#!/usr/bin/env bash
#
# build-claude.sh - Claude clones build orchestrator: several accounts signed
# in at once, deliberately SEPARATE from build.sh/build-x.sh so a flaky Claude
# build never blocks the YouTube nightly or the X build. It publishes its OWN
# GitHub release, tagged "claude-v...", on its own cadence.
#
#   resolve vantage-patches(float) + APKEditor(pinned) + morphe-cli(pinned) ->
#   resolve Claude version (source page, not morphe-cli list-versions - the
#   clone patch has no version gate) -> (skip?) -> keystore preflight ->
#   download+merge the split bundle -> patch one clone per CLAUDE_CLONES ->
#   assert -> stage -> release.
#
# Claude ships no single base APK and no genuine APKM mirror either: sources
# return an XAPK/APKS zip of splits, and download-apk.sh's "bundle" container
# verifies every required split's signature individually before merging them
# into one APK with APKEditor - see the comment block on verify_bundle() in
# download-apk.sh for why that order matters.
#
# Each clone is a renamed, recolored copy of the stock app patched with the
# vantage-patches "Clone with badge" patch (packageName/appLabel/badgeNumber/
# iconColor), so several accounts can be signed in side by side. The package,
# label and icon color per clone number live in config/build.env
# (CLAUDE_CLONE_<N>_*), not here.
#
# State is the latest Claude release's built-versions-claude.json, never a
# committed file. Published with --latest=false for the same reason as X: the
# repo's "latest release" slot must stay on a YouTube build (obtainium-
# config.json).
#
# Usage: build-claude.sh [--force] [--output-dir DIR] [--release]
#   --force       build even if the Claude version and patch bundle are unchanged
#   --output-dir  where staged assets land (default build/release-claude)
#   --release     create/update the GitHub release (needs gh + write perms)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

FORCE="" OUTDIR="$VANTAGE_ROOT/build/release-claude" DO_RELEASE=""
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
command -v unzip >/dev/null 2>&1 || die "unzip not found"

WORK="$VANTAGE_ROOT/build"; TOOLS="$WORK/tools"; STOCK="$WORK/stock"; OUT="$WORK/out"; TMPROOT="/tmp/vt"
mkdir -p "$WORK" "$TOOLS" "$STOCK" "$OUT" "$OUTDIR" "$TMPROOT"
GH_REPO="${GITHUB_REPOSITORY:-${VANTAGE_REPO:-}}"
dl() { log "download $(basename "$2")"; curl -fsSL "$1" -o "$2" || die "download failed: $1"; }

: "${CLAUDE_PACKAGE:?CLAUDE_PACKAGE must be set}"; : "${CLAUDE_CLONES:?CLAUDE_CLONES must be set}"
: "${CLAUDE_ARCH:?CLAUDE_ARCH must be set}"

# ---- signing keystore -------------------------------------------------------
KEYSTORE="$WORK/vantage.keystore"
resolve_signing_keystore "$KEYSTORE"

# ---- resolve APKEditor (pinned version + sha256) ---------------------------
: "${APKEDITOR_VERSION:?}"; : "${APKEDITOR_URL:?}"; : "${APKEDITOR_SHA256:?}"
APKEDITOR_JAR="$TOOLS/APKEditor-$APKEDITOR_VERSION.jar"
if [ ! -f "$APKEDITOR_JAR" ]; then
  dl "$APKEDITOR_URL" "$APKEDITOR_JAR"
fi
got_sha="$(sha256_of "$APKEDITOR_JAR")"
[ "$got_sha" = "$APKEDITOR_SHA256" ] \
  || die "APKEditor sha256 mismatch: expected=$APKEDITOR_SHA256 got=$got_sha (bad/tampered download, refusing to use it to merge a trust-critical APK)"
export APKEDITOR_JAR
log "APKEditor $APKEDITOR_VERSION OK (sha256 pinned)"

# ---- resolve vantage-patches (float to latest release, or a local override) -
: "${VANTAGE_PATCHES_REPO:?VANTAGE_PATCHES_REPO must be set}"
if [ -n "${VANTAGE_PATCHES_MPP:-}" ]; then
  [ -f "$VANTAGE_PATCHES_MPP" ] || die "VANTAGE_PATCHES_MPP set but not found: $VANTAGE_PATCHES_MPP"
  PATCHES_MPP="$VANTAGE_PATCHES_MPP"
  VANTAGE_PATCHES_VERSION="local-$(sha256_of "$PATCHES_MPP" | cut -c1-8)"
  log "using local vantage-patches override: $PATCHES_MPP"
