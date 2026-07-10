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
install it by hand from the release assets if you want it. Vantage X (patched
Twitter/X) is also left out and ships as its own release - see below.

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

## Vantage X (Twitter/X, experimental)

Vantage X is a patched Twitter/X build from the [piko](https://github.com/crimera/piko)
patch set (the morphe patches for X). It is a separate, EXPERIMENTAL track from the
YouTube variants above, for three reasons, so it gets its own workflow
(`build-x.yml`) and its own GitHub **prerelease** rather than riding the YouTube
release:

- X ships no single universal APK. It is distributed as a split APKM bundle, which
  morphe patches directly (merging the splits, then patching). The download gate
  verifies every split's signing cert before patching.
- Patching X 11.88+ needs a second bundle, the [x-shim](https://gitlab.com/inotia00/x-shim)
  compatibility layer, stacked on top of piko. x-shim does not remove pairip (X's
  Play-integrity anti-tamper), so a re-signed sideloaded build can misbehave.
- Because pairip stays in and CI cannot log in to X on a phone, a green build is
  **not** proof the app launches or works - that is confirmed by hand. Vantage X was
  installed and exercised on a logged-in Pixel 6 (Android 16): it launches, the
  timeline loads, and the verified-user filter works as intended. It is still shipped
  outside the one-tap Obtainium config (like Vantage M), installed by hand from the
  assets. Each build publishes as a prerelease pending that on-device check; once
  confirmed it is promoted to a full release, as the current build has been.

| Variant | App | Package | Label | Patch source |
|---|---|---|---|---|
| Vantage X | Twitter/X | `com.twitter.android` | X | piko fork + x-shim (default set, `Browse tweet object` off, `Hide verified users` on) |

Its headline addition is **Hide verified users**: it hides every tweet and reply
whose author has a verified check - the blue X Premium badge (including a badge the
user has hidden in-UI, since the underlying `is_blue_verified` flag stays set), plus
gold/grey org and legacy verified. It also hides tweets that **reply to, retweet, or
quote-tweet** a verified account (so a reply to a blue-check is hidden even when the
replier is not), and it catches pinned tweets and "show more replies" pagination, not
just the main feed. Upstream piko has no such patch (it is an open, unimplemented
request there), so Vantage X builds from a small
[fork of piko](https://github.com/pmaxhogan/piko) that adds it. The patch filters the
raw JSON server response at the same hook piko's own "Log server response" uses,
before the app parses it, so it is independent of the app's per-version obfuscation
and covers the home timeline, profiles, conversations, and search alike. It fails
safe: if a response is not the shape it expects, it is passed through untouched. (The
reply-to-verified match needs the verified account present in the same response, so it
is reliable inside a tweet's reply thread and best-effort in the home feed.)

The filter was verified on-device against real X 12.2.0 responses (a captured sample
of the For You feed, a verified profile, and explore): it removed every
verified/retweet/quote/reply-to-verified timeline entry and kept every other one with
no false removals, and the running app visibly hides verified accounts. An earlier
build silently did nothing because current X had renamed its GraphQL timeline fields
(`tweet_results`/`user_results`/`itemContent` became `tweetResult`/`user_result`/
`content`); the on-device capture caught it, so the filter now matches the live schema
(and still accepts the old names) rather than an assumed one.

Vantage X also **defaults the home tab to Following** (the For You tab is removed via
piko's "Customize timeline top bar" with the `customisation_timeline_tabs` default set
to `hide_forYou`). It stays a setting, so For You can be restored to "Show both" in
piko settings.

The package stays `com.twitter.android`, so Vantage X replaces a stock X install
rather than sitting beside it (piko has no package-rename patch for X). Its config
is `config/x-options.json`, which enables piko's recommended default set plus the
three x-shim layers. Five piko patches are left off: `Browse tweet object` (a debug
share-menu entry, excluded by request) and four that are off upstream for good
reason (`Bring back twitter`, `Disunify xchat system`, `Dynamic color`,
`Export all activities`). Every X patch is listed explicitly in the options file,
so flipping any is a one-line change. The target version auto-resolves to the newest
non-`ripped` compatible build, currently X 12.2.0-release.0.

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

Vantage X builds separately. `.github/workflows/build-x.yml` runs
`scripts/build-x.sh` on its own daily schedule, so a flaky X build (single-source
APKM download, piko/x-shim churn, pairip) never blocks the YouTube nightly. It
resolves piko's latest release and the pinned x-shim bundle, skips early when
neither changed (state is the newest `x-v...` prerelease's `built-versions-x.json`),
downloads the split APKM through the same signature gate, patches with both bundles
stacked (`patch.sh` takes repeated `--patches`), asserts, and publishes a
**prerelease** tagged `x-v<date>-piko<v>-shim<v>`. The shared scripts (`lib.sh`,
`download-apk.sh`, `patch.sh`, `assert.sh`) are reused; only the orchestrator and
options differ.

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

Assets are named `<package>-<version>.<container>`, where the container is `apk`
for YouTube/Music and `apkm` for X (a split bundle). X is fetched only from
APKMirror, and its gate extracts every nested split and checks each one's signing
cert, so a mirror that re-signs the bundle (APKPure serves X under its own key) is
rejected. You only need to seed the cache by hand to bootstrap a package no source
carries yet:

```bash
gh release create stock-cache -R <owner>/vantage --prerelease \
  --title "Stock APK cache" --notes "keyed by <package>-<version>.<apk|apkm>"
gh release upload stock-cache -R <owner>/vantage \
  com.google.android.youtube-<ver>.apk \
  com.google.android.apps.youtube.music-<ver>.apk \
  com.twitter.android-<ver>.apkm
```

## Layout

```
.github/workflows/build.yml   cron + dispatch(force); Java 21; runs build.sh; one Release
.github/workflows/build-x.yml cron + dispatch(force); runs build-x.sh; X prerelease
scripts/
  lib.sh                      shared helpers (logging, keystore, SDK-tool finder, sha256, versions)
  resolve-versions.sh         upstream versions + skip decision (state = latest Release)
  download-apk.sh             stock-cache-first, multi-source + signature verify gate (apk & apkm)
  apkmirror-dl.py             APKMirror resolver (curl_cffi; picks the APK or BUNDLE variant)
  apkpure-dl.py               APKPure resolver (curl_cffi; version-pinned base APK)
  patch.sh                    one morphe-cli patch pass; repeatable --patches (X stacks two bundles)
  assert.sh                   keystore pre-flight + post-build guards (nonneg/forbidden/inert)
  build.sh                    YouTube-family orchestrator (also runnable locally)
  build-x.sh                  X (Twitter) orchestrator, isolated; its own prerelease
config/
  youtube-options.json        anddea YouTube, 23 enabled
  music-options.json          anddea YouTube Music, default set + branding
  morphe-youtube-options.json Morphe YouTube, default set + Custom branding + package
  x-options.json              piko X, recommended default set + x-shim; Browse tweet object off
  build.env                   pinned morphe-cli, channel selectors, packages, version pins, x-shim pin
  expected-signatures.txt     genuine vendor signing certs the stock download gate accepts
  assertions/*.txt            non-negotiable names, forbidden names, inert allowlists, expected count
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
- Vantage X keeps pairip (x-shim does not strip it) and cannot be exercised on a
  logged-in device in CI, so a green build only proves it patched and signed, not
  that it launches or works. Each build is published as a prerelease and hand-installed
  for a device check, then promoted to a full release once confirmed. It is also
  effectively single-source (APKMirror is the only mirror that
  serves the genuine APKM), and its pinned signing cert means an X signing-key
  rotation would fail the gate until `config/expected-signatures.txt` is updated.
