#!/usr/bin/env bash
#
# build-postbox.sh - Postbox (patched Instagram) build orchestrator, deliberately
# SEPARATE from build.sh and build-x.sh so a flaky Instagram build can never take
# the YouTube nightly or X down with it. Postbox is Instagram with the feed,
# Reels tab, Explore/Search and other people's post grids locked out, cloned to
# its own package (app.vantage.postbox) so it installs next to stock Instagram.
# It uses the same pmaxhogan/piko patch bundle as X and publishes its OWN GitHub
# release, tagged "postbox-v...".
#
#   resolve piko(float) -> (skip?) -> download cli+bundle -> resolve Instagram
#   version -> keystore preflight -> download APKM -> patch -> assert -> stage ->
#   release.
#
# State is the latest postbox-v* release's built-versions-postbox.json, never a
# committed file.
#
# The Postbox release is published with --latest=false on purpose: the repo's
# "latest release" slot must stay on a YouTube build, since that is the one
# carrying obtainium-config.json (the README's install link points at
# /releases/latest). Postbox also ships a copy of that config as a release asset.
#
# There is no cron. The workflow fires on pushes to Postbox build files, on the
# piko fork's repository_dispatch, and by hand; the workflow passes --force for
# the first two, so the skip check below only matters for a manual dispatch.
#
# Patch selection: config/postbox-options.json carries every patch in the bundle
# (X ones included) with an explicit "enabled", and patch.sh passes --exclusive,
# so only the options-file enabled set runs; a default-on patch added upstream
# later cannot sneak in. (Dependencies of an enabled patch are still pulled in by
# morphe; assert.sh's forbidden list catches one that is on the do-not-ship list.)
#
# Usage: build-postbox.sh [--force] [--output-dir DIR] [--release]
#   --force       build even if the piko version is unchanged
#   --output-dir  where staged assets land (default build/release-postbox)
#   --release     create/update the GitHub release (needs gh + write perms)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

FORCE="" OUTDIR="$VANTAGE_ROOT/build/release-postbox" DO_RELEASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE="1"; shift;;
    --output-dir) OUTDIR="$2"; shift 2;;
    --release) DO_RELEASE="1"; shift;;
    *) die "unknown arg: $1";;
  esac
done

command -v java >/dev/null 2>&1 || die "java not found (need Java 21+ for morphe-cli)"
command -v gh   >/dev/null 2>&1 || die "gh CLI not found"
command -v jq   >/dev/null 2>&1 || die "jq not found"

WORK="$VANTAGE_ROOT/build"; TOOLS="$WORK/tools"; STOCK="$WORK/stock"; OUT="$WORK/out"; TMPROOT="/tmp/vt"
mkdir -p "$WORK" "$TOOLS" "$STOCK" "$OUT" "$OUTDIR" "$TMPROOT"
GH_REPO="${GITHUB_REPOSITORY:-${VANTAGE_REPO:-}}"
A="$VANTAGE_ROOT/config/assertions"
OPTS="$VANTAGE_ROOT/config/postbox-options.json"