else
  log "Resolving vantage-patches latest release from $VANTAGE_PATCHES_REPO ..."
  vp_json="$(gh api "repos/$VANTAGE_PATCHES_REPO/releases/latest" 2>/dev/null)" \
    || die "no release found on $VANTAGE_PATCHES_REPO yet (set VANTAGE_PATCHES_MPP=<local .mpp path> to build against a not-yet-published bundle)"
  [ "$vp_json" != "null" ] && [ -n "$vp_json" ] || die "no release found on $VANTAGE_PATCHES_REPO"
  VANTAGE_PATCHES_VERSION="$(jq -r '.tag_name' <<<"$vp_json" | sed 's/^v//')"
  VP_MPP_URL="$(jq -r '.assets[]|select(.name|test("^vantage-patches-.*\\.mpp$"))|.browser_download_url' <<<"$vp_json" | head -1)"
  [ -n "$VP_MPP_URL" ] || die "no vantage-patches-*.mpp asset on vantage-patches release $VANTAGE_PATCHES_VERSION"
  PATCHES_MPP="$TOOLS/vantage-patches-$VANTAGE_PATCHES_VERSION.mpp"
  [ -f "$PATCHES_MPP" ] || dl "$VP_MPP_URL" "$PATCHES_MPP"
  log "  vantage-patches = $VANTAGE_PATCHES_VERSION"
fi

# ---- resolve morphe-cli (pinned, same jar the other builds use) -----------
CLI_JAR="$TOOLS/morphe-cli-$MORPHE_CLI_VERSION-all.jar"
if [ ! -f "$CLI_JAR" ]; then
  cli_json="$(gh api "repos/$MORPHE_CLI_REPO/releases/tags/v$MORPHE_CLI_VERSION" 2>/dev/null \
    || gh api "repos/$MORPHE_CLI_REPO/releases/tags/$MORPHE_CLI_VERSION")"
  CLI_JAR_URL="$(jq -r '.assets[]|select(.name|endswith("-all.jar"))|.browser_download_url' <<<"$cli_json" | head -1)"
  [ -n "$CLI_JAR_URL" ] || die "no -all.jar asset on morphe-cli $MORPHE_CLI_VERSION"
  dl "$CLI_JAR_URL" "$CLI_JAR"
fi

# ---- resolve target Claude version ------------------------------------------
# The clone patch has no compatiblePackages gate (a rename/badge patch works on
# any build), so `morphe-cli list-versions` isn't the right tool here - it's
# built for a curated compatibility tier, and Claude ships new builds roughly
# daily. Instead: ask the download sources what the newest version they list
# is, in CLAUDE_DL_SOURCES order, and take the first answer.
resolve_claude_version() {
  local ua='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
  local src ver=""
  for src in ${CLAUDE_DL_SOURCES:-apkcombo uptodown}; do
    case "$src" in
      apkcombo)
        ver="$(curl -fsSL --connect-timeout 20 --max-time 60 -A "$ua" \
            "https://apkcombo.app/claude/${CLAUDE_PACKAGE}/download/apk" 2>/dev/null \
          | grep -oE '"description" content="[^"]*"' \
          | grep -oE 'Version:[[:space:]]*[0-9]+(\.[0-9]+)+' \
          | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)"
        ;;
      uptodown)
        ver="$(curl -fsSL --connect-timeout 20 --max-time 60 -A "$ua" \
            "https://claude.en.uptodown.com/android/versions" 2>/dev/null \
          | grep -oE '<span class="version">[0-9]+(\.[0-9]+)+</span>' \
          | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' || true)"
        ;;
      *) warn "  resolve-claude-version: no resolver for source '$src'"; continue ;;
    esac
    if [ -n "$ver" ]; then warn "  resolve-claude-version: $src -> $ver"; printf '%s\n' "$ver"; return 0; fi
    warn "  resolve-claude-version: $src gave no answer"
  done
  return 1
}
CLAUDE_VER="$(resolve_claude_version)" || die "could not resolve the latest Claude version from any of: ${CLAUDE_DL_SOURCES:-apkcombo uptodown}"
log "target Claude version: $CLAUDE_VER"

