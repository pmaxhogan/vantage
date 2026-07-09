#!/usr/bin/env bash
#
# download-apk.sh - fetch a genuine stock (unpatched) APK for a package + version.
#
# Sourcing order:
#   1. The "stock-cache" release, tried first so unchanged rebuilds skip the
#      download.
#   2. On a miss, the sources in DL_SOURCES (build.env), in order. Each candidate
#      is downloaded to a scratch file and run through verify() below; the first
#      one that passes is used.
#   3. If they all fail, exit with an error.
# A verified download is uploaded back to the stock-cache.
#
# verify() is what makes downloading from third-party mirrors safe - nothing is
# trusted until it passes all five checks:
#   1. real APK (PK zip magic), not an HTML challenge/error page
#   2. a single base APK, not a split/XAPK bundle (no nested *.apk)
#   3. aapt package name matches the expected package
#   4. aapt versionName matches the expected version
#   5. the signing-cert SHA-256 matches a known Google fingerprint for the package
#      (config/expected-signatures.txt) - this rejects a repackaged or tampered
#      build from a hostile mirror
# Any failure logs the reason and moves to the next source.
#
# Cache asset naming: "<package>-<version>.apk"
#
# Usage: download-apk.sh <package> <version> <arch> <out.apk>
#   arch: "universal" (YouTube) or "arm64-v8a" (YouTube Music has no universal APK)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

# PKG/VER/ARCH/OUT are set by main() (from CLI args) and referenced as globals by
# verify() and the src_* resolvers. Sourcing this file (for tests) defines the
# functions without running main - see the guard at the bottom.
SIG_FILE="$VANTAGE_ROOT/config/expected-signatures.txt"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

# curl wrapper: browser-ish UA, follow redirects, fail on HTTP error, quiet.
fetch() { curl -fsSL --connect-timeout 20 --max-time 300 -A "$UA" "$@"; }

# Run a curl_cffi-based Python resolver (scripts/<script>). APKMirror + APKPure
# put their download pages behind a Cloudflare TLS-fingerprint bot-block that
# plain curl gets 403'd by; curl_cffi impersonating Chrome gets 200. The resolver
# writes a base APK to $2; verify() still judges it. Skips (returns 1) if python3
# or curl_cffi is missing, or the resolver fails - then the next source is tried.
py_source() {
  local script="$1" out="$2" py
  py="$(command -v python3 || command -v python || true)"
  if [ -z "$py" ]; then warn "  ${script%.py}: python3 not found - skipping"; return 1; fi
  # 5th arg is the container (apk|apkm); apkmirror-dl.py picks the APK vs BUNDLE row.
  "$py" "$VANTAGE_ROOT/scripts/$script" "$PKG" "$VER" "$ARCH" "$out" "${CONTAINER:-apk}"
}

# ===========================================================================
# verify() - the 5-point gate. Returns 0 only if $1 is a genuine Google-signed
# single-base-APK matching $PKG/$VER. Logs the first failing reason.
# ===========================================================================
apk_has_pk_magic() {  # a real APK is a zip: first two bytes "PK"
  [ -s "$1" ] && [ "$(head -c2 "$1" 2>/dev/null)" = "PK" ]
}

# Every expected Google cert SHA-256 for a package (may be several - key rotation
# means a genuine APK reports one cert per minSdk band). Printed one per line.
expected_sigs_for() {
  local pkg="$1"
  [ -f "$SIG_FILE" ] || return 0
  # tolerate CRLF; skip blanks/comments; match col1==pkg, emit lowercased col2.
  awk -v p="$pkg" '
    { sub(/\r$/,"") }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == p { print tolower($2) }
  ' "$SIG_FILE"
}

