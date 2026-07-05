#!/usr/bin/env python3
"""apkpure-dl.py <package> <version> <arch> <out>

Second stock-APK source (redundancy for APKMirror). Resolves a version-pinned
base APK from APKPure's `.net` mirror and streams it to <out>. APKPure's `.com`
host Cloudflare-blocks scripted clients (403) even via curl_cffi; the `.net`
mirror serves fine with Chrome impersonation.

The version download page exposes `id="download_link"` ->
`https://d.apkpure.net/b/APK/<pkg>?versionCode=<code>&nc=<arches>&sv=..`. The
`/b/APK/` path asks for a single base APK (not an XAPK bundle). We just fetch it;
download-apk.sh's gate verifies Google signature / single-APK / package+version.

Exit 0 on a written file, non-zero otherwise (reason on stderr).
"""
import html
import re
import sys

try:
    from curl_cffi import requests
except Exception as e:  # pragma: no cover
    print(f"  [apkpure-py] curl_cffi not available: {e}", file=sys.stderr)
    sys.exit(3)

# APKPure URL name-slugs per package (the human name segment before the id).
SLUGS = {
    "com.google.android.youtube": "youtube",
    "com.google.android.apps.youtube.music": "youtube-music",
}


def log(*a):
    print("  [apkpure-py]", *a, file=sys.stderr)


def main():
    if len(sys.argv) < 5:
        log("usage: apkpure-dl.py <package> <version> <arch> <out>")
        return 2
    pkg, ver, arch, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    name = SLUGS.get(pkg)
    if not name:
        log("no APKPure slug mapping for", pkg)
        return 1

    s = requests.Session(impersonate="chrome", timeout=120)
    page = f"https://apkpure.net/{name}/{pkg}/download/{ver}"
    log("download page", page)
    r = s.get(page, headers={"Referer": "https://apkpure.net/"})
    if r.status_code != 200:
        log("download page HTTP", r.status_code)
        return 1

    # Prefer the explicit base-APK link; refuse an XAPK link (bundle -> gate reject).
    m = re.search(r'id="download_link"[^>]*href="([^"]+)"', r.text)
    if not m:
        m = re.search(r'href="(https?://d\.apkpure\.net/b/APK/[^"]+)"', r.text)
    if not m:
        log("no base-APK (/b/APK/) download link on the page (may be XAPK-only)")
        return 1
    url = html.unescape(m.group(1))
    if "/b/XAPK/" in url:
        log("resolved link is an XAPK bundle - refusing")
        return 1
    log("fetching", url.split("?")[0])

    d = s.get(url, headers={"Referer": page}, stream=True)
    if d.status_code != 200:
        log("file HTTP", d.status_code)
        return 1
    n = 0
    with open(out, "wb") as fh:
        for chunk in d.iter_content(1 << 16):
            if chunk:
                fh.write(chunk)
                n += len(chunk)
    log(f"wrote {n} bytes -> {out}")
    return 0 if n > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