# ---- skip logic vs the latest Claude release's manifest --------------------
# Rebuild when EITHER the Claude app version OR the vantage-patches bundle
# changed - unlike X (piko-only), Claude has no version gate on the patch, so
# the app itself moves the target far more often than the patch bundle does.
NEEDS_BUILD="true"
if [ -n "$GH_REPO" ]; then
  log "Reading last Claude release manifest from $GH_REPO ..."
  last_tag="$(gh api "repos/$GH_REPO/releases" --paginate 2>/dev/null \
    | jq -r '[.[] | select(.tag_name|startswith("claude-v"))] | first | .tag_name // empty')" || true
  if [ -n "$last_tag" ] && gh release download "$last_tag" -R "$GH_REPO" \
       -p 'built-versions-claude.json' -O "$WORK/last-claude.json" --clobber 2>/dev/null; then
    last_claude_ver="$(jq -r '.claudeVersion // empty' "$WORK/last-claude.json")"
    last_vp_ver="$(jq -r '.vantagePatchesVersion // empty' "$WORK/last-claude.json")"
    log "  last Claude release $last_tag: claude=$last_claude_ver vantage-patches=$last_vp_ver"
    if [ "$last_claude_ver" = "$CLAUDE_VER" ] && [ "$last_vp_ver" = "$VANTAGE_PATCHES_VERSION" ]; then
      NEEDS_BUILD="false"
    fi
  else
    log "  no prior Claude release/manifest - building"
  fi
fi
[ -n "$FORCE" ] && { NEEDS_BUILD="true"; log "force flag set - building regardless"; }
if [ "$NEEDS_BUILD" != "true" ]; then
  log "Claude version and vantage-patches unchanged since the last Claude release - skipping (success)."
  exit 0
fi

# ---- keystore preflight ------------------------------------------------------
"$VANTAGE_ROOT/scripts/assert.sh" keystore-preflight "$KEYSTORE"

# ---- download + merge the split bundle --------------------------------------
STOCK_APK="$STOCK/${CLAUDE_PACKAGE}-${CLAUDE_VER}.merged.apk"
"$VANTAGE_ROOT/scripts/download-apk.sh" "$CLAUDE_PACKAGE" "$CLAUDE_VER" "$CLAUDE_ARCH" "$STOCK_APK" bundle

# ---- patch: one clone APK per CLAUDE_CLONES ---------------------------------
KS_ALIAS="${VANTAGE_KEYSTORE_ALIAS:-vantage}"
PATCH_NAME="Clone with badge"
OUTAPKS=()
MANIFEST_CLONES="[]"
for n in $CLAUDE_CLONES; do
  suffix_var="CLAUDE_CLONE_${n}_SUFFIX"; label_var="CLAUDE_CLONE_${n}_LABEL"; color_var="CLAUDE_CLONE_${n}_ICON_COLOR"
  suffix="${!suffix_var:?missing $suffix_var in config/build.env}"
  label="${!label_var:?missing $label_var in config/build.env}"
  color="${!color_var:?missing $color_var in config/build.env}"
  clone_pkg="${CLAUDE_PACKAGE}.${suffix}"

  OUTAPK="claude-${n}-${CLAUDE_VER}.apk"
  RESULT="$OUT/claude-$n-result.json"; LOGF="$OUT/claude-$n-patch.log"; TMP="$TMPROOT/claude-$n"
  rm -rf "$TMP"; mkdir -p "$TMP"
  log "=== Claude clone $n: $label ($clone_pkg, badge=$n, icon=$color) ==="

  set +e
  java -jar "$CLI_JAR" patch \
    -p "$PATCHES_MPP" \
    --exclusive \
    -e "$PATCH_NAME" \
    -O packageName="$clone_pkg" \
    -O appLabel="$label" \
    -O badgeNumber="$n" \
    -O iconColor="$color" \
    -f \
    --keystore="$KEYSTORE" \
    --keystore-entry-alias="$KS_ALIAS" \
    --keystore-password="$VANTAGE_KEYSTORE_PASS" \
    --keystore-entry-password="$VANTAGE_KEYSTORE_PASS" \
    -o "$OUT/$OUTAPK" \
    -r "$RESULT" \
    -t "$TMP" \
    "$STOCK_APK" 2>&1 | tee "$LOGF"
  rc=${PIPESTATUS[0]}
  set -e
  [ "$rc" -eq 0 ] || die "morphe-cli exited $rc for clone $n (see $LOGF). NOTE: if the bundle doesn't have '$PATCH_NAME' yet, this is expected until vantage-patches ships it."
  [ -f "$OUT/$OUTAPK" ] || die "morphe-cli reported success but produced no output APK for clone $n"
  [ -f "$RESULT" ] || die "no result JSON at $RESULT for clone $n"
  log "Patch OK: $OUT/$OUTAPK ($(du -h "$OUT/$OUTAPK" | cut -f1))"

  "$VANTAGE_ROOT/scripts/assert.sh" claude-clone --variant "claude-$n" \
    --apk "$OUT/$OUTAPK" --package "$clone_pkg" --label "$label" \
    --forbidden-authority "${CLAUDE_PACKAGE}.provider" \
    --result "$RESULT" --patch-name "$PATCH_NAME"

  cp "$OUT/$OUTAPK" "$OUTDIR/$OUTAPK"
  OUTAPKS+=("$OUTDIR/$OUTAPK")
  MANIFEST_CLONES="$(jq -c --arg n "$n" --arg pkg "$clone_pkg" --arg label "$label" --arg color "$color" \
    '. + [{number:$n, package:$pkg, label:$label, iconColor:$color}]' <<<"$MANIFEST_CLONES")"
  log "staged $OUTDIR/$OUTAPK"