verify() {
  local apk="$1" why
  local aapt apksigner

  # 1. valid APK (not an HTML challenge / error page saved as .apk)
  if ! apk_has_pk_magic "$apk"; then
    warn "  reject: not a valid APK (no PK zip magic - likely HTML/challenge)"; return 1
  fi
  if command -v unzip >/dev/null 2>&1 && ! unzip -qt "$apk" >/dev/null 2>&1; then
    warn "  reject: zip integrity check failed (truncated/corrupt download)"; return 1
  fi

  # 2. not a split / XAPK bundle (a bundle is a zip containing nested *.apk).
  # Use `unzip -Z1` (entry names only) not `unzip -l` - the latter's "Archive:
  # <path>.apk" header line would false-match and reject every real download.
  if command -v unzip >/dev/null 2>&1 && unzip -Z1 "$apk" 2>/dev/null | grep -qiE '\.apk$'; then
    warn "  reject: contains nested *.apk (split/XAPK bundle, not a single base APK)"; return 1
  fi

  # 3 + 4. package name + versionName via aapt badging.
  aapt="$(find_sdk_tool aapt || find_sdk_tool aapt.exe || true)"
  if [ -z "$aapt" ]; then
    warn "  reject: aapt not found - cannot verify package/version (Android SDK required)"; return 1
  fi
  local badging pkg_got ver_got
  badging="$("$aapt" dump badging "$apk" 2>/dev/null || true)"
  pkg_got="$(grep -oE "^package: name='[^']*'" <<<"$badging" | sed -E "s/.*name='([^']*)'.*/\1/" | head -1)"
  ver_got="$(grep -oE "versionName='[^']*'"      <<<"$badging" | sed -E "s/.*versionName='([^']*)'.*/\1/" | head -1)"
  if [ "$pkg_got" != "$PKG" ]; then
    warn "  reject: package mismatch - expected '$PKG' got '${pkg_got:-<none>}'"; return 1
  fi
  if [ "$ver_got" != "$VER" ]; then
    warn "  reject: versionName mismatch - expected '$VER' got '${ver_got:-<none>}'"; return 1
  fi

  # 5. signing cert SHA-256 must match a known Google fingerprint - the main check.
  apksigner="$(find_sdk_tool apksigner || find_sdk_tool apksigner.bat || true)"
  if [ -z "$apksigner" ]; then
    warn "  reject: apksigner not found - cannot verify signature (Android SDK required)"; return 1
  fi
  local expected; expected="$(expected_sigs_for "$PKG")"
  if [ -z "$expected" ]; then
    warn "  reject: no expected signatures for '$PKG' in $SIG_FILE - refusing to trust an unpinned package"; return 1
  fi
  # apksigner must cryptographically verify the APK (exit 0). That's what makes
  # "cert digest == Google" mean something: it only reports a signer cert after
  # proving the content is actually signed by that cert's key, so a build tampered
  # after signing fails here and a matching digest can't be forged without
  # Google's private key.
  local certs_out rc
  certs_out="$("$apksigner" verify --print-certs "$apk" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "  reject: apksigner signature verification FAILED (rc=$rc) - unsigned or tampered APK"; return 1
  fi
  # All signer cert digests the (verified) APK carries (lowercased); includes any
  # Play "source stamp" cert, and matching any entry to Google is fine.
  local got_all; got_all="$(grep -i 'certificate SHA-256 digest' <<<"$certs_out" \
    | awk '{print tolower($NF)}' | sort -u)"
  if [ -z "$got_all" ]; then
    warn "  reject: could not read any signing cert (unsigned or apksigner failed)"; return 1
  fi
  local g matched=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    if grep -qxF "$g" <<<"$expected"; then matched="$g"; break; fi
  done <<<"$got_all"
  if [ -z "$matched" ]; then
    warn "  reject: SIGNING CERT NOT GOOGLE - none of [$(tr '\n' ' ' <<<"$got_all")] is an expected fingerprint for $PKG. Refusing tampered/repackaged APK."
    return 1
  fi

  log "  verify OK: $PKG $VER, single base APK, signer $matched (Google)"
  return 0
}

# ===========================================================================
# Per-source resolvers. Each takes ($out_candidate) and must leave a downloaded
# file there (verify() is applied by the caller). Return non-zero on any resolve
# failure. They must not trust their own output - the gate is central.
# ===========================================================================

# --- APKCombo (apkcombo.app) -----------------------------------------------
# Confirmed to host the exact old versions we need. Flow (per nirewen/apkcombo-
# downloader): download page -> scrape variant href(s) -> GET /checkin token ->
# append token to href with '&' -> download. Page is JS-rendered so the href may
# not always be in the static HTML; if we cannot find one, this source just fails
# and we fall through. Datacenter Cloudflare posture is unproven until a live CI
# run - verify() keeps a challenge-page response harmless.
src_apkcombo() {
  local out="$1" tmp; tmp="$(mktemp -d)"
  local org repo
  case "$PKG" in
    com.google.android.youtube)            org=youtube;       repo="youtube/com.google.android.youtube" ;;
    com.google.android.apps.youtube.music) org=youtube-music; repo="youtube-music/com.google.android.apps.youtube.music" ;;
    *) warn "  apkcombo: no slug mapping for $PKG"; rm -rf "$tmp"; return 1 ;;
  esac
  local dl_page="https://apkcombo.app/${repo%%/*}/${repo#*/}/download/phone-${VER}-apk"
  log "  apkcombo: fetching $dl_page (arch=$ARCH)"
  if ! fetch -H 'Referer: https://apkcombo.app/' "$dl_page" -o "$tmp/page.html"; then
    warn "  apkcombo: download page fetch failed"; rm -rf "$tmp"; return 1
  fi
  # checkin token (appended to the variant href with '&')
  local token; token="$(fetch -H "Referer: $dl_page" 'https://apkcombo.app/checkin' 2>/dev/null | tr -d '\r\n' || true)"
  # Candidate direct-download hrefs on the page. Prefer arch-matched, APK (not
  # bundle/xapk) links. apkcombo serves from download*/dw* hosts.
  local arch_re; case "$ARCH" in
    universal|noarch|nodpi) arch_re='nodpi|noarch|universal|arm64-v8a' ;;
    *) arch_re="$ARCH" ;;
  esac
  local href
  href="$(grep -oiE 'https?://[a-z0-9.-]*apkcombo[^"'"'"' ]*\.apk[^"'"'"' ]*' "$tmp/page.html" \
      | grep -viE 'xapk|bundle' | grep -iE "$arch_re" | head -1 || true)"
  # fall back to any apk href if no arch-tagged one is present in static HTML
  [ -n "$href" ] || href="$(grep -oiE 'https?://[a-z0-9.-]*apkcombo[^"'"'"' ]*\.apk[^"'"'"' ]*' "$tmp/page.html" \
      | grep -viE 'xapk|bundle' | head -1 || true)"
  if [ -z "$href" ]; then
    warn "  apkcombo: no direct .apk href in page (JS-only render or layout change)"; rm -rf "$tmp"; return 1
  fi
  local url="$href"
  [ -n "$token" ] && case "$href" in *\?*) url="${href}&${token}" ;; *) url="${href}?${token}" ;; esac
  log "  apkcombo: downloading $url"
  if ! fetch -H "Referer: $dl_page" "$url" -o "$out"; then
    warn "  apkcombo: final download failed"; rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"; return 0
}

