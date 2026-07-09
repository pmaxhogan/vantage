#!/usr/bin/env bash
#
# assert.sh - the hard CI guards. morphe-cli's own exit code is not trusted: it
# only warns on renamed/removed patch names and counts version-incompatible-but-
# inert patches as "applied". So we independently verify the result JSON, the
# log, the signing cert, and the APK structure.
#
# Two subcommands:
#   assert.sh keystore-preflight <keystore>
#       Assert the keystore exists and its SHA-256 == $VANTAGE_KEYSTORE_SHA256.
#       Runs before patching so a missing/replaced key can never lead to a
#       silently re-keyed release.
#
#   assert.sh variant --variant <name> --result <json> --log <log> --apk <apk> \
#       --package <pkg> --label <label> --nonneg <file> --inert <file> \
#       [--expected-count <n>] [--settings <json>] [--min-size-mb <n>]
#       All post-build checks. Any failure exits non-zero (blocks the release).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_build_env
command -v jq >/dev/null 2>&1 || die "jq not found"

# ============================ keystore-preflight ============================
keystore_preflight() {
  local ks="${1:?keystore path}"
  [ -f "$ks" ] || die "keystore not found: $ks (morphe-cli would silently mint a NEW key -> broken in-place updates)"
  if [ -z "${VANTAGE_KEYSTORE_SHA256:-}" ]; then
    warn "VANTAGE_KEYSTORE_SHA256 unset - SKIPPING keystore hash pin (CI MUST set this secret)"
    return 0
  fi
  local got; got="$(sha256_of "$ks")"
  [ "$got" = "$VANTAGE_KEYSTORE_SHA256" ] \
    || die "keystore SHA-256 mismatch. expected=$VANTAGE_KEYSTORE_SHA256 got=$got (wrong/corrupt keystore)"
  log "keystore preflight OK (hash pinned)"
}