done

# ---- manifest -----------------------------------------------------------------
MANIFEST="$OUTDIR/built-versions-claude.json"
jq -n \
  --arg builtAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg claude "$CLAUDE_VER" \
  --arg vp "$VANTAGE_PATCHES_VERSION" \
  --arg cli "$MORPHE_CLI_VERSION" \
  --argjson clones "$MANIFEST_CLONES" \
  '{builtAt:$builtAt, claudeVersion:$claude, vantagePatchesVersion:$vp, morpheCliVersion:$cli, clones:$clones}' \
  > "$MANIFEST"
log "wrote manifest:"; cat "$MANIFEST"

# ---- release (never --latest - see the header) -------------------------------
TAG="claude-v${CLAUDE_VER}-vp${VANTAGE_PATCHES_VERSION}"
echo "CLAUDE_RELEASE_TAG=$TAG" > "$WORK/release-claude.env"
echo "CLAUDE_VER=$CLAUDE_VER" >> "$WORK/release-claude.env"
log "Claude release tag would be: $TAG"

if [ -n "$DO_RELEASE" ]; then
  [ -n "$GH_REPO" ] || die "--release needs GITHUB_REPOSITORY or VANTAGE_REPO"
  notes="$WORK/notes-claude.md"
  {
    echo "Claude clones build $TAG"
    echo
    echo "- Claude target version: $CLAUDE_VER"
    echo "- vantage-patches: $VANTAGE_PATCHES_VERSION | morphe-cli: $MORPHE_CLI_VERSION"
    echo
    echo "Several accounts signed in at once: each clone is a renamed, recolored copy"
    echo "of Claude that installs next to the original app and next to the other clones."
    echo
    echo "| APK | Name | Package | Badge |"
    echo "|---|---|---|---|"
    for n in $CLAUDE_CLONES; do
      label_var="CLAUDE_CLONE_${n}_LABEL"; suffix_var="CLAUDE_CLONE_${n}_SUFFIX"
      echo "| claude-$n-$CLAUDE_VER.apk | ${!label_var} | ${CLAUDE_PACKAGE}.${!suffix_var} | $n |"
    done
    echo
    echo "Install the first clone APK manually; afterwards Obtainium tracks and updates"
    echo "it like any other app in the bundled config. If an earlier hand-built copy"
    echo "with the same name is already installed, uninstall it first - the signing key"
    echo "differs and Android refuses to install over the mismatch."
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

log "CLAUDE BUILD COMPLETE. Staged in $OUTDIR"
ls -la "$OUTDIR"
