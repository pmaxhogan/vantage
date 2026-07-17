#!/usr/bin/env bash
#
# build-x.sh - Vantage X (Twitter) build orchestrator, deliberately SEPARATE from
# build.sh so a flaky X build can never take the YouTube nightly down with it: X
# has a single-source APKM download and two floating/pinned patch bundles (piko +
# x-shim) that churn on their own schedule. It publishes its OWN GitHub release,
# tagged "x-v...", on its own cadence.
#
#   resolve piko(float)+x-shim(pinned) -> (skip?) -> download cli+bundles ->
#   resolve X version -> keystore preflight -> download APKM -> patch(piko+shim) ->
#   assert -> stage -> release.
#
# State is the latest X release's built-versions-x.json, never a committed file.
#
# The X release is published with --latest=false on purpose: the repo's "latest
# release" slot must stay on a YouTube build, since that is the one carrying
# obtainium-config.json (the README's install link points at /releases/latest).
#
# Usage: build-x.sh [--force] [--output-dir DIR] [--release]
#   --force       build even if piko + x-shim versions are unchanged
#   --output-dir  where staged assets land (default build/release-x)
#   --release     create/update the GitHub release (needs gh + write perms)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

FORCE="" OUTDIR="$VANTAGE_ROOT/build/release-x" DO_RELEASE=""
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

# ---- signing keystore -----------------------------------------------------
KEYSTORE="$WORK/vantage.keystore"
resolve_signing_keystore "$KEYSTORE"

# ---- resolve piko (floats to latest release) ------------------------------
: "${PIKO_REPO:?PIKO_REPO must be set}"; : "${X_PACKAGE:?}"
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

# ---- resolve x-shim (pinned to an exact version, sha256-verified) ---------
: "${XSHIM_GITLAB_PROJECT:?}"; : "${XSHIM_VERSION:?}"
SHIM_VERSION="$XSHIM_VERSION"
SHIM_MPP_URL="https://gitlab.com/$XSHIM_GITLAB_PROJECT/-/releases/v$SHIM_VERSION/downloads/patches-$SHIM_VERSION.mpp"
log "  x-shim = $SHIM_VERSION (pinned)"

# ---- skip logic vs the latest X release's manifest ------------------------
# X releases are tagged "x-v..."; the YouTube releases and the stock-cache are
# ignored. Build when piko OR x-shim changed, or when forced.
NEEDS_BUILD="true"
if [ -n "$GH_REPO" ]; then
  log "Reading last X release manifest from $GH_REPO ..."
  last_tag="$(gh api "repos/$GH_REPO/releases" --paginate 2>/dev/null \
    | jq -r '[.[] | select(.tag_name|startswith("x-v"))] | first | .tag_name // empty')" || true
  if [ -n "$last_tag" ] && gh release download "$last_tag" -R "$GH_REPO" \
       -p 'built-versions-x.json' -O "$WORK/last-x.json" --clobber 2>/dev/null; then
    last_piko="$(jq -r '.pikoVersion // empty' "$WORK/last-x.json")"
    last_shim="$(jq -r '.xShimVersion // empty' "$WORK/last-x.json")"
    log "  last X release $last_tag: piko=$last_piko shim=$last_shim"
    [ "$last_piko" = "$PIKO_VERSION" ] && [ "$last_shim" = "$SHIM_VERSION" ] && NEEDS_BUILD="false"
  else
    log "  no prior X release/manifest - building"
  fi
fi
[ -n "$FORCE" ] && { NEEDS_BUILD="true"; log "force flag set - building regardless"; }
if [ "$NEEDS_BUILD" != "true" ]; then
  log "piko + x-shim unchanged since the last X release - skipping (success)."
  exit 0
fi

# ---- fetch toolchain + bundles --------------------------------------------
CLI_JAR="$TOOLS/morphe-cli-$MORPHE_CLI_VERSION-all.jar"
PIKO_MPP="$TOOLS/piko-$PIKO_VERSION.mpp"
SHIM_MPP="$TOOLS/x-shim-$SHIM_VERSION.mpp"
dl() { log "download $(basename "$2")"; curl -fsSL "$1" -o "$2" || die "download failed: $1"; }
if [ ! -f "$CLI_JAR" ]; then
  cli_json="$(gh api "repos/$MORPHE_CLI_REPO/releases/tags/v$MORPHE_CLI_VERSION" 2>/dev/null \
    || gh api "repos/$MORPHE_CLI_REPO/releases/tags/$MORPHE_CLI_VERSION")"
  CLI_JAR_URL="$(jq -r '.assets[]|select(.name|endswith("-all.jar"))|.browser_download_url' <<<"$cli_json" | head -1)"
  [ -n "$CLI_JAR_URL" ] || die "no -all.jar asset on morphe-cli $MORPHE_CLI_VERSION"
  dl "$CLI_JAR_URL" "$CLI_JAR"
