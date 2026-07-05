#!/usr/bin/env bash
#
# patch.sh - run one morphe-cli patch pass for a variant.
#
# Patch selection + option values live entirely in the --options-file JSON
# ("enabled" per patch); there are no -e flags. We don't pass
# --continue-on-error: a real patch exception must abort with a non-zero exit
# (CI wants hard failures). --exclusive is used for the curated YouTube set so a
# future default-enabled upstream patch cannot sneak into the build.
#
# Icon options reference a repo-relative folder path (e.g. "config/icon/vantage").
# morphe-cli resolves paths against its CWD, which is not guaranteed, so we
# rewrite those to absolute paths in a runtime copy of the options file.
#
# Usage:
#   patch.sh --jar <cli.jar> --patches <bundle.mpp> --options <options.json> \
#            --keystore <ks> --apk <stock.apk> --out <out.apk> \
#            --result <result.json> --log <patch.log> --tmp <shortdir> [--exclusive]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env

JAR="" PATCHES="" OPTIONS="" KEYSTORE="" APK="" OUT="" RESULT="" LOG="" TMP="" EXCLUSIVE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jar) JAR="$2"; shift 2;;
    --patches) PATCHES="$2"; shift 2;;
    --options) OPTIONS="$2"; shift 2;;
    --keystore) KEYSTORE="$2"; shift 2;;
    --apk) APK="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --result) RESULT="$2"; shift 2;;
    --log) LOG="$2"; shift 2;;
    --tmp) TMP="$2"; shift 2;;
    --exclusive) EXCLUSIVE="--exclusive"; shift;;
    *) die "unknown arg: $1";;
  esac
done
for v in JAR PATCHES OPTIONS KEYSTORE APK OUT RESULT LOG TMP; do
  [ -n "${!v}" ] || die "patch.sh: missing --${v,,}"
  case "$v" in JAR|PATCHES|OPTIONS|KEYSTORE|APK) [ -f "${!v}" ] || die "not found: ${!v}";; esac
done

mkdir -p "$(dirname "$OUT")" "$(dirname "$RESULT")" "$(dirname "$LOG")" "$TMP"

# Rewrite repo-relative icon folder paths -> absolute in a runtime options copy.
RUNTIME_OPTIONS="$TMP/options.$(basename "$OPTIONS")"
sed "s#\"config/icon/#\"$VANTAGE_ROOT/config/icon/#g" "$OPTIONS" > "$RUNTIME_OPTIONS"

log "Patching $(basename "$APK") -> $(basename "$OUT")"
log "  patches=$(basename "$PATCHES") options=$(basename "$OPTIONS") ${EXCLUSIVE:+exclusive}"

# Run. Tee full CLI output to the log (assert.sh greps it). set -o pipefail
# makes the tee preserve morphe-cli's exit code.
set +e
# Signing creds come from the environment (secrets), not hardcoded. The keystore
# itself is decoded from a secret by build.sh (repo is public - no committed key).
: "${VANTAGE_KEYSTORE_PASS:?VANTAGE_KEYSTORE_PASS must be set (keystore + entry password)}"
KS_ALIAS="${VANTAGE_KEYSTORE_ALIAS:-vantage}"
java -jar "$JAR" patch \
  --patches="$PATCHES" \
  --options-file="$RUNTIME_OPTIONS" \
  $EXCLUSIVE \
  --keystore="$KEYSTORE" \
  --keystore-entry-alias="$KS_ALIAS" \
  --keystore-password="$VANTAGE_KEYSTORE_PASS" \
  --keystore-entry-password="$VANTAGE_KEYSTORE_PASS" \
  -o "$OUT" \
  -r "$RESULT" \
  -t "$TMP" \
  "$APK" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

[ "$rc" -eq 0 ] || die "morphe-cli exited $rc (see $LOG). NOTE: a non-zero exit is a genuine patch exception - do not add --continue-on-error."
[ -f "$OUT" ] || die "morphe-cli reported success but produced no output APK"
[ -f "$RESULT" ] || die "no result JSON at $RESULT"
log "Patch OK: $OUT ($(du -h "$OUT" | cut -f1))"
