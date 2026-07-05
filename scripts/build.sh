#!/usr/bin/env bash
#
# build.sh - Vantage build orchestrator. Also runnable locally.
#
#   resolve versions -> (skip?) -> download cli+bundles -> resolve target app
#   versions -> keystore preflight -> for each variant: download stock APK,
#   patch, assert -> stage release assets + built-versions.json manifest.
#
# State is the latest release (built-versions.json), never a committed file.
#
# Usage: build.sh [--force] [--output-dir DIR] [--release]
#   --force       build even if resolve-versions says nothing changed
#   --output-dir  where staged release assets land (default build/release)
#   --release     create the GitHub Release (needs gh + write perms). Without
#                 it, build.sh only builds+stages locally (the workflow releases).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

FORCE="" OUTDIR="$VANTAGE_ROOT/build/release" DO_RELEASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE="--force"; shift;;
    --output-dir) OUTDIR="$2"; shift 2;;
    --release) DO_RELEASE="1"; shift;;
    *) die "unknown arg: $1";;
  esac
done

command -v java >/dev/null 2>&1 || die "java not found (need Java 21+ for morphe-cli)"
WORK="$VANTAGE_ROOT/build"; TOOLS="$WORK/tools"; STOCK="$WORK/stock"; OUT="$WORK/out"; TMPROOT="/tmp/vt"
mkdir -p "$WORK" "$TOOLS" "$STOCK" "$OUT" "$OUTDIR" "$TMPROOT"

# ---- resolve signing keystore (not committed - repo is public) -------------
# Source of truth is the secret VANTAGE_KEYSTORE_B64 (base64 of the .keystore),
# decoded to a runtime file. Local dev may instead point VANTAGE_KEYSTORE_FILE
# at a real keystore on disk. The password + alias come from secrets too
# (VANTAGE_KEYSTORE_PASS required; VANTAGE_KEYSTORE_ALIAS defaults to "vantage").
# base64 round-trips byte-for-byte, so the decoded file's SHA-256 still matches
# the pinned VANTAGE_KEYSTORE_SHA256 guard.
KEYSTORE="$WORK/vantage.keystore"
if [ -n "${VANTAGE_KEYSTORE_B64:-}" ]; then
  printf '%s' "$VANTAGE_KEYSTORE_B64" | base64 -d > "$KEYSTORE" \
    || die "failed to base64-decode VANTAGE_KEYSTORE_B64"
  log "decoded signing keystore from VANTAGE_KEYSTORE_B64"
elif [ -n "${VANTAGE_KEYSTORE_FILE:-}" ] && [ -f "${VANTAGE_KEYSTORE_FILE}" ]; then
  cp "$VANTAGE_KEYSTORE_FILE" "$KEYSTORE"
  log "using local signing keystore from VANTAGE_KEYSTORE_FILE"
else
  die "no signing keystore: set VANTAGE_KEYSTORE_B64 (CI secret) or VANTAGE_KEYSTORE_FILE (local path)"
fi
: "${VANTAGE_KEYSTORE_PASS:?VANTAGE_KEYSTORE_PASS must be set (keystore + entry password)}"
export VANTAGE_KEYSTORE_PASS VANTAGE_KEYSTORE_ALIAS="${VANTAGE_KEYSTORE_ALIAS:-vantage}"

# ---- resolve versions + skip ---------------------------------------------
RESOLVED="$WORK/resolved.env"
"$VANTAGE_ROOT/scripts/resolve-versions.sh" "$RESOLVED" $FORCE
# shellcheck disable=SC1090
. "$RESOLVED"
if [ "${NEEDS_BUILD:-true}" != "true" ]; then
  log "NEEDS_BUILD=false and not forced - nothing new upstream. Skipping build (success)."
  exit 0
fi

# ---- fetch toolchain + bundles -------------------------------------------
CLI_JAR="$TOOLS/morphe-cli-$MORPHE_CLI_VERSION-all.jar"
ANDDEA_MPP="$TOOLS/anddea-$ANDDEA_VERSION.mpp"
MORPHE_MPP="$TOOLS/morphe-$MORPHE_VERSION.mpp"
dl() { log "download $(basename "$2")"; curl -fsSL "$1" -o "$2" || die "download failed: $1"; }
[ -f "$CLI_JAR" ]    || dl "$CLI_JAR_URL"    "$CLI_JAR"
[ -f "$ANDDEA_MPP" ] || dl "$ANDDEA_MPP_URL" "$ANDDEA_MPP"
[ -f "$MORPHE_MPP" ] || dl "$MORPHE_MPP_URL" "$MORPHE_MPP"

