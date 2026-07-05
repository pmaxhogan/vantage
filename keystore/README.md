# Vantage signing keystore

## The keystore isn't in this repo

The signing keystore is never committed. It's stored base64-encoded in the
`VANTAGE_KEYSTORE_B64` secret and decoded to a runtime file by `scripts/build.sh`
at build time; the password and alias are secrets too. Nothing under `keystore/`
is a real key. This README documents how signing works.

### Signing secrets (Settings, Secrets and variables, Actions)

| Secret | What |
|---|---|
| `VANTAGE_KEYSTORE_B64` | `base64 -w0` of the `.keystore` file |
| `VANTAGE_KEYSTORE_PASS` | keystore password (also the entry password) |
| `VANTAGE_KEYSTORE_ALIAS` | key entry alias (defaults to `vantage`) |
| `VANTAGE_KEYSTORE_SHA256` | SHA-256 of the `.keystore` file (pre-flight guard) |
| `VANTAGE_CERT_SHA256` | signing-cert SHA-256 fingerprint (post-build guard) |

`build.sh` decodes `VANTAGE_KEYSTORE_B64` to `build/vantage.keystore` (base64
round-trips byte-for-byte, so the decoded file's SHA-256 still matches
`VANTAGE_KEYSTORE_SHA256`). `patch.sh` then calls morphe-cli with:

```
--keystore <decoded.keystore> \
--keystore-entry-alias "$VANTAGE_KEYSTORE_ALIAS" \
--keystore-password "$VANTAGE_KEYSTORE_PASS" \
--keystore-entry-password "$VANTAGE_KEYSTORE_PASS"
```

For a local build, point at a real keystore on disk instead of putting it in the
repo:

```bash
export VANTAGE_KEYSTORE_FILE=/secure/path/vantage.keystore
export VANTAGE_KEYSTORE_PASS=...          # keystore + entry password
export VANTAGE_KEYSTORE_ALIAS=vantage     # optional; defaults to vantage
```

## Why the key can't change or be lost

Android identifies an app by package name plus signing certificate. Once a phone
has a Vantage build installed, every update has to be signed by this same key or
the install is rejected and the user has to uninstall first, losing app data. So:

- Losing the key breaks in-place updates for everyone who already installed. Back
  it up outside this repo (a password manager or vault) as well as in the
  `VANTAGE_KEYSTORE_B64` secret.
- Don't regenerate it. If morphe-cli can't load the keystore it silently
  generates a new one and signs with that, producing an APK that looks fine but
  won't install as an update. The guards below catch this.
- Rotating the key is a breaking change - the signature differs, so every
  existing install has to be uninstalled and reinstalled once. Note it in the
  first post-rotation release.

## The two guards (scripts/assert.sh)

1. Pre-flight hash pin. Before patching, the decoded keystore's SHA-256 must equal
   `VANTAGE_KEYSTORE_SHA256`. A mismatch or a failed decode fails the build before
   any APK is produced.
2. Post-build cert pin. After signing, `apksigner verify --print-certs` on the
   output must report a signing cert SHA-256 equal to `VANTAGE_CERT_SHA256`. This
   proves the intended key signed the output, not a regenerated one.

### Computing the two pinned values (once, from the real keystore)

```bash
# keystore file hash -> VANTAGE_KEYSTORE_SHA256
sha256sum vantage.keystore | cut -d' ' -f1

# cert fingerprint -> VANTAGE_CERT_SHA256 (lowercase hex, no colons)
keytool -list -v -keystore vantage.keystore -storepass "$PASS" \
  | grep -i 'SHA256:' | head -1 | awk '{print $2}' | tr -d ':' | tr 'A-F' 'a-f'
# (or build one APK and: apksigner verify --print-certs out.apk | grep 'SHA-256 digest')
```

If either guard secret is unset (e.g. a bare local run) the guard warns and skips
instead of failing - but CI should always have both.
