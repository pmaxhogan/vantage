#!/usr/bin/env bash
# Shared helpers for Vantage build scripts. Source this, do not execute it.
# Every script that sources this runs under `set -euo pipefail`.

# Repo root = parent of scripts/. Resolve regardless of caller CWD.
VANTAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VANTAGE_ROOT

# ---- logging -------------------------------------------------------------
log()  { printf '%s [vantage] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
warn() { printf '%s [vantage][WARN] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die()  { printf '%s [vantage][FAIL] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; exit 1; }

# Re-run a command a few times before giving up. GitHub's release/asset API
# throws the odd 5xx, so wrap the flaky network calls in this.
retry() {
  local tries="$1"; shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$tries" ]; then return 1; fi
    warn "attempt $n/$tries failed, retrying in $((n*5))s: $*"
    sleep "$((n*5))"
    n=$((n+1))
  done
}

# ---- config --------------------------------------------------------------
load_build_env() {
  local env_file="$VANTAGE_ROOT/config/build.env"
  [ -f "$env_file" ] || die "missing config/build.env"
  # shellcheck disable=SC1090
  set -a; . "$env_file"; set +a
}

# ---- signing keystore ----------------------------------------------------
# Materialize the signing keystore to $1 from the VANTAGE_KEYSTORE_B64 secret
# (CI) or a local VANTAGE_KEYSTORE_FILE, then export the pass + alias. base64
# round-trips byte-for-byte, so the decoded file still matches the pinned
# VANTAGE_KEYSTORE_SHA256 guard. Shared by build.sh and build-x.sh so the two
# never drift. The key is never committed - the repo is public.
resolve_signing_keystore() {
  local dest="${1:?keystore dest path}"
  if [ -n "${VANTAGE_KEYSTORE_B64:-}" ]; then
    printf '%s' "$VANTAGE_KEYSTORE_B64" | base64 -d > "$dest" \
      || die "failed to base64-decode VANTAGE_KEYSTORE_B64"
    log "decoded signing keystore from VANTAGE_KEYSTORE_B64"
  elif [ -n "${VANTAGE_KEYSTORE_FILE:-}" ] && [ -f "${VANTAGE_KEYSTORE_FILE}" ]; then
    cp "$VANTAGE_KEYSTORE_FILE" "$dest"
    log "using local signing keystore from VANTAGE_KEYSTORE_FILE"
  else
    die "no signing keystore: set VANTAGE_KEYSTORE_B64 (CI secret) or VANTAGE_KEYSTORE_FILE (local path)"
  fi
  : "${VANTAGE_KEYSTORE_PASS:?VANTAGE_KEYSTORE_PASS must be set (keystore + entry password)}"
  export VANTAGE_KEYSTORE_PASS VANTAGE_KEYSTORE_ALIAS="${VANTAGE_KEYSTORE_ALIAS:-vantage}"
}

# ---- Android SDK tools ---------------------------------------------------
# ubuntu-latest ships the Android SDK (aapt/aapt2/apksigner). Prefer PATH, then
# $ANDROID_HOME / $ANDROID_SDK_ROOT build-tools (highest version wins).
find_sdk_tool() {
  local tool="$1" found
  if command -v "$tool" >/dev/null 2>&1; then command -v "$tool"; return 0; fi
  local root
  for root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
    [ -n "$root" ] && [ -d "$root/build-tools" ] || continue
    found="$(find "$root/build-tools" -maxdepth 2 -name "$tool" -type f 2>/dev/null | sort -V | tail -1)"
    [ -n "$found" ] && { printf '%s\n' "$found"; return 0; }
  done
  return 1
}

# sha256 of a file, hex only, portable across coreutils / macOS.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Resolve the newest patch-compatible app version for a package from a .mpp
# bundle via `morphe-cli list-versions` (newest version in the top patch-count
# tier). A non-empty $4 pins/overrides. Single source of truth for the most
# compatible version to build.
# Usage: resolve_target_version <cli_jar> <mpp> <package> [pin]
resolve_target_version() {
  local jar="$1" mpp="$2" pkg="$3" pin="${4:-}"
  if [ -n "$pin" ]; then printf '%s\n' "$pin"; return 0; fi
  # list-versions has failed transiently in CI (runs 30001758724/30087966622):
  # the same jar+mpp bytes resolved fine later on the same runner image, and the
  # old 2>/dev/null discarded the only evidence. Keep stderr, surface it on
  # failure, and retry before dying.
  local out rc attempt errf
  errf="$(mktemp)"
  for attempt in 1 2 3; do
    rc=0
    out="$(java -jar "$jar" list-versions --patches="$mpp" -f "$pkg" 2>"$errf" \
      | sed 's/\x1b\[[0-9;]*m//g')" || rc=$?
    if [ "$rc" -eq 0 ] && grep -qE '\([0-9]+ patches\)' <<<"$out"; then break; fi
    warn "list-versions attempt $attempt/3 for $pkg failed (java exit $rc)"
    [ -s "$errf" ] && sed 's/^/  [stderr] /' "$errf" >&2
    [ -n "$out" ] && sed 's/^/  [stdout] /' <<<"$out" >&2
    [ "$attempt" -lt 3 ] && sleep $((attempt * 5))
  done
  rm -f "$errf"
  # Lines like "\t20.51.39 (60 patches)" or "\t12.2.0-release.0 (67 patches)". Take
  # the max patch-count tier, then the newest version in it. Keep the FULL version
  # token (everything before " (") instead of a digits-only regex, so a suffixed
  # string like "12.2.0-release.0" survives for the versionName gate - stripping it
  # to "12.2.0" would never match the real APK. Drop "-ripped" targets: those are
  # repackaged, non-vendor-signed builds that can't pass the signing-cert gate.
  local maxc; maxc="$(grep -oE '\(([0-9]+) patches\)' <<<"$out" | grep -oE '[0-9]+' | sort -n | tail -1)"
  [ -n "$maxc" ] || die "list-versions produced no versions for $pkg"
  grep -E "\($maxc patches\)" <<<"$out" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]*\([0-9]+ patches\).*$//' \
    | grep -viE 'ripped' | sort -V | tail -1
}

# Read a data file into a bash array, skipping blank lines and # comments.
# Usage: read_list OUT_ARRAY_NAME path/to/file
read_list() {
  local __arr="$1" __file="$2" __line
  eval "$__arr=()"
  [ -f "$__file" ] || die "missing list file: $__file"
  while IFS= read -r __line || [ -n "$__line" ]; do
    __line="${__line%%$'\r'}"                 # tolerate stray CR
    case "$__line" in ''|\#*) continue;; esac
    eval "$__arr+=(\"\$__line\")"
  done < "$__file"
}