# ---- resolve target app version ------------------------------------------
# Newest version in the top patch-count tier from `morphe-cli list-versions`,
# unless pinned. Each variant's bundle resolves independently. The logic lives in
# lib.sh (resolve_target_version).
resolve_target() { resolve_target_version "$CLI_JAR" "$1" "$2" "$3"; }

YT_VER="$(resolve_target "$ANDDEA_MPP" "$YT_PACKAGE" "${YT_VERSION_PIN:-}")"
MUSIC_VER="$(resolve_target "$ANDDEA_MPP" "$MUSIC_PACKAGE" "${MUSIC_VERSION_PIN:-}")"
MORPHE_YT_VER="$(resolve_target "$MORPHE_MPP" "$YT_PACKAGE" "${YT_VERSION_PIN:-}")"
log "target versions: YouTube(anddea)=$YT_VER  Music=$MUSIC_VER  YouTube(morphe)=$MORPHE_YT_VER"

# ---- keystore preflight ---------------------------------------------------
"$VANTAGE_ROOT/scripts/assert.sh" keystore-preflight "$KEYSTORE"

A="$VANTAGE_ROOT/config/assertions"
build_variant() {
  # $1 name  $2 mpp  $3 options  $4 pkg  $5 arch  $6 appver  $7 out-apk
  # $8 exp-package  $9 label  $10 exclusive(yes/"")  $11 exp-count  $12 nonneg
  # $13 inert  $14 settings(optional)  $15 min-size-mb
  local name="$1" mpp="$2" options="$3" pkg="$4" arch="$5" appver="$6" outapk="$7"
  local exppkg="$8" label="$9" excl="${10}" count="${11}" nonneg="${12}" inert="${13}" settings="${14}" minmb="${15}"
  local stock="$STOCK/${pkg}-${appver}.apk"
  local result="$OUT/${name}-result.json" logf="$OUT/${name}-patch.log" tmp="$TMPROOT/$name"
  rm -rf "$tmp"; mkdir -p "$tmp"

  "$VANTAGE_ROOT/scripts/download-apk.sh" "$pkg" "$appver" "$arch" "$stock"

  "$VANTAGE_ROOT/scripts/patch.sh" \
    --jar "$CLI_JAR" --patches "$mpp" --options "$options" \
    --keystore "$KEYSTORE" --apk "$stock" --out "$OUT/$outapk" \
    --result "$result" --log "$logf" --tmp "$tmp" \
    ${excl:+--exclusive}

  local -a aa=(variant --variant "$name" --result "$result" --log "$logf" \
    --apk "$OUT/$outapk" --package "$exppkg" --label "$label" \
    --nonneg "$nonneg" --inert "$inert" --min-size-mb "$minmb")
  [ -n "$count" ] && aa+=(--expected-count "$count")
  [ -n "$settings" ] && aa+=(--settings "$settings")
  "$VANTAGE_ROOT/scripts/assert.sh" "${aa[@]}"

  cp "$OUT/$outapk" "$OUTDIR/$outapk"
  log "staged $OUTDIR/$outapk"
}

# ---- the three variants ---------------------------------------------------
build_variant "youtube" "$ANDDEA_MPP" "$VANTAGE_ROOT/config/youtube-options.json" \
  "$YT_PACKAGE" "$YT_ARCH" "$YT_VER" "vantage-youtube-${YT_VER}-anddea.apk" \
  "app.vantage.youtube" "Vantage" "yes" "$(cat "$A/youtube-expected-count.txt")" \
  "$A/youtube-nonnegotiable.txt" "$A/youtube-inert-allowlist.txt" \
  "$VANTAGE_ROOT/config/settings/vantage-youtube.json" "40"

build_variant "youtube-alt" "$ANDDEA_MPP" "$VANTAGE_ROOT/config/youtube-alt-options.json" \
  "$YT_PACKAGE" "$YT_ARCH" "$YT_VER" "vantage-youtube-${YT_VER}-alt.apk" \
  "app.vantage.youtube.alt" "Vantage Alt" "yes" "$(cat "$A/youtube-expected-count.txt")" \
  "$A/youtube-nonnegotiable.txt" "$A/youtube-inert-allowlist.txt" \
  "$VANTAGE_ROOT/config/settings/vantage-youtube.json" "40"

build_variant "music" "$ANDDEA_MPP" "$VANTAGE_ROOT/config/music-options.json" \
  "$MUSIC_PACKAGE" "$MUSIC_ARCH" "$MUSIC_VER" "vantage-music-${MUSIC_VER}.apk" \
  "app.vantage.youtube.music" "Vantage Music" "" "" \
  "$A/music-nonnegotiable.txt" "$A/music-inert-allowlist.txt" \
  "$VANTAGE_ROOT/config/settings/vantage-music.json" "30"

