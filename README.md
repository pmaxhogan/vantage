# Vantage

[![Build](https://github.com/pmaxhogan/vantage/actions/workflows/build.yml/badge.svg)](https://github.com/pmaxhogan/vantage/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/pmaxhogan/vantage?label=release)](https://github.com/pmaxhogan/vantage/releases/latest)

Vantage builds patched YouTube and YouTube Music APKs, signs them with a stable
key, and publishes them as GitHub Releases. [Obtainium](https://github.com/ImranR98/Obtainium)
installs them and keeps them updated. Every variant needs
[MicroG-RE](https://github.com/MorpheApp/MicroG-RE) on the phone, an unrooted
replacement for Google Play Services, and the bundled config installs it for you.

## Install

Each release ships an `obtainium-config.json` that sets up four apps in one
import: MicroG-RE plus the three Vantage apps (Vantage, Vantage Alt, Vantage
Music), each already configured with the right APK filter and update settings.

1. Install [Obtainium](https://github.com/ImranR98/Obtainium/releases).
2. Download `obtainium-config.json` from the
   [latest release](https://github.com/pmaxhogan/vantage/releases/latest).
3. In Obtainium, open the menu, choose Import/Export, then Import from file, and
   pick it. All four apps appear.
4. Install MicroG-RE first, since the Vantage apps need it at runtime. Then
   install whichever Vantage apps you want.

Obtainium auto-updates all four as new releases land. The Vantage apps track the
release date and MicroG-RE tracks its version. The settings you'd otherwise have
to toggle by hand are baked into the patches, so a fresh install already hides
Shorts, comments, and community posts, opens on Subscriptions, and has DeArrow
thumbnails and copy-URL buttons. SponsorBlock, Return YouTube Dislike, and ad
hiding are on as RVX defaults.

Vantage M is left out of the config on purpose. It's the extra Morphe variant;
install it by hand from the release assets if you want it.

## The four variants

| Variant | App | Package | Label | Patch source |
|---|---|---|---|---|
| Vantage | YouTube | `app.vantage.youtube` | Vantage | anddea dev, 23-patch curated (`--exclusive`) |
| Vantage Alt | YouTube | `app.vantage.youtube.alt` | Vantage Alt | anddea dev, same 23-patch set as Vantage |
| Vantage Music | YouTube Music | `app.vantage.youtube.music` | Vantage Music | anddea dev, default set |
| Vantage M | YouTube | `app.vantage.youtube.morphe` | Vantage M | Morphe official, default set |

Vantage Alt is the same build as Vantage, identical patch set and options, with a
different name, package, settings label, and icon (amber instead of cyan). The
separate package lets you run two copies of patched YouTube side by side, for
example with two accounts. Its config is `config/youtube-alt-options.json`.

Vantage M is a Morphe-based YouTube build with two gaps versus Vantage: no comment
hiding and no Return YouTube Username. It has its own package so it can sit
alongside Vantage.

Patches come from a [fork of anddea/revanced-patches](https://github.com/pmaxhogan/revanced-patches)
(dev channel) that bakes the setting defaults into the bundle itself, so a fresh
install is already configured with nothing to import in-app. A nightly workflow
keeps the fork current with anddea. Patching runs through
[morphe-cli](https://github.com/MorpheApp/morphe-cli), and the Vantage M variant
builds from the official [morphe-patches](https://github.com/MorpheApp/morphe-patches)
set. Target versions auto-resolve to the newest in the top compatibility tier,
currently YouTube 20.51.39 and YouTube Music 9.15.51.

## Enabled patches (Vantage / Vantage Alt)

These 23 patches are the curated set applied with `--exclusive`, so only they run.
Vantage and Vantage Alt use the exact same set. Vantage Music and Vantage M use
different sets and aren't listed here.

<details>
<summary>Ads and sponsors</summary>

| Patch | What it does |
|---|---|
| Hide ads | Removes video, feed, and Shorts ads plus promo shelves. |
| SponsorBlock | Skips sponsor and self-promo segments from the SponsorBlock database. |

</details>

<details>
<summary>Shorts</summary>

| Patch | What it does |
|---|---|
| Shorts components | Hides and reworks the Shorts UI. |
| Disable resuming Shorts on startup | Stops the app reopening a Short on launch. |
| Hide shortcuts | Removes the Shorts long-press launcher shortcut. |

</details>

<details>
<summary>Comments</summary>

| Patch | What it does |
|---|---|
| Hide comments components | Hides the comments section and its preview. |

</details>

<details>
<summary>Feeds and navigation</summary>

| Patch | What it does |
|---|---|
| Hide feed components | Strips feed clutter like breaking news, watch cards, and community posts. |
| Change start page | Opens on the Subscriptions tab. |
| Navigation bar components | Cleans up the bottom navigation bar. |

</details>

<details>
<summary>Player and controls</summary>

| Patch | What it does |
|---|---|
| Overlay buttons | Adds player buttons including download and copy video URL. |
| Swipe controls | Swipe gestures for brightness and volume. |
| Player components | Declutters the video player. |
| Video playback | Default quality and playback-speed controls. |

</details>

<details>
<summary>Restored functionality</summary>

| Patch | What it does |
|---|---|
| Return YouTube Dislike | Restores the dislike count via the RYD API. |
| Return YouTube Username | Shows original @handles instead of display names. |
| Remove background playback restrictions | Allows background and PiP playback for everything. |
| Alternative thumbnails | Swaps clickbait thumbnails for DeArrow or still-frame images. |
| Sanitize sharing links | Strips tracking params like `si=` from shared links. |
| Set transcript cookies | Fixes transcript and caption retrieval used by other features. |

</details>

<details>
<summary>Branding and setup</summary>

| Patch | What it does |
|---|---|
| Custom branding icon for YouTube | Applies the Vantage launcher icon. |
| Custom branding name for YouTube | Sets the app name to Vantage. |
| Settings for YouTube | Adds the in-app settings menu, labeled Vantage. |
| GmsCore support | Routes the app through MicroG-RE so it runs unrooted. |

</details>

There's also a golden-settings reset file (`vantage-youtube.json`,
`vantage-music.json`) attached to each release. A normal install doesn't need it,
since the defaults are baked in. It's there to restore the baseline if you've
changed settings and want to reset: in the app, avatar, Settings, Vantage,
Import, then pick the JSON.

## How the build works

`.github/workflows/build.yml` runs `scripts/build.sh`, which:

1. `resolve-versions.sh` finds the latest anddea fork release, the latest Morphe
   stable release, and the pinned morphe-cli jar. It reads the newest existing
   Release's `built-versions.json` manifest, and if neither patch version changed
   (and `--force` wasn't passed) it exits early. The latest Release is the state;
   there's no committed state file.
2. Decodes the signing keystore from the `VANTAGE_KEYSTORE_B64` secret to a
   runtime file, then downloads the morphe-cli jar and both `.mpp` bundles.
3. Resolves each variant's target app version with `morphe-cli list-versions`,
   taking the newest in the top patch-count tier unless pinned in
   `config/build.env`.
4. Runs the keystore pre-flight check (`assert.sh`).
5. For each variant, runs `download-apk.sh`, then `patch.sh`, then `assert.sh`.
6. Creates one Release with all four APKs, `built-versions.json`, the Obtainium
   config, and the golden settings files. The tag encodes the date and patch
   versions, for example `v2026.07.05-anddea4.2.0-dev.2-morphe1.33.0`.

Old releases stay put, so a rollback is just pointing Obtainium at an earlier tag.
Since the repo is public, GitHub disables the scheduled workflow after 60 days
with no commits (cron runs and releases don't reset that timer). See the
limitations below.

### CI guards

morphe-cli only warns on a renamed or removed patch, and it counts a
version-incompatible-but-inert patch as applied. So `assert.sh` checks the result
independently:

- every non-negotiable patch name must appear in `appliedPatches[]`
- `failedPatches` must be empty
- the exclusive YouTube set must be exactly 23 patches (name-check only for the
  Music and Morphe default sets, which grow over time)
- any `"not supported in this version"` in the log fails the build unless the
  patch is in that variant's inert allowlist
- the keystore hash (pre-flight) and signing-cert SHA-256 (post-build) must match
- aapt package name and label, an APK size floor, and zip integrity

The names, counts, and allowlists live in `config/assertions/`. Edit those, not
the script.

## GitHub secrets

| Secret | What | How to get it |
|---|---|---|
| `VANTAGE_KEYSTORE_B64` | `base64 -w0` of the signing keystore | `base64 -w0 vantage.keystore` |
| `VANTAGE_KEYSTORE_PASS` | keystore and entry password | chosen at `keytool -genkeypair` time |
| `VANTAGE_KEYSTORE_ALIAS` | key entry alias (defaults to `vantage`) | the `-alias` used at genkeypair |
| `VANTAGE_KEYSTORE_SHA256` | SHA-256 of the keystore (pre-flight guard) | `sha256sum vantage.keystore` |
| `VANTAGE_CERT_SHA256` | signing-cert SHA-256 (post-build guard) | `keytool -list -v ...`, or `apksigner verify --print-certs out.apk` |
| `GITHUB_TOKEN` | provided by Actions | built in, used for Releases and the stock cache |

Set these under Settings, then Secrets and variables, then Actions. The key exists
only in `VANTAGE_KEYSTORE_B64`, decoded at build time. If a guard secret is missing
the guard warns and skips, so CI should always have all of them. See
`keystore/README.md`.

## Stock-APK download

`download-apk.sh` looks for the stock APK in a `stock-cache` Release first, and on
a miss downloads it live from the runner. The mirrors block scripted clients on a
TLS fingerprint, so plain curl gets a 403. The resolvers use `curl_cffi`
impersonating Chrome, which gets through even from a GitHub datacenter IP; it
pulled a 170MB base APK from a runner in about eight seconds. There are two
sources so that one breaking isn't fatal:

- APKMirror (`scripts/apkmirror-dl.py`) picks the APK variant matching the arch
  rather than a bundle. It has the freshest builds and the best version coverage.
- APKPure's `.net` mirror (`scripts/apkpure-dl.py`) serves a version-pinned base
  APK, byte-identical to APKMirror.

Both go through the same signature verify gate, and a verified download is uploaded
back to `stock-cache`, so the cache maintains itself. `build.yml` installs
`curl_cffi` before building. `apkcombo` and `aptoide` remain as extra fallbacks
(see `config/build.env`).

Assets are named `<package>-<version>.apk`. You only need to seed the cache by hand
to bootstrap a package no source carries yet:

```bash
gh release create stock-cache -R <owner>/vantage --prerelease \
  --title "Stock APK cache" --notes "keyed by <package>-<version>.apk"
gh release upload stock-cache -R <owner>/vantage \
  com.google.android.youtube-<ver>.apk \
  com.google.android.apps.youtube.music-<ver>.apk
```

## Layout

```
.github/workflows/build.yml   cron + dispatch(force); Java 21; runs build.sh; one Release
scripts/
  lib.sh                      shared helpers (logging, SDK-tool finder, sha256, list reader)
  resolve-versions.sh         upstream versions + skip decision (state = latest Release)
  download-apk.sh             stock-cache-first, multi-source + Google-sig verify gate
  apkmirror-dl.py             APKMirror resolver (curl_cffi; picks the APK variant)
  apkpure-dl.py               APKPure resolver (curl_cffi; version-pinned base APK)
  patch.sh                    one morphe-cli patch pass (absolutizes icon folder paths)
  assert.sh                   keystore pre-flight + post-build guards
  build.sh                    orchestrator (also runnable locally)
config/
  youtube-options.json        anddea YouTube, 23 enabled
  music-options.json          anddea YouTube Music, default set + branding
  morphe-youtube-options.json Morphe YouTube, default set + Custom branding + package
  build.env                   pinned morphe-cli, channel selectors, packages, version pins
  assertions/*.txt            non-negotiable names, inert allowlists, expected count
  icon/                       custom icon sets per variant
  settings/                   golden RVX settings (optional reset files)
obtainium-config.json         one-tap Obtainium onboarding (MicroG-RE + 3 Vantage apps)
keystore/                     README only; the key lives in the VANTAGE_KEYSTORE_B64 secret
```

## Local build

```bash
# needs java 21+, gh (authenticated), jq, curl, python3 + curl_cffi; Android SDK for the guards
export VANTAGE_REPO=<owner>/vantage
export VANTAGE_KEYSTORE_FILE=/secure/vantage.keystore
export VANTAGE_KEYSTORE_PASS=...
export VANTAGE_KEYSTORE_ALIAS=vantage        # optional; defaults to vantage
export VANTAGE_KEYSTORE_SHA256=...            # optional locally; guard skips if unset
export VANTAGE_CERT_SHA256=...
bash scripts/build.sh --force                 # build + stage in build/release
```

## Known limitations

- Downloads depend on `curl_cffi`. If a mirror adds a full JavaScript challenge (a
  503 rather than a 403) curl_cffi won't get past it, and that source would need a
  headless-browser resolver instead. Having two sources covers one of them
  breaking.
- The setting defaults live in the fork's patch bundle, so changing one means
  editing the fork's `Settings.java` and rebuilding the `.mpp`, not this repo. The
  Music golden file is empty since its behaviors are already RVX defaults.
- The scheduled workflow auto-disables after 60 days without a commit. If upstream
  patches go quiet that long the cron stops; a weekly keepalive commit or a manual
  re-enable fixes it.
- Vantage M's Morphe monochrome and notification icon assets are validated through
  morphe-cli's resource compiler, not a live themed-icon render.
