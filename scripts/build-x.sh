#!/usr/bin/env bash
#
# build-x.sh - Vantage X (Twitter) build orchestrator, deliberately SEPARATE from
# build.sh so a flaky X build can never take the YouTube nightly down with it: X
# has a single-source APKM download and a patch bundle (the pmaxhogan/piko fork)
# that churns on its own schedule. It publishes its OWN GitHub release, tagged
# "x-v...", on its own cadence.
#
#   resolve piko(float) -> (skip?) -> download cli+bundle -> resolve X version ->
#   keystore preflight -> download APKM -> patch -> assert -> stage -> release.
#
# x-shim (inotia00's compatibility layer for X 11.88-12.4) is no longer stacked:
# from X 12.5.0 piko patches the app on its own (piko README).
#
# State is the latest X release's built-versions-x.json, never a committed file.
#
# The X release is published with --latest=false on purpose: the repo's "latest
# release" slot must stay on a YouTube build, since that is the one carrying
# obtainium-config.json (the README's install link points at /releases/latest).
#
# Usage: build-x.sh [--force] [--output-dir DIR] [--release]
#   --force       build even if the piko version is unchanged
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

# ---- skip logic vs the latest X release's manifest ------------------------
# X releases are tagged "x-v..."; the YouTube releases and the stock-cache are
# ignored. Build when piko changed, or when forced.
NEEDS_BUILD="true"
if [ -n "$GH_REPO" ]; then
  log "Reading last X release manifest from $GH_REPO ..."
  last_tag="$(gh api "repos/$GH_REPO/releases" --paginate 2>/dev/null \
    | jq -r '[.[] | select(.tag_name|startswith("x-v"))] | first | .tag_name // empty')" || true
  if [ -n "$last_tag" ] && gh release download "$last_tag" -R "$GH_REPO" \
       -p 'built-versions-x.json' -O "$WORK/last-x.json" --clobber 2>/dev/null; then
    last_piko="$(jq -r '.pikoVersion // empty' "$WORK/last-x.json")"
    log "  last X release $last_tag: piko=$last_piko"
    [ "$last_piko" = "$PIKO_VERSION" ] && NEEDS_BUILD="false"
  else
    log "  no prior X release/manifest - building"
  fi
fi
[ -n "$FORCE" ] && { NEEDS_BUILD="true"; log "force flag set - building regardless"; }
if [ "$NEEDS_BUILD" != "true" ]; then
  log "piko unchanged since the last X release - skipping (success)."
  exit 0
fi

# ---- fetch toolchain + bundles --------------------------------------------
CLI_JAR="$TOOLS/morphe-cli-$MORPHE_CLI_VERSION-all.jar"
PIKO_MPP="$TOOLS/piko-$PIKO_VERSION.mpp"
dl() { log "download $(basename "$2")"; curl -fsSL "$1" -o "$2" || die "download failed: $1"; }
if [ ! -f "$CLI_JAR" ]; then
  cli_json="$(gh api "repos/$MORPHE_CLI_REPO/releases/tags/v$MORPHE_CLI_VERSION" 2>/dev/null \
    || gh api "repos/$MORPHE_CLI_REPO/releases/tags/$MORPHE_CLI_VERSION")"
  CLI_JAR_URL="$(jq -r '.assets[]|select(.name|endswith("-all.jar"))|.browser_download_url' <<<"$cli_json" | head -1)"
  [ -n "$CLI_JAR_URL" ] || die "no -all.jar asset on morphe-cli $MORPHE_CLI_VERSION"
  dl "$CLI_JAR_URL" "$CLI_JAR"
fi
[ -f "$PIKO_MPP" ] || dl "$PIKO_MPP_URL" "$PIKO_MPP"

# ---- resolve target X version (piko bundle is the binding constraint) -----
X_VER="$(resolve_target_version "$CLI_JAR" "$PIKO_MPP" "$X_PACKAGE" "${X_VERSION_PIN:-}")"
[ -n "$X_VER" ] || die "could not resolve an X target version"
log "target X version: $X_VER"

# ---- keystore preflight ---------------------------------------------------
"$VANTAGE_ROOT/scripts/assert.sh" keystore-preflight "$KEYSTORE"

# ---- download the stock split APKM ----------------------------------------
STOCK_APKM="$STOCK/${X_PACKAGE}-${X_VER}.apkm"
"$VANTAGE_ROOT/scripts/download-apk.sh" "$X_PACKAGE" "$X_VER" "${X_ARCH:-universal}" "$STOCK_APKM" apkm