# ================================ variant ==================================
assert_variant() {
  local NAME="" RESULT="" LOG="" APK="" PKG="" LABEL="" NONNEG="" INERT="" FORBIDDEN="" COUNT="" SETTINGS="" MINMB="40"
  while [ $# -gt 0 ]; do
    case "$1" in
      --variant) NAME="$2"; shift 2;;
      --result) RESULT="$2"; shift 2;;
      --log) LOG="$2"; shift 2;;
      --apk) APK="$2"; shift 2;;
      --package) PKG="$2"; shift 2;;
      --label) LABEL="$2"; shift 2;;
      --nonneg) NONNEG="$2"; shift 2;;
      --inert) INERT="$2"; shift 2;;
      --forbidden) FORBIDDEN="$2"; shift 2;;
      --expected-count) COUNT="$2"; shift 2;;
      --settings) SETTINGS="$2"; shift 2;;
      --min-size-mb) MINMB="$2"; shift 2;;
      *) die "unknown arg: $1";;
    esac
  done
  for v in NAME RESULT LOG APK PKG NONNEG INERT; do
    [ -n "${!v}" ] || die "assert variant: missing --${v,,}"
  done
  for f in "$RESULT" "$LOG" "$APK"; do [ -f "$f" ] || die "not found: $f"; done
  local fail=0
  log "=== asserting variant: $NAME ==="

  # --- 1. failedPatches must be empty --------------------------------------
  local nfailed; nfailed="$(jq '.failedPatches | length' "$RESULT")"
  if [ "$nfailed" -ne 0 ]; then
    warn "[$NAME] failedPatches is non-empty ($nfailed):"; jq -r '.failedPatches[].name' "$RESULT" >&2; fail=1
  else log "[$NAME] failedPatches == [] OK"; fi

  # --- 2. every non-negotiable name present in appliedPatches[] ------------
  local applied; applied="$(jq -r '.appliedPatches[].name' "$RESULT")"
  local -a need; read_list need "$NONNEG"
  local n
  for n in "${need[@]}"; do
    if ! grep -Fxq "$n" <<<"$applied"; then
      warn "[$NAME] NON-NEGOTIABLE patch MISSING from appliedPatches: '$n' (upstream rename or dropped support?)"; fail=1
    fi
  done
  [ "$fail" -eq 0 ] && log "[$NAME] all ${#need[@]} non-negotiable patches present OK"

  # --- 2b. forbidden patches must NOT be in appliedPatches -----------------
  # morphe can re-add a deselected patch as another patch's dependency, so an
  # "enabled": false in the options file is not a guarantee. This fails the build
  # if a forbidden patch actually applied.
  if [ -n "$FORBIDDEN" ] && [ -f "$FORBIDDEN" ]; then
    local -a forbid; read_list forbid "$FORBIDDEN"
    local fb
    for fb in "${forbid[@]:-}"; do
      [ -z "$fb" ] && continue
      if grep -Fxq "$fb" <<<"$applied"; then
        warn "[$NAME] FORBIDDEN patch present in appliedPatches: '$fb' (excluded on purpose - a dependency pulled it back in)"; fail=1
      else
        log "[$NAME] forbidden patch absent OK: '$fb'"
      fi
    done
  fi

  # --- 3. exact applied count (curated/exclusive sets only) ----------------
  if [ -n "$COUNT" ]; then
    local got; got="$(jq '.appliedPatches | length' "$RESULT")"
    if [ "$got" -ne "$COUNT" ]; then
      warn "[$NAME] applied-count $got != expected $COUNT"; jq -r '.appliedPatches[].name' "$RESULT" | sort >&2; fail=1
    else log "[$NAME] applied-count == $COUNT OK"; fi
  fi

  # --- 4. "not supported in this version" grep vs inert allowlist ----------
  local -a inert; read_list inert "$INERT" 2>/dev/null || inert=()
  local -a unsup=(); local line pname
  while IFS= read -r line; do
    pname="$(sed -E 's/.*"([^"]+)".*/\1/' <<<"$line")"
    unsup+=("$pname")
  done < <(grep -i 'is not supported in this version' "$LOG" || true)
  for pname in "${unsup[@]:-}"; do
    [ -z "$pname" ] && continue
    if printf '%s\n' "${inert[@]:-}" | grep -Fxq "$pname"; then
      log "[$NAME] inert (allowlisted): '$pname'"
    else
      warn "[$NAME] UNEXPECTED inert patch (not in allowlist): '$pname' - it applied but does NOTHING on this version"; fail=1
    fi
  done

  # --- 4b. custom-icon guard ----------------------------------------------
  # The Custom branding icon patch only warns on an unresolvable icon folder path
  # ("Invalid app icon path: ..."); it still reports "Applied" and counts toward
  # appliedPatches, so a silently-skipped icon would otherwise pass every check.
  # A skipped icon must fail the build.
  if grep -qi 'Invalid app icon path' "$LOG"; then
    warn "[$NAME] custom icon SILENTLY SKIPPED - morphe-cli logged 'Invalid app icon path' (the APK carries the stock icon)"
    grep -i 'Invalid app icon path' "$LOG" >&2
    fail=1
  else
    log "[$NAME] no 'Invalid app icon path' warning OK"
  fi

  # --- 5. signing cert fingerprint pin -------------------------------------
  local apksigner; apksigner="$(find_sdk_tool apksigner || find_sdk_tool apksigner.bat || true)"
  if [ -z "$apksigner" ]; then
    warn "[$NAME] apksigner not found - SKIPPING cert fingerprint check (Android SDK expected in CI)"
  else
    local cert; cert="$("$apksigner" verify --print-certs "$APK" 2>/dev/null \
      | grep -i 'certificate SHA-256 digest' | head -1 | awk '{print $NF}')"
    [ -n "$cert" ] || { warn "[$NAME] could not read signing cert"; fail=1; }
    if [ -n "${VANTAGE_CERT_SHA256:-}" ]; then
      if [ "$cert" = "$VANTAGE_CERT_SHA256" ]; then log "[$NAME] cert fingerprint pinned OK"
      else warn "[$NAME] cert SHA-256 mismatch expected=$VANTAGE_CERT_SHA256 got=$cert (APK NOT signed by the committed key!)"; fail=1; fi
    else
      warn "[$NAME] VANTAGE_CERT_SHA256 unset - cannot pin cert (got $cert). CI MUST set this secret."
    fi
  fi

  # --- 6. aapt package name + label ----------------------------------------
  local aapt; aapt="$(find_sdk_tool aapt || find_sdk_tool aapt.exe || true)"
  if [ -z "$aapt" ]; then
    warn "[$NAME] aapt not found - SKIPPING package/label check"
  else
    local badging pkg_got label_got
    badging="$("$aapt" dump badging "$APK" 2>/dev/null)"
    pkg_got="$(grep -oE "^package: name='[^']*'" <<<"$badging" | sed -E "s/.*name='([^']*)'.*/\1/")"
    label_got="$(grep -oE "^application-label:'[^']*'" <<<"$badging" | sed -E "s/.*:'([^']*)'.*/\1/")"
    [ "$pkg_got" = "$PKG" ] && log "[$NAME] package '$pkg_got' OK" \
      || { warn "[$NAME] package mismatch expected='$PKG' got='$pkg_got'"; fail=1; }
    # Label is optional: pass --label to pin it, omit to only record it. The X
    # build leaves it unpinned (its label is whatever piko's Change app icon sets)
    # while still pinning the security-relevant package name above.
    if [ -n "$LABEL" ]; then
      [ "$label_got" = "$LABEL" ] && log "[$NAME] label '$label_got' OK" \
        || { warn "[$NAME] label mismatch expected='$LABEL' got='$label_got'"; fail=1; }
    else
      log "[$NAME] label '$label_got' (not pinned)"
    fi
  fi

  # --- 7. size threshold + zip integrity -----------------------------------
  local bytes mb; bytes="$(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK")"; mb=$((bytes/1024/1024))
  if [ "$mb" -lt "$MINMB" ]; then warn "[$NAME] APK too small: ${mb}MB < ${MINMB}MB"; fail=1
  else log "[$NAME] size ${mb}MB OK"; fi
  if command -v unzip >/dev/null 2>&1; then
    unzip -qt "$APK" >/dev/null 2>&1 && log "[$NAME] zip integrity OK" \
      || { warn "[$NAME] zip integrity check FAILED"; fail=1; }
  fi

  # --- 8. settings-key guard (on version bumps) ----------------------------
  # The settings file is RVX's own export: a JSON body (may lack wrapping
  # braces) whose keys have the "revanced_" prefix stripped (e.g. change_start_page,
  # not revanced_change_start_page). So we extract keys by regex (format-agnostic,
  # no jq dependency) and look each up in the dex as both the prefixed shared-pref
  # form (revanced_<key>, what Settings.java actually references) and the bare key,
  # failing only if neither is present. An upstream key rename would then trip this,
  # since a renamed key silently reverts its setting to default on the in-place update.
  if [ -n "$SETTINGS" ] && [ -f "$SETTINGS" ]; then
    local keys; keys="$(grep -oE '"[A-Za-z0-9_]+"[[:space:]]*:' "$SETTINGS" 2>/dev/null \
      | sed -E 's/[":[:space:]]//g' | sort -u || true)"
    if [ -z "$keys" ]; then
      log "[$NAME] settings-key guard: no keys in $(basename "$SETTINGS") (settings not yet captured - non-fatal)"
    elif command -v unzip >/dev/null 2>&1 && command -v strings >/dev/null 2>&1; then
      local dexdir; dexdir="$(mktemp -d)"
      unzip -qo "$APK" 'classes*.dex' -d "$dexdir" 2>/dev/null || true
      local allstr; allstr="$(cat "$dexdir"/classes*.dex 2>/dev/null | strings || true)"
      local k
      while IFS= read -r k; do
        [ -z "$k" ] && continue
        if grep -Fq "revanced_$k" <<<"$allstr" || grep -Fq "$k" <<<"$allstr"; then
          log "[$NAME] settings key present: $k"
        else
          warn "[$NAME] settings key MISSING from dex: $k (upstream rename would silently revert this setting on update)"; fail=1
        fi
      done <<<"$keys"
      rm -rf "$dexdir"
    else
      warn "[$NAME] settings-key guard: unzip/strings unavailable - skipped"
    fi
  fi

  if [ "$fail" -ne 0 ]; then die "[$NAME] ASSERTIONS FAILED - build must not be released"; fi
  log "=== [$NAME] ALL ASSERTIONS PASSED ==="
}

# ================================ dispatch =================================
sub="${1:?subcommand: keystore-preflight | variant}"; shift || true
case "$sub" in
  keystore-preflight) keystore_preflight "$@";;
  variant)            assert_variant "$@";;
  *) die "unknown subcommand: $sub";;
esac