build_variant "morphe" "$MORPHE_MPP" "$VANTAGE_ROOT/config/morphe-youtube-options.json" \
  "$YT_PACKAGE" "$YT_ARCH" "$MORPHE_YT_VER" "vantage-youtube-${MORPHE_YT_VER}-morphe.apk" \
  "app.vantage.youtube.morphe" "Vantage M" "" "" \
  "$A/morphe-nonnegotiable.txt" "$A/morphe-inert-allowlist.txt" "" "40"

# ---- manifest -------------------------------------------------------------
MANIFEST="$OUTDIR/built-versions.json"
jq -n \
  --arg builtAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg anddea "$ANDDEA_VERSION" --arg morphe "$MORPHE_VERSION" \
  --arg cli "$MORPHE_CLI_VERSION" \
  --arg yt "$YT_VER" --arg music "$MUSIC_VER" --arg mor_yt "$MORPHE_YT_VER" \
  '{builtAt:$builtAt, anddeaVersion:$anddea, morphePatchesVersion:$morphe,
    morpheCliVersion:$cli, youtubeVersion:$yt, musicVersion:$music,
    morpheYoutubeVersion:$mor_yt}' > "$MANIFEST"
log "wrote manifest:"; cat "$MANIFEST"

# Ship the settings files with the release (optional reset-only now that
# defaults are baked into the fork's .mpp).
cp "$VANTAGE_ROOT/config/settings/vantage-youtube.json" "$OUTDIR/" 2>/dev/null || true
cp "$VANTAGE_ROOT/config/settings/vantage-music.json" "$OUTDIR/" 2>/dev/null || true

# Ship the Obtainium one-tap onboarding config (MicroG-RE + the 3 Vantage apps).
cp "$VANTAGE_ROOT/obtainium-config.json" "$OUTDIR/" 2>/dev/null \
  || warn "obtainium-config.json not found - skipping (release will lack the onboarding config)"

# ---- release (optional; workflow does this by default) --------------------
TAG="v$(date -u +%Y.%m.%d)-anddea${ANDDEA_VERSION}-morphe${MORPHE_VERSION}"
echo "RELEASE_TAG=$TAG" > "$WORK/release.env"
echo "YT_VER=$YT_VER" >> "$WORK/release.env"
echo "MUSIC_VER=$MUSIC_VER" >> "$WORK/release.env"
echo "MORPHE_YT_VER=$MORPHE_YT_VER" >> "$WORK/release.env"
log "release tag would be: $TAG"

if [ -n "$DO_RELEASE" ]; then
  GH_REPO="${GITHUB_REPOSITORY:-${VANTAGE_REPO:-}}"
  [ -n "$GH_REPO" ] || die "--release needs GITHUB_REPOSITORY or VANTAGE_REPO"
  local_notes="$WORK/notes.md"
  {
    echo "Vantage build $TAG"
    echo
    echo "- YouTube (anddea): $YT_VER"
    echo "- YouTube Music: $MUSIC_VER"
    echo "- YouTube (Morphe): $MORPHE_YT_VER"
    echo "- anddea patches: $ANDDEA_VERSION | morphe patches: $MORPHE_VERSION | morphe-cli: $MORPHE_CLI_VERSION"
  } > "$local_notes"
  # Idempotent: a same-day rebuild reuses the date+versions tag. If the release
  # already exists (re-run for the same patch versions), UPDATE it in place
  # (clobber same-named assets, refresh notes) instead of failing on "already
  # exists". Otherwise create it fresh.
  local_assets=("$OUTDIR"/*.apk "$MANIFEST" "$OUTDIR/vantage-youtube.json" "$OUTDIR/vantage-music.json")
  [ -f "$OUTDIR/obtainium-config.json" ] && local_assets+=("$OUTDIR/obtainium-config.json")
  if gh release view "$TAG" -R "$GH_REPO" >/dev/null 2>&1; then
    log "release $TAG exists - updating in place (clobber assets + notes)"
    retry 4 gh release edit "$TAG" -R "$GH_REPO" --notes-file "$local_notes" || warn "could not update release notes"
    retry 4 gh release upload "$TAG" -R "$GH_REPO" "${local_assets[@]}" --clobber \
      || die "failed to upload assets to existing release $TAG"
  else
    log "creating GitHub release $TAG on $GH_REPO"
    retry 4 gh release create "$TAG" -R "$GH_REPO" --title "$TAG" --notes-file "$local_notes" \
      "${local_assets[@]}"
  fi
fi

log "BUILD COMPLETE. Staged in $OUTDIR"
ls -la "$OUTDIR"