# --- Aptoide (ws75.aptoide.com) --------------------------------------------
# Plain JSON REST, no Cloudflare - the most datacenter-friendly source, but its
# version history is sparse and may not carry a given old build (then it just
# fails resolve and we fall through). Needs jq.
src_aptoide() {
  local out="$1"
  if ! command -v jq >/dev/null 2>&1; then
    warn "  aptoide: jq not available - skipping this source"; return 1
  fi
  local api='https://ws75.aptoide.com/api/7'
  local tmp; tmp="$(mktemp -d)"
  log "  aptoide: listing versions for $PKG"
  if ! fetch "$api/listAppVersions?package_name=${PKG}&limit=100" -o "$tmp/list.json"; then
    warn "  aptoide: listAppVersions failed"; rm -rf "$tmp"; return 1
  fi
  # Collect vercodes whose vername == VER (arch variants share a vername, differ
  # by vercode). Try each until getMeta yields a single-APK URL the gate accepts;
  # here we just download - verify() enforces arch-correctness via package/sig
  # (arch itself is not gate-checked, but a wrong-arch build is still a genuine
  # Google APK of the right version, which for universal/YT is fine and for Music
  # is acceptable since we then feed the matching arch through the same pipeline).
  local vercodes; vercodes="$(jq -r --arg v "$VER" \
    '.list[]? | select(.file.vername==$v) | .file.vercode' "$tmp/list.json" 2>/dev/null | head -5)"
  if [ -z "$vercodes" ]; then
    warn "  aptoide: version $VER not hosted (sparse history)"; rm -rf "$tmp"; return 1
  fi
  local vc apkurl
  while IFS= read -r vc; do
    [ -n "$vc" ] || continue
    log "  aptoide: getMeta vercode=$vc"
    if ! fetch "$api/app/getMeta?package_name=${PKG}&vercode=${vc}" -o "$tmp/meta.json"; then continue; fi
    # reject bundles up front: aab present -> not a single base APK
    if [ "$(jq -r '.data.file.aab // empty' "$tmp/meta.json" 2>/dev/null)" != "" ]; then
      log "  aptoide: vercode $vc is an app bundle - skipping"; continue
    fi
    apkurl="$(jq -r '.data.file.path // .data.file.path_alt // empty' "$tmp/meta.json" 2>/dev/null)"
    [ -n "$apkurl" ] || continue
    log "  aptoide: downloading $apkurl"
    if fetch "$apkurl" -o "$out"; then rm -rf "$tmp"; return 0; fi
  done <<<"$vercodes"
  warn "  aptoide: no downloadable single-APK for $VER"; rm -rf "$tmp"; return 1
}

