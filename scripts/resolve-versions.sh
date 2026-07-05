#!/usr/bin/env bash
#
# resolve-versions.sh - work out which upstream patch versions to build with and
# whether a build is even needed (skip logic). State is the latest release, not
# a committed file: skip logic reads the newest build release's built-versions.json
# manifest asset, never a state file in the tree.
#
# Resolves:
#   - anddea dev channel  = latest PRERELEASE on ANDDEA_REPO (+ its .mpp asset URL)
#   - morphe channel      = latest stable RELEASE on MORPHE_PATCHES_REPO (+ .mpp URL)
#   - morphe-cli          = PINNED MORPHE_CLI_VERSION jar URL
#   - NEEDS_BUILD         = true unless (both patch versions == last release's
#                           manifest) and not --force
#
# Writes KEY=VALUE lines to the output file (arg 1, default build/resolved.env)
# and echoes a human summary. Requires `gh` (authenticated) and `jq`.
#
# Usage: resolve-versions.sh [OUTFILE] [--force]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

OUTFILE="${1:-$VANTAGE_ROOT/build/resolved.env}"
FORCE="false"
for a in "$@"; do [ "$a" = "--force" ] && FORCE="true"; done
mkdir -p "$(dirname "$OUTFILE")"

command -v gh >/dev/null 2>&1 || die "gh CLI not found (needed for release/version resolution)"
command -v jq >/dev/null 2>&1 || die "jq not found"

# Repo for release reads: GITHUB_REPOSITORY in Actions, else VANTAGE_REPO override.
GH_REPO="${GITHUB_REPOSITORY:-${VANTAGE_REPO:-}}"

# ---- anddea: latest release (fork) or prerelease (upstream) ---------------
# The fork (pmaxhogan/revanced-patches) publishes normal releases (ANDDEA_CHANNEL
# =release); upstream anddea uses prereleases for its dev channel. Support both.
if [ "${ANDDEA_CHANNEL:-prerelease}" = "release" ]; then
  log "Resolving latest release from $ANDDEA_REPO (baked-defaults fork) ..."
  anddea_json="$(gh api "repos/$ANDDEA_REPO/releases/latest")"
else
  log "Resolving anddea dev prerelease from $ANDDEA_REPO ..."
  anddea_json="$(gh api "repos/$ANDDEA_REPO/releases" --paginate \
    | jq -c "[.[] | select(.prerelease==true)] | first" )"
fi
[ "$anddea_json" != "null" ] && [ -n "$anddea_json" ] || die "no release found on $ANDDEA_REPO"
ANDDEA_VERSION="$(jq -r '.tag_name' <<<"$anddea_json" | sed 's/^v//')"
ANDDEA_MPP_URL="$(jq -r '.assets[] | select(.name|endswith(".mpp")) | .browser_download_url' <<<"$anddea_json" | head -1)"
[ -n "$ANDDEA_MPP_URL" ] || die "no .mpp asset on anddea prerelease $ANDDEA_VERSION"
log "  anddea = $ANDDEA_VERSION"

# ---- morphe patches: latest stable release --------------------------------
log "Resolving morphe stable release from $MORPHE_PATCHES_REPO ..."
morphe_json="$(gh api "repos/$MORPHE_PATCHES_REPO/releases/latest")"
MORPHE_VERSION="$(jq -r '.tag_name' <<<"$morphe_json" | sed 's/^v//')"
MORPHE_MPP_URL="$(jq -r '.assets[] | select(.name|endswith(".mpp")) | .browser_download_url' <<<"$morphe_json" | head -1)"
[ -n "$MORPHE_MPP_URL" ] || die "no .mpp asset on morphe release $MORPHE_VERSION"
log "  morphe = $MORPHE_VERSION"

# ---- morphe-cli: pinned jar ----------------------------------------------
log "Resolving pinned morphe-cli $MORPHE_CLI_VERSION jar from $MORPHE_CLI_REPO ..."
cli_json="$(gh api "repos/$MORPHE_CLI_REPO/releases/tags/v$MORPHE_CLI_VERSION" 2>/dev/null \
  || gh api "repos/$MORPHE_CLI_REPO/releases/tags/$MORPHE_CLI_VERSION")"
CLI_JAR_URL="$(jq -r '.assets[] | select(.name|endswith("-all.jar")) | .browser_download_url' <<<"$cli_json" | head -1)"
[ -n "$CLI_JAR_URL" ] || die "no -all.jar asset on morphe-cli $MORPHE_CLI_VERSION"

# ---- skip logic: compare with last build release's manifest ---------------
NEEDS_BUILD="true"
LAST_ANDDEA=""; LAST_MORPHE=""
if [ -n "$GH_REPO" ]; then
  log "Reading last build release manifest from $GH_REPO ..."
  # Newest release whose tag isn't the stock-cache tag and that has the manifest.
  last_tag="$(gh api "repos/$GH_REPO/releases" --paginate 2>/dev/null \
    | jq -r --arg cache "$STOCK_CACHE_TAG" \
        '[.[] | select(.tag_name != $cache)] | first | .tag_name // empty')" || true
  if [ -n "$last_tag" ]; then
    if gh release download "$last_tag" -R "$GH_REPO" -p 'built-versions.json' \
         -O "$OUTFILE.manifest" --clobber 2>/dev/null; then
      LAST_ANDDEA="$(jq -r '.anddeaVersion // empty' "$OUTFILE.manifest")"
      LAST_MORPHE="$(jq -r '.morphePatchesVersion // empty' "$OUTFILE.manifest")"
      log "  last release $last_tag built with anddea=$LAST_ANDDEA morphe=$LAST_MORPHE"
      if [ "$LAST_ANDDEA" = "$ANDDEA_VERSION" ] && [ "$LAST_MORPHE" = "$MORPHE_VERSION" ]; then
        NEEDS_BUILD="false"
      fi
    else
      log "  last release has no built-versions.json - treating as build-needed"
    fi
  else
    log "  no prior build release found - first build"
  fi
else
  warn "no GITHUB_REPOSITORY/VANTAGE_REPO set - cannot read last release; forcing build"
fi

if [ "$FORCE" = "true" ]; then
  NEEDS_BUILD="true"
  log "force flag set - building regardless of skip logic"
fi

# ---- emit ----------------------------------------------------------------
{
  echo "ANDDEA_VERSION=$ANDDEA_VERSION"
  echo "ANDDEA_MPP_URL=$ANDDEA_MPP_URL"
  echo "MORPHE_VERSION=$MORPHE_VERSION"
  echo "MORPHE_MPP_URL=$MORPHE_MPP_URL"
  echo "MORPHE_CLI_VERSION=$MORPHE_CLI_VERSION"
  echo "CLI_JAR_URL=$CLI_JAR_URL"
  echo "NEEDS_BUILD=$NEEDS_BUILD"
} > "$OUTFILE"
rm -f "$OUTFILE.manifest"

log "Resolved versions written to $OUTFILE"
cat "$OUTFILE"

# Also surface to GitHub Actions step outputs when available.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "needs_build=$NEEDS_BUILD"
    echo "anddea_version=$ANDDEA_VERSION"
    echo "morphe_version=$MORPHE_VERSION"
  } >> "$GITHUB_OUTPUT"
fi

log "NEEDS_BUILD=$NEEDS_BUILD"