# ---- patch: one APK per daily-limit ceiling ---------------------------------
# The "Daily time limit" patch bakes the highest limit a user can configure into
# the build (maxLimitMinutes), so the release carries four APKs that differ ONLY
# in that option file: 2h, 1h, 30m and 15m ceilings. All four default to a 30m
# limit except max15m, whose ceiling is its default. The options files are
# generated from the same base set; keep them in sync (diff them - only the
# maxLimitMinutes value should differ). enableTestHooks must be false in all of
# them - the assertion below refuses a release build that turns it on.
X_VARIANTS="max2h max1h max30m max15m"
A="$VANTAGE_ROOT/config/assertions"
OUTAPKS=()
for variant in $X_VARIANTS; do
  OPTS="$VANTAGE_ROOT/config/x-options-$variant.json"
  [ -f "$OPTS" ] || die "missing options file $OPTS"
  if [ "$(jq -r '.[0].patches."Daily time limit".options.enableTestHooks' "$OPTS")" != "false" ]; then
    die "$OPTS enables test hooks - refusing to build a release APK with the debug clock offset"
  fi
  maxmin="$(jq -r '.[0].patches."Daily time limit".options.maxLimitMinutes' "$OPTS")"
  [ "$maxmin" -ge 1 ] && [ "$maxmin" -le 120 ] || die "$OPTS: maxLimitMinutes=$maxmin out of 1..120"
  OUTAPK="vantage-x-${X_VER}-${variant}.apk"
  RESULT="$OUT/x-$variant-result.json"; LOGF="$OUT/x-$variant-patch.log"; TMP="$TMPROOT/x-$variant"
  rm -rf "$TMP"; mkdir -p "$TMP"
  log "=== Vantage X $variant (maxLimitMinutes=$maxmin) ==="
  "$VANTAGE_ROOT/scripts/patch.sh" \
    --jar "$CLI_JAR" --patches "$PIKO_MPP" \
    --options "$OPTS" \
    --keystore "$KEYSTORE" --apk "$STOCK_APKM" --out "$OUT/$OUTAPK" \
    --result "$RESULT" --log "$LOGF" --tmp "$TMP"

  # Label is left unpinned (X's label is whatever piko's Change app icon sets); the
  # package name and signing cert are still pinned. Min-size floor is conservative.
  "$VANTAGE_ROOT/scripts/assert.sh" variant --variant "x-$variant" --result "$RESULT" --log "$LOGF" \
    --apk "$OUT/$OUTAPK" --package "$X_PACKAGE" \
    --nonneg "$A/x-nonnegotiable.txt" --inert "$A/x-inert-allowlist.txt" \
    --forbidden "$A/x-forbidden.txt" --min-size-mb "30"

  cp "$OUT/$OUTAPK" "$OUTDIR/$OUTAPK"
  OUTAPKS+=("$OUTDIR/$OUTAPK")
  log "staged $OUTDIR/$OUTAPK"
done

# ---- manifest -------------------------------------------------------------
MANIFEST="$OUTDIR/built-versions-x.json"
jq -n \
  --arg builtAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg piko "$PIKO_VERSION" \
  --arg cli "$MORPHE_CLI_VERSION" --arg x "$X_VER" \
  --arg variants "$X_VARIANTS" \
  '{builtAt:$builtAt, pikoVersion:$piko, morpheCliVersion:$cli, xVersion:$x,
    variants:($variants|split(" "))}' > "$MANIFEST"
log "wrote manifest:"; cat "$MANIFEST"

# ---- release (never --latest - see the header) -----------------------------
TAG="x-v$(date -u +%Y.%m.%d)-piko${PIKO_VERSION}"
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
    echo "- piko patches: $PIKO_VERSION | morphe-cli: $MORPHE_CLI_VERSION"
    echo
    echo "Four APKs, identical except for the highest daily time limit a user can set:"
    echo
    echo "| APK | max daily limit | default limit |"
    echo "|---|---|---|"
    echo "| vantage-x-$X_VER-max2h.apk | 2 hours | 30 minutes |"
    echo "| vantage-x-$X_VER-max1h.apk | 1 hour | 30 minutes |"
    echo "| vantage-x-$X_VER-max30m.apk | 30 minutes | 30 minutes |"
    echo "| vantage-x-$X_VER-max15m.apk | 15 minutes | 15 minutes |"
    echo
    echo "The daily limit is always on and resets at 5:00 AM local time. It needs two"
    echo "one-time special permissions (Usage access and All files access) on first"
    echo "launch. obtainium-config.json tracks the max2h build."
    echo
    echo "Package is com.twitter.android, so it replaces a stock X install."
    echo "pairip (X's Play-integrity anti-tamper) is not removed."
  } > "$notes"
  assets=("${OUTAPKS[@]}" "$MANIFEST")
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