# ---- options-file guards ----------------------------------------------------
# Two refusals, both on the options file itself and both before any network or
# patch work. assert.sh re-checks the forbidden list against what actually
# applied; this catches the mistake at its source.
#   1. an enabled patch that is named in postbox-forbidden.txt (download,
#      anonymous-viewing, ad-block, ... - see that file for why)
#   2. any option whose key looks like a test/debug/trace switch and is truthy on
#      an enabled patch (a debug-trace option is planned and must never ship on;
#      same idea as the enableTestHooks refusal in build-x.sh, but generic)
# A patch entry with no "enabled" key counts as enabled, to fail safe.
check_postbox_options() {
  local opts="$1" forbidden_file="$2" enabled hit n
  [ -f "$opts" ] || die "missing options file $opts"
  jq empty "$opts" 2>/dev/null || die "$opts is not valid JSON"
  enabled="$(jq -r '.[].patches | to_entries[] | select(.value.enabled != false) | .key' "$opts")"
  local -a forbid; read_list forbid "$forbidden_file"
  for n in "${forbid[@]:-}"; do
    [ -z "$n" ] && continue
    if grep -Fxq -- "$n" <<<"$enabled"; then
      die "$opts enables forbidden patch '$n' (see $(basename "$forbidden_file")) - refusing to build"
    fi
  done
  hit="$(jq -r '
    .[].patches | to_entries[] | select(.value.enabled != false) | .key as $p
    | (.value.options // {}) | to_entries[]
    | select(.key | test("test|debug|trace"; "i"))
    | select(.value
        | if type == "boolean" then .
          elif type == "number" then . != 0
          elif type == "string" then (ascii_downcase | IN("", "false", "0", "no", "off", "null") | not)
          elif type == "null" then false
          else true end)
    | "\($p).\(.key)=\(.value)"' "$opts")"
  [ -z "$hit" ] || die "$opts turns on a test/debug/trace option, refusing to build a release APK: $(tr '\n' ' ' <<<"$hit")"
  log "options file OK: no forbidden patch enabled, no test/debug/trace option on"
}
check_postbox_options "$OPTS" "$A/postbox-forbidden.txt"

# ---- signing keystore -----------------------------------------------------
KEYSTORE="$WORK/vantage.keystore"
resolve_signing_keystore "$KEYSTORE"

# ---- resolve piko (floats to latest release) ------------------------------
: "${PIKO_REPO:?PIKO_REPO must be set}"; : "${IG_PACKAGE:?}"; : "${POSTBOX_PACKAGE:?}"; : "${POSTBOX_LABEL:?}"
if [ "${PIKO_CHANNEL:-release}" = "release" ]; then
  log "Resolving piko latest release from $PIKO_REPO ..."
  piko_json="$(gh api "repos/$PIKO_REPO/releases/latest")"
else
  log "Resolving piko dev prerelease from $PIKO_REPO ..."
  piko_json="$(gh api "repos/$PIKO_REPO/releases" --paginate | jq -c '[.[]|select(.prerelease==true)]|first')"
fi
[ "$piko_json" != "null" ] && [ -n "$piko_json" ] || die "no release found on $PIKO_REPO"
PIKO_VERSION="$(jq -r '.tag_name' <<<"$piko_json" | sed 's/^v//')"
PIKO_MPP_URL="$(jq -r '.assets[]|select(.name|endswith(".mpp"))|.browser_download_url' <<<"$piko_json" | head -1)"
[ -n "$PIKO_MPP_URL" ] || die "no .mpp asset on piko release $PIKO_VERSION"
log "  piko = $PIKO_VERSION"

# ---- skip logic vs the latest Postbox release's manifest ------------------
# Postbox releases are tagged "postbox-v..."; the YouTube and X releases and the
# stock-cache are ignored. Build when piko changed, or when forced.
NEEDS_BUILD="true"; last_cli=""
if [ -n "$GH_REPO" ]; then
  log "Reading last Postbox release manifest from $GH_REPO ..."
  last_tag="$(gh api "repos/$GH_REPO/releases" --paginate 2>/dev/null \
    | jq -r '[.[] | select(.tag_name|startswith("postbox-v"))] | first | .tag_name // empty')" || true
  if [ -n "$last_tag" ] && gh release download "$last_tag" -R "$GH_REPO" \
       -p 'built-versions-postbox.json' -O "$WORK/last-postbox.json" --clobber 2>/dev/null; then
    last_piko="$(jq -r '.pikoVersion // empty' "$WORK/last-postbox.json")"
    last_cli="$(jq -r '.morpheCliVersion // empty' "$WORK/last-postbox.json")"
    log "  last Postbox release $last_tag: piko=$last_piko"
    [ "$last_piko" = "$PIKO_VERSION" ] && NEEDS_BUILD="false"
  else
    log "  no prior Postbox release/manifest - building"
  fi
fi
[ -n "$FORCE" ] && { NEEDS_BUILD="true"; log "force flag set - building regardless"; }
if [ "$NEEDS_BUILD" != "true" ]; then
  log "piko unchanged since the last Postbox release - skipping (success)."
  exit 0
fi

# ---- fetch toolchain + bundle ----------------------------------------------
PIKO_MPP="$TOOLS/piko-$PIKO_VERSION.mpp"
dl() { log "download $(basename "$2")"; curl -fsSL "$1" -o "$2" || die "download failed: $1"; }
[ -f "$PIKO_MPP" ] || dl "$PIKO_MPP_URL" "$PIKO_MPP"
# Sets MORPHE_CLI_VERSION + CLI_JAR (latest stable cli that loads piko).
setup_morphe_cli "$TOOLS" "$last_cli" "$PIKO_MPP"

# ---- resolve target Instagram version (piko bundle is the binding constraint) --
# For piko this is exactly the one supported version unless IG_VERSION_PIN is set.
IG_VER="$(resolve_target_version "$CLI_JAR" "$PIKO_MPP" "$IG_PACKAGE" "${IG_VERSION_PIN:-}")"
[ -n "$IG_VER" ] || die "could not resolve an Instagram target version"
log "target Instagram version: $IG_VER"

# ---- keystore preflight ---------------------------------------------------
"$VANTAGE_ROOT/scripts/assert.sh" keystore-preflight "$KEYSTORE"

# ---- download the stock split APKM ----------------------------------------
# Checks the stock-cache release first (com.instagram.android-<ver>.apkm), which
# is how this normally succeeds while APKMirror's Instagram pages are challenge-
# gated.
STOCK_APKM="$STOCK/${IG_PACKAGE}-${IG_VER}.apkm"
"$VANTAGE_ROOT/scripts/download-apk.sh" "$IG_PACKAGE" "$IG_VER" "${IG_ARCH:-arm64-v8a}" "$STOCK_APKM" apkm

# download-apk.sh trusts a stock-cache hit as is, because it only ever uploads
# files that passed its gate. Instagram's cache entry is seeded by hand, so run
# the APKM gate here on whatever came back: every split must be signed by one of
# Instagram's certs in config/expected-signatures.txt and the base must report
# this package and version. Sourcing download-apk.sh only defines its functions.
# shellcheck disable=SC2034  # PKG/VER/ARCH/CONTAINER are globals verify_apkm reads
(
  . "$VANTAGE_ROOT/scripts/download-apk.sh"
  PKG="$IG_PACKAGE"; VER="$IG_VER"; ARCH="${IG_ARCH:-arm64-v8a}"; CONTAINER=apkm
  verify_apkm "$STOCK_APKM"
) || die "stock APKM $STOCK_APKM failed the signing-cert gate - refusing to patch it"

# ---- patch + assert ---------------------------------------------------------
OUTAPK="postbox-${IG_VER}.apk"
RESULT="$OUT/postbox-result.json"; LOGF="$OUT/postbox-patch.log"; TMP="$TMPROOT/postbox"
rm -rf "$TMP"; mkdir -p "$TMP"
log "=== Postbox (Instagram $IG_VER, package $POSTBOX_PACKAGE) ==="
"$VANTAGE_ROOT/scripts/patch.sh" \
  --jar "$CLI_JAR" --patches "$PIKO_MPP" \
  --options "$OPTS" --exclusive \
  --keystore "$KEYSTORE" --apk "$STOCK_APKM" --out "$OUT/$OUTAPK" \
  --result "$RESULT" --log "$LOGF" --tmp "$TMP"

# Package and label are both pinned (Clone sets them). No --expected-count: the
# applied set also holds whatever dependency patches the enabled ones pull in.
# The min-size floor is a conservative guess for an arm64 Instagram APKM, to be
# tightened once a real build exists.
"$VANTAGE_ROOT/scripts/assert.sh" variant --variant postbox --result "$RESULT" --log "$LOGF" \
  --apk "$OUT/$OUTAPK" --package "$POSTBOX_PACKAGE" --label "$POSTBOX_LABEL" \
  --nonneg "$A/postbox-nonnegotiable.txt" --inert "$A/postbox-inert-allowlist.txt" \
  --forbidden "$A/postbox-forbidden.txt" --min-size-mb "40"

cp "$OUT/$OUTAPK" "$OUTDIR/$OUTAPK"
log "staged $OUTDIR/$OUTAPK"

# ---- manifest -------------------------------------------------------------
MANIFEST="$OUTDIR/built-versions-postbox.json"
jq -n \
  --arg builtAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg piko "$PIKO_VERSION" \
  --arg cli "$MORPHE_CLI_VERSION" --arg ig "$IG_VER" --arg pkg "$POSTBOX_PACKAGE" \
  '{builtAt:$builtAt, pikoVersion:$piko, morpheCliVersion:$cli, igVersion:$ig,
    package:$pkg}' > "$MANIFEST"