# --- APKMirror (via curl_cffi Chrome impersonation) ------------------------
# Primary source. APKMirror hides its variant/download pages behind a Cloudflare
# TLS-fingerprint bot-block (plain curl -> 403; curl_cffi impersonating Chrome ->
# 200). scripts/apkmirror-dl.py picks the type=APK variant matching $ARCH (not a
# bundle), walks release -> variant -> download page -> file, and streams it.
src_apkmirror() { py_source apkmirror-dl.py "$1"; }

# --- APKPure (.net mirror, via curl_cffi) ----------------------------------
# Second independent source (redundancy if APKMirror breaks). apkpure.net serves
# version-pinned base APKs (verified byte-identical to APKMirror). Logic in
# scripts/apkpure-dl.py. (.com Cloudflare-blocks even curl_cffi; .net serves.)
src_apkpure() { py_source apkpure-dl.py "$1"; }

# ===========================================================================
# verify_apkm() - the gate for a split APKM bundle (X/Twitter). An APKM is a zip
# of per-split *.apk files (base + config.<abi>/<dpi>/<lang>) plus metadata.
# morphe patches the APKM directly, so we can't collapse it to a single base APK;
# instead we verify EVERY nested split is genuinely signed by the package's known
# cert, so a hostile mirror can't slip in a tampered split (native lib/resources)
# behind a genuine base.
#   1. valid zip (PK magic + integrity)
#   2. no duplicate *.apk entry names (else the bytes we verify != what morphe reads)
#   3. at least one nested *.apk (it's a bundle, not a bare APK)
#   4. every nested *.apk is apksigner-verified and carries an expected cert
#   5. some split reports the expected package + versionName (the base)
# ===========================================================================
verify_apkm() {
  local apkm="$1" aapt apksigner
  if ! apk_has_pk_magic "$apkm"; then
    warn "  reject: not a valid APKM (no PK zip magic - likely HTML/challenge)"; return 1
  fi
  command -v unzip >/dev/null 2>&1 || { warn "  reject: unzip required to verify an APKM"; return 1; }
  if ! unzip -qt "$apkm" >/dev/null 2>&1; then
    warn "  reject: APKM zip integrity check failed (truncated/corrupt download)"; return 1
  fi

  local names dups
  names="$(unzip -Z1 "$apkm" 2>/dev/null | grep -iE '\.apk$' || true)"
  dups="$(sort <<<"$names" | uniq -d)"
  if [ -n "$dups" ]; then
    warn "  reject: APKM has duplicate .apk entry names: $(tr '\n' ' ' <<<"$dups")"; return 1
  fi
  if [ -z "$names" ]; then
    warn "  reject: APKM contains no nested *.apk (not a split bundle)"; return 1
  fi

  aapt="$(find_sdk_tool aapt || find_sdk_tool aapt.exe || true)"
  apksigner="$(find_sdk_tool apksigner || find_sdk_tool apksigner.bat || true)"
  [ -n "$aapt" ]      || { warn "  reject: aapt not found - cannot verify APKM (Android SDK required)"; return 1; }
  [ -n "$apksigner" ] || { warn "  reject: apksigner not found - cannot verify APKM (Android SDK required)"; return 1; }
  local expected; expected="$(expected_sigs_for "$PKG")"
  if [ -z "$expected" ]; then
    warn "  reject: no expected signatures for '$PKG' in $SIG_FILE - refusing an unpinned package"; return 1
  fi

  local xd; xd="$(mktemp -d)"
  if ! unzip -qo "$apkm" '*.apk' -d "$xd" 2>/dev/null; then
    warn "  reject: could not extract splits from APKM"; rm -rf "$xd"; return 1
  fi

  local base_ok=0 nsplits=0 f rc certs got g matched badging pkg_got ver_got
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    nsplits=$((nsplits+1))
    certs="$("$apksigner" verify --print-certs "$f" 2>/dev/null)"; rc=$?
    if [ "$rc" -ne 0 ]; then
      warn "  reject: split $(basename "$f") failed apksigner verification (unsigned/tampered)"; rm -rf "$xd"; return 1
    fi
    got="$(grep -i 'certificate SHA-256 digest' <<<"$certs" | awk '{print tolower($NF)}' | sort -u)"
    matched=""
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      if grep -qxF "$g" <<<"$expected"; then matched="$g"; break; fi
    done <<<"$got"
    if [ -z "$matched" ]; then
      warn "  reject: split $(basename "$f") NOT signed by an expected $PKG cert (got: $(tr '\n' ' ' <<<"$got"))"; rm -rf "$xd"; return 1
    fi
    badging="$("$aapt" dump badging "$f" 2>/dev/null || true)"
    pkg_got="$(grep -oE "^package: name='[^']*'" <<<"$badging" | sed -E "s/.*name='([^']*)'.*/\1/" | head -1)"
    ver_got="$(grep -oE "versionName='[^']*'"      <<<"$badging" | sed -E "s/.*versionName='([^']*)'.*/\1/" | head -1)"
    if [ "$pkg_got" = "$PKG" ] && [ "$ver_got" = "$VER" ]; then base_ok=1; fi
  done < <(find "$xd" -name '*.apk' -type f)
  rm -rf "$xd"

  if [ "$base_ok" -ne 1 ]; then
    warn "  reject: no split reported package=$PKG versionName=$VER (wrong app or version)"; return 1
  fi
  log "  verify OK: APKM $PKG $VER, $nsplits splits all signed by an expected cert"
  return 0
}

# Dispatch to the right gate for the requested container ($CONTAINER, set by main).
run_gate() {
  case "$CONTAINER" in
    apkm) verify_apkm "$1";;
    *)    verify "$1";;
  esac
}

