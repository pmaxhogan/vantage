#!/usr/bin/env bash
#
# probe-sources.sh - diagnostic: which stock-APK download sources actually work
# from this host (meant to run on a GitHub Actions runner to learn datacenter-IP
# reachability). It bypasses the stock-cache and, for each app + each source in
# DL_SOURCES, runs that source's resolver and the full verify() gate, reporting
# PASS/FAIL per (app, source). It doesn't patch, release, or touch the cache -
# pure probe.
#
# Usage: probe-sources.sh
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env
# Source the downloader for its src_* resolvers + verify() (main won't run: it is
# guarded by BASH_SOURCE==0, and here we are sourcing, not executing it).
. "$(dirname "${BASH_SOURCE[0]}")/download-apk.sh"
# download-apk.sh sets `-e`; a probe must survive individual source failures, so
# turn errexit back off (we handle every non-zero explicitly below).
set +e

: "${DL_SOURCES:=apkmirror apkpure apkcombo aptoide}"

# (package, version, arch) triples to probe - the versions the build targets today.
PROBES=(
  "com.google.android.youtube 20.51.39 universal"
  "com.google.android.apps.youtube.music 9.15.51 arm64-v8a"
)

overall=0
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
for probe in "${PROBES[@]}"; do
  # shellcheck disable=SC2086
  set -- $probe
  PKG="$1"; VER="$2"; ARCH="$3"
  log "==================================================================="
  log "PROBE: $PKG $VER ($ARCH)"
  any_pass=0
  for src in $DL_SOURCES; do
    fn="src_${src}"
    if ! declare -F "$fn" >/dev/null 2>&1; then warn "  [$src] no resolver - skip"; continue; fi
    cand="$scratch/${src}-${PKG}-${VER}.apk"; rm -f "$cand"
    if ! "$fn" "$cand" >/dev/null 2>&1; then
      log "  [$src] RESOLVE-FAIL (no download / unreachable)"
      continue
    fi
    if verify "$cand" >/dev/null 2>&1; then
      log "  [$src] PASS (downloaded + verified genuine Google-signed $VER)"
      any_pass=1
    else
      log "  [$src] DOWNLOADED-BUT-REJECTED (failed verify - challenge page / wrong ver / bad signer)"
    fi
    rm -f "$cand"
  done
  if [ "$any_pass" -eq 0 ]; then
    warn "  RESULT: no source produced a verified APK for $PKG $VER (cache seed required)"
    overall=1
  else
    log "  RESULT: at least one source works for $PKG $VER"
  fi
done

log "==================================================================="
if [ "$overall" -eq 0 ]; then
  log "PROBE SUMMARY: every probed app has at least one working live source."
else
  warn "PROBE SUMMARY: one or more apps have NO working live source from this host - rely on the seeded cache + manual seed on version bumps."
fi
# Informational only - always exit 0 so the workflow surfaces the log without
# being marked failed (a no-working-source result is expected/known, not a bug).
exit 0