log "wrote manifest:"; cat "$MANIFEST"

# Ship the Obtainium onboarding config, same as build.sh (a copy of the committed
# repo-root file; gen-obtainium-config.py produces it). Unlike build.sh, refuse a
# copy that lacks the Postbox entry: it would be a useless asset.
cp "$VANTAGE_ROOT/obtainium-config.json" "$OUTDIR/" \
  || die "obtainium-config.json not found at the repo root"
jq -e --arg id "$POSTBOX_PACKAGE" '.apps[] | select(.id == $id)' "$OUTDIR/obtainium-config.json" >/dev/null \
  || die "obtainium-config.json has no $POSTBOX_PACKAGE entry (re-run scripts/gen-obtainium-config.py and commit)"

# ---- release (never --latest - see the header) -----------------------------
TAG="postbox-v$(date -u +%Y.%m.%d)-piko${PIKO_VERSION}"
echo "POSTBOX_RELEASE_TAG=$TAG" > "$WORK/release-postbox.env"
echo "IG_VER=$IG_VER" >> "$WORK/release-postbox.env"
log "Postbox release tag would be: $TAG"

if [ -n "$DO_RELEASE" ]; then
  [ -n "$GH_REPO" ] || die "--release needs GITHUB_REPOSITORY or VANTAGE_REPO"
  notes="$WORK/notes-postbox.md"
  {
    echo "Postbox (patched Instagram) build $TAG"
    echo
    echo "- Instagram version: $IG_VER"
    echo "- piko patches: $PIKO_VERSION | morphe-cli: $MORPHE_CLI_VERSION"
    echo "- Package: $POSTBOX_PACKAGE (label $POSTBOX_LABEL)"
    echo
    echo "Postbox is Instagram for talking to your friends: messages, stories, the"
    echo "profile tab and links people send you. Blocked: the home feed, the Reels"
    echo "tab, Explore and Search, other people's post and reel grids, and suggested"
    echo "content."
    echo
    echo "One-time setup so Instagram links open in Postbox: Settings > Apps >"
    echo "Postbox > Open by default > add the instagram.com links."
    echo
    echo "Installs alongside stock Instagram (different package), signed with the"
    echo "Vantage key. obtainium-config.json in this release adds Postbox to Obtainium."
  } > "$notes"
  assets=("$OUTDIR/$OUTAPK" "$MANIFEST" "$OUTDIR/obtainium-config.json")
  if gh release view "$TAG" -R "$GH_REPO" >/dev/null 2>&1; then
    log "release $TAG exists - updating in place (clobber assets + notes)"
    retry 4 gh release edit "$TAG" -R "$GH_REPO" --prerelease=false --latest=false \
      --notes-file "$notes" || warn "could not update notes"
    retry 4 gh release upload "$TAG" -R "$GH_REPO" "${assets[@]}" --clobber \
      || die "failed to upload assets to existing release $TAG"
  else
    log "creating GitHub release $TAG on $GH_REPO"
    retry 4 gh release create "$TAG" -R "$GH_REPO" --latest=false --title "$TAG" --notes-file "$notes" \
      "${assets[@]}"
  fi
fi

log "POSTBOX BUILD COMPLETE. Staged in $OUTDIR"
ls -la "$OUTDIR"