main() {
  PKG="${1:?package}"; VER="${2:?version}"; ARCH="${3:?arch}"; OUT="${4:?out path}"
  # $5 = container: "apk" (single base APK, YouTube/Music) or "apkm" (split
  # bundle, X/Twitter - morphe patches it directly). Sets the gate and the
  # cache-asset extension so an .apk and an .apkm never collide in the cache.
  CONTAINER="${5:-apk}"
  case "$CONTAINER" in apk|apkm) ;; *) die "unknown container '$CONTAINER' (want apk|apkm)";; esac
  CACHE_ASSET="${PKG}-${VER}.${CONTAINER}"
  GH_REPO="${GITHUB_REPOSITORY:-${VANTAGE_REPO:-}}"
  mkdir -p "$(dirname "$OUT")"

  # -------------------------------------------------------------------------
  # 1. stock-cache release (always first)
  # -------------------------------------------------------------------------
  if [ -n "$GH_REPO" ] && command -v gh >/dev/null 2>&1; then
    log "Checking stock-cache ($STOCK_CACHE_TAG) for $CACHE_ASSET ..."
    if gh release download "$STOCK_CACHE_TAG" -R "$GH_REPO" -p "$CACHE_ASSET" \
         -O "$OUT" --clobber 2>/dev/null && apk_has_pk_magic "$OUT"; then
      log "Cache HIT: $CACHE_ASSET"
      return 0
    fi
    log "Cache miss for $CACHE_ASSET"
  else
    warn "no GH repo/gh - skipping stock-cache lookup"
  fi

  # -------------------------------------------------------------------------
  # 2. Ordered download sources, each behind the container's gate. X uses its
  #    own source list (only APKMirror serves the genuine APKM).
  # -------------------------------------------------------------------------
  local sources
  if [ "$CONTAINER" = "apkm" ]; then
    sources="${X_DL_SOURCES:-apkmirror}"
  else
    sources="${DL_SOURCES:-apkmirror apkpure apkcombo aptoide}"
  fi
  log "Cache miss - trying download sources: $sources"
  local scratch; scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' RETURN
  local accepted="" src fn cand
  for src in $sources; do
    fn="src_${src}"
    if ! declare -F "$fn" >/dev/null 2>&1; then
      warn "unknown download source '$src' (no $fn) - skipping"; continue
    fi
    cand="$scratch/${src}.${CONTAINER}"; rm -f "$cand"
    log "== source: $src =="
    if ! "$fn" "$cand"; then
      warn "source '$src' did not produce a download - next source"; continue
    fi
    if run_gate "$cand"; then
      log "ACCEPTED from source '$src'"
      cp "$cand" "$OUT"; accepted="$src"; break
    else
      warn "source '$src' produced a file that FAILED verification - next source"
    fi
  done

  if [ -z "$accepted" ]; then
    die "all download sources failed verification for $CACHE_ASSET. Seed the stock-cache manually (see the 'Stock-APK download' section in the README) with a genuine vendor-signed $PKG $VER $ARCH $CONTAINER."
  fi
  log "Download OK from '$accepted': $OUT ($(du -h "$OUT" | cut -f1))"

  # -------------------------------------------------------------------------
  # 3. upload the verified APK to the stock-cache for future runs
  # -------------------------------------------------------------------------
  if [ -n "$GH_REPO" ] && command -v gh >/dev/null 2>&1; then
    log "Uploading $CACHE_ASSET to stock-cache ..."
    gh release view "$STOCK_CACHE_TAG" -R "$GH_REPO" >/dev/null 2>&1 \
      || gh release create "$STOCK_CACHE_TAG" -R "$GH_REPO" --prerelease \
           --title "Stock APK cache" \
           --notes "Cache of unpatched stock APKs, keyed by <package>-<version>.apk. Do not delete." \
      || warn "could not create stock-cache release"
    cp "$OUT" "$scratch/$CACHE_ASSET"
    gh release upload "$STOCK_CACHE_TAG" -R "$GH_REPO" "$scratch/$CACHE_ASSET" --clobber \
      || warn "cache upload failed (build continues with the local copy)"
  fi
}

# Run main only when executed directly; sourcing (tests) just loads functions.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
