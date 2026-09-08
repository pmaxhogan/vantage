#!/usr/bin/env python3
"""uptodown-dl.py <package> <version> <arch> <out> [container]

Second stock source for Claude (fallback behind apkcombo). Walks the app's
/versions list on Uptodown to find the numeric file id matching the requested
version, then fetches that version's download page.

Uptodown's real file link only comes back from an ajax endpoint
(/ajax/app/<appId>/file/<fileId>/download-url) that requires a SOLVED
Cloudflare Turnstile token - confirmed by reading the page's own download.js:
its click handler awaits a Turnstile "solved" status before it ever POSTs to
that endpoint. curl_cffi's Chrome TLS impersonation gets past Cloudflare's
earlier fingerprint block (these pages load fine, unlike a flat 403), but it
cannot solve an interactive JS challenge, and this resolver does not attempt
to - that would be building a CAPTCHA bypass, not a mirror client. So in
practice this source resolves the version/page chain correctly and then fails
cleanly, and download-apk.sh falls through to whatever's next (or the overall
download fails, same as any other source going dark). It does try one ungated
path first: some Uptodown layouts expose a direct data-url/data-url-ext
attribute on the download button with no Turnstile round trip - if that ever
applies here, this resolver uses it automatically.

Exit 0 on a written file, non-zero otherwise (reason on stderr).
"""
import re
import sys

try:
    from curl_cffi import requests
except Exception as e:  # pragma: no cover
    print(f"  [uptodown-py] curl_cffi not available: {e}", file=sys.stderr)
    sys.exit(3)

# Uptodown per-app subdomain slugs.
SLUGS = {
    "com.anthropic.claude": "claude",
}


def log(*a):
    print("  [uptodown-py]", *a, file=sys.stderr)


def find_file_id(versions_html, want_version):
    """Each row on /versions is one <div data-url="..." data-version-id="ID"
    data-extra-url="download">...<span class="version">VER</span>...</div>
    block. Return the numeric id whose version span matches want_version."""
    for vid, body in re.findall(
        r'<div data-url="[^"]*" data-version-id="(\d+)"[^>]*>(.*?)</div>',
        versions_html,
        re.S,
    ):
        m = re.search(r'<span class="version">([^<]+)</span>', body)
        if m and m.group(1).strip() == want_version:
            return vid
    return None


def main():
    if len(sys.argv) < 5:
        log("usage: uptodown-dl.py <package> <version> <arch> <out> [bundle]")
        return 2
    pkg, ver, arch, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    slug = SLUGS.get(pkg)
    if not slug:
        log("no Uptodown slug mapping for", pkg)
        return 1

    s = requests.Session(impersonate="chrome", timeout=60)
    base = f"https://{slug}.en.uptodown.com/android"

    log("versions page", f"{base}/versions")
    r = s.get(f"{base}/versions", headers={"Referer": base})
    if r.status_code != 200:
        log("versions page HTTP", r.status_code)
        return 1

    file_id = find_file_id(r.text, ver)
    if not file_id:
        log(f"version {ver} not found on the versions page (sparse history or already rotated off)")
        return 1
    log("file id", file_id)

    dlpage = f"{base}/download/{file_id}"
    r = s.get(dlpage, headers={"Referer": f"{base}/versions"})
    if r.status_code != 200:
        log("download page HTTP", r.status_code)
        return 1

    m = re.search(r'<button[^>]*id="detail-download-button"[^>]*>', r.text)
    if not m:
        log("no #detail-download-button on the download page (layout change)")
        return 1
    btn = m.group(0)

    # Ungated fallback: a direct data-url/data-url-ext on the button itself,
    # no Turnstile round trip. Try it before giving up.
    du = re.search(r'data-url="([^"]+)"', btn)
    due = re.search(r'data-url-ext="([^"]+)"', btn)
    direct = due.group(1) if due else (("https://dw.uptodown.com/dwn/" + du.group(1)) if du else None)
    if direct:
        log("direct link found on the button (no Turnstile needed)", direct.split("?")[0])
        d = s.get(direct, headers={"Referer": dlpage})
        if d.status_code == 200 and d.content:
            with open(out, "wb") as fh:
                fh.write(d.content)
            log(f"wrote {len(d.content)} bytes -> {out}")
            return 0
        log("direct link fetch failed, HTTP", d.status_code)

    # The real path: /ajax/app/<appId>/file/<fileId>/download-url needs a
    # solved Cloudflare Turnstile token (see module docstring) - not attempted
    # here. Fail cleanly so the caller falls through to the next source.
    log("download gated behind Cloudflare Turnstile - no ungated link on this page, giving up")
    return 1


if __name__ == "__main__":
    sys.exit(main())