fi
[ -f "$PIKO_MPP" ] || dl "$PIKO_MPP_URL" "$PIKO_MPP"
[ -f "$SHIM_MPP" ] || dl "$SHIM_MPP_URL" "$SHIM_MPP"

# x-shim is a ~35MB opaque binary we pin; a hash mismatch means the pinned release
# changed under us (or a bad download) - refuse it rather than patch with a surprise.
got_shim_sha="$(sha256_of "$SHIM_MPP")"
[ "$got_shim_sha" = "${XSHIM_SHA256:?XSHIM_SHA256 must be set to pin x-shim}" ] \
  || die "x-shim sha256 mismatch: expected $XSHIM_SHA256 got $got_shim_sha"
log "x-shim sha256 pinned OK"

# ---- resolve target X version (piko bundle is the binding constraint) -----
X_VER="$(resolve_target_version "$CLI_JAR" "$PIKO_MPP" "$X_PACKAGE" "${X_VERSION_PIN:-}")"
[ -n "$X_VER" ] || die "could not resolve an X target version"
log "target X version: $X_VER"

# ---- keystore preflight ---------------------------------------------------
"$VANTAGE_ROOT/scripts/assert.sh" keystore-preflight "$KEYSTORE"

# ---- download the stock split APKM ----------------------------------------
STOCK_APKM="$STOCK/${X_PACKAGE}-${X_VER}.apkm"
"$VANTAGE_ROOT/scripts/download-apk.sh" "$X_PACKAGE" "$X_VER" "${X_ARCH:-universal}" "$STOCK_APKM" apkm

# ---- patch (piko + x-shim stacked) ----------------------------------------
OUTAPK="vantage-x-${X_VER}.apk"
RESULT="$OUT/x-result.json"; LOGF="$OUT/x-patch.log"; TMP="$TMPROOT/x"
rm -rf "$TMP"; mkdir -p "$TMP"
"$VANTAGE_ROOT/scripts/patch.sh" \
  --jar "$CLI_JAR" --patches "$PIKO_MPP" --patches "$SHIM_MPP" \
  --options "$VANTAGE_ROOT/config/x-options.json" \
  --keystore "$KEYSTORE" --apk "$STOCK_APKM" --out "$OUT/$OUTAPK" \
  --result "$RESULT" --log "$LOGF" --tmp "$TMP"

# ---- assert ---------------------------------------------------------------
# Label is left unpinned (X's label is whatever piko's Change app icon sets); the
# package name and signing cert are still pinned. Min-size floor is conservative.
A="$VANTAGE_ROOT/config/assertions"
"$VANTAGE_ROOT/scripts/assert.sh" variant --variant "x" --result "$RESULT" --log "$LOGF" \
  --apk "$OUT/$OUTAPK" --package "$X_PACKAGE" \
  --nonneg "$A/x-nonnegotiable.txt" --inert "$A/x-inert-allowlist.txt" \
  --forbidden "$A/x-forbidden.txt" --min-size-mb "30"

cp "$OUT/$OUTAPK" "$OUTDIR/$OUTAPK"
log "staged $OUTDIR/$OUTAPK"

# ---- manifest -------------------------------------------------------------
MANIFEST="$OUTDIR/built-versions-x.json"
jq -n \
  --arg builtAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg piko "$PIKO_VERSION" --arg shim "$SHIM_VERSION" \
  --arg cli "$MORPHE_CLI_VERSION" --arg x "$X_VER" \
  '{builtAt:$builtAt, pikoVersion:$piko, xShimVersion:$shim,
    morpheCliVersion:$cli, xVersion:$x}' > "$MANIFEST"
log "wrote manifest:"; cat "$MANIFEST"

# ---- release (never --latest - see the header) -----------------------------
TAG="x-v$(date -u +%Y.%m.%d)-piko${PIKO_VERSION}-shim${SHIM_VERSION}"
echo "X_RELEASE_TAG=$TAG" > "$WORK/release-x.env"
echo "X_VER=$X_VER" >> "$WORK/release-x.env"
log "X release tag would be: $TAG"

if [ -n "$DO_RELEASE" ]; then
  [ -n "$GH_REPO" ] || die "--release needs GITHUB_REPOSITORY or VANTAGE_REPO"
  notes="$WORK/notes-x.md"
  {
    echo "Vantage X (Twitter/X) build $TAG"
    echo
    echo "- X target version: $X_VER"
    echo "- piko patches: $PIKO_VERSION | x-shim: $SHIM_VERSION | morphe-cli: $MORPHE_CLI_VERSION"
    echo
    echo "Package is com.twitter.android, so it replaces a stock X install."
    echo "x-shim does not remove pairip (X's Play-integrity anti-tamper)."
  } > "$notes"
  assets=("$OUTDIR/$OUTAPK" "$MANIFEST")
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

log "X BUILD COMPLETE. Staged in $OUTDIR"
ls -la "$OUTDIR"
