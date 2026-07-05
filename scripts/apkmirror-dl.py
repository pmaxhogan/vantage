#!/usr/bin/env python3
"""apkmirror-dl.py <package> <version> <arch> <out>

Resolve + download a single base APK (variant type = APK, matching arch) from
APKMirror. APKMirror puts its variant + download pages behind Cloudflare's
TLS/JA3 fingerprint bot-block, so plain curl gets a 403; curl_cffi impersonating
Chrome gets 200. This helper does the release -> variant -> download-page ->
file chain and streams the APK to <out>.

It deliberately doesn't verify the APK - download-apk.sh's 5-point gate (Google
signature, single base APK, package/version) does that. Here we only pick the
right variant (type APK, not a bundle; arch match) and fetch it.

Exit 0 on a written file, non-zero otherwise (with a reason on stderr).
"""
import re
import sys

try:
    from curl_cffi import requests
except Exception as e:  # pragma: no cover
    print(f"  [apkmirror-py] curl_cffi not available: {e}", file=sys.stderr)
    sys.exit(3)

BASE = "https://www.apkmirror.com"
SLUGS = {
    "com.google.android.youtube": "google-inc/youtube/youtube",
    "com.google.android.apps.youtube.music": "google-inc/youtube-music/youtube-music",
}
# arch aliases: what row-text tokens count as a match for a requested arch.
ARCH_ALIASES = {
    "universal": ("universal", "noarch"),
    "arm64-v8a": ("arm64-v8a",),
    "armeabi-v7a": ("armeabi-v7a",),
    "x86": ("x86",),
    "x86_64": ("x86_64",),
}


def log(*a):
    print("  [apkmirror-py]", *a, file=sys.stderr)


def pick_variant(html_text, want_arch):
    """Return the /apk/.../download/ variant path for the type=APK row whose arch
    matches want_arch, or None. Rows are the release page's download table rows."""
    aliases = ARCH_ALIASES.get(want_arch, (want_arch,))
    for row in re.findall(r'<div class="table-row[^"]*">.*?</div>\s*</div>', html_text, re.S):
        m = re.search(r'href="(/apk/[^"]*-android-apk-download/)"', row)
        if not m:
            continue
        text = re.sub(r"<[^>]+>", " ", row)
        text = re.sub(r"\s+", " ", text)
        # A BUNDLE row says "BUNDLE"; a base-APK row shows "APK" and no "BUNDLE".
        if re.search(r"\bBUNDLE\b", text):
            continue
        if not re.search(r"\bAPK\b", text):
            continue
        low = text.lower()
        # For arm64-v8a we must not accept an armeabi-v7a-only row, etc. Require an
        # exact arch token and (for arm64) reject if only armeabi is present.
        if any(a in low for a in aliases):
            if want_arch == "arm64-v8a" and "arm64-v8a" not in low:
                continue
            return m.group(1)
    return None


def main():
    if len(sys.argv) < 5:
        log("usage: apkmirror-dl.py <package> <version> <arch> <out>")
        return 2
    pkg, ver, arch, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    slug = SLUGS.get(pkg)
    if not slug:
        log("no APKMirror slug mapping for", pkg)
        return 1

    s = requests.Session(impersonate="chrome", timeout=120)

    rel = f"{BASE}/apk/{slug}-{ver.replace('.', '-')}-release/"
    log("release page", rel)
    r = s.get(rel, headers={"Referer": BASE + "/"})
    if r.status_code != 200:
        log("release page HTTP", r.status_code)
        return 1

    vpath = pick_variant(r.text, arch)
    if not vpath:
        log(f"no type=APK variant matching arch={arch} on the release page")
        return 1
    log("variant", vpath)

    r = s.get(BASE + vpath, headers={"Referer": rel})
    if r.status_code != 200:
        log("variant page HTTP", r.status_code)
        return 1
    dl = re.search(r'href="(/apk/[^"]*/download/\?key=[^"]+)"', r.text)
    if not dl:
        log("no /download/?key= link on the variant page")
        return 1
    dlpage = BASE + dl.group(1).replace("&amp;", "&")
    log("download page", dlpage)

    r = s.get(dlpage, headers={"Referer": BASE + vpath})
    if r.status_code != 200:
        log("download page HTTP", r.status_code)
        return 1
    f = re.search(r'href="(/wp-content/[^"]*download\.php\?[^"]+)"', r.text)
    if not f:
        log("no download.php link on the download page")
        return 1
    furl = BASE + f.group(1).replace("&amp;", "&")
    log("fetching file", furl.split("?")[0])

    d = s.get(furl, headers={"Referer": dlpage}, stream=True)
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
