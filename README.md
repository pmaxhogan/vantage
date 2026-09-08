# Vantage

[![Build](https://github.com/pmaxhogan/vantage/actions/workflows/build.yml/badge.svg)](https://github.com/pmaxhogan/vantage/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/pmaxhogan/vantage?label=release)](https://github.com/pmaxhogan/vantage/releases/latest)

Vantage builds patched YouTube, YouTube Music, and Twitter/X APKs, signs them with
a stable key, and publishes them as GitHub Releases. [Obtainium](https://github.com/ImranR98/Obtainium)
installs them and keeps them updated. The YouTube variants need
[MicroG-RE](https://github.com/MorpheApp/MicroG-RE) on the phone, an unrooted
replacement for Google Play Services, and the bundled config installs it for you.
It also builds Claude clones - renamed, recolored copies of the Claude Android
app for several accounts signed in at once (see [Claude clones](#claude-clones)).

## Install

Each release ships an `obtainium-config.json` that sets up eight apps in one
import: MicroG-RE, the four Vantage apps (Vantage, Vantage Alt, Vantage Music,
Vantage X), and the three Claude clones (Claude 2, Claude 3, Claude 4), each
already configured with the right APK filter and update settings.

1. Install [Obtainium](https://github.com/ImranR98/Obtainium/releases).
2. Download `obtainium-config.json` from the
   [latest release](https://github.com/pmaxhogan/vantage/releases/latest).
3. In Obtainium, open the menu, choose Import/Export, then Import from file, and
   pick it. All eight apps appear.
4. Install MicroG-RE first, since the YouTube-family Vantage apps need it at
   runtime. Then install whichever Vantage apps you want. Vantage X needs no
   MicroG-RE, but it does replace a stock X install (see below). The Claude
   clones need no MicroG-RE either, and the first install of each is manual
   (see [Claude clones](#claude-clones)).

Obtainium auto-updates all eight as new releases land. The Vantage apps track the
release date and MicroG-RE tracks its version. The settings you'd otherwise have
to toggle by hand are baked into the patches, so a fresh install already hides
Shorts, comments, and community posts, opens on Subscriptions, and has DeArrow
thumbnails and copy-URL buttons. SponsorBlock, Return YouTube Dislike, and ad
hiding are on as RVX defaults.

Vantage M is left out of the config on purpose. It's the extra Morphe variant;
install it by hand from the release assets if you want it.

Vantage X is in the config, but it builds on its own cadence and publishes its own
`x-v...` release rather than riding the YouTube one - so the newest release in the
repo often carries no X APK. Obtainium's fallback-to-older-releases handles that
and finds the last X build; see [Vantage X](#vantage-x-twitterx) below.

## The four YouTube-family variants

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

## Vantage X (Twitter/X)

Vantage X is a patched Twitter/X build from the [piko](https://github.com/crimera/piko)
patch set (the morphe patches for X). It's a first-class variant, in the one-tap
Obtainium config alongside the YouTube apps, but it builds on a separate track from
them - its own workflow (`build-x.yml`) and its own GitHub release tagged `x-v...`
rather than riding the YouTube release - because X ships no single universal APK.
It is distributed as a split APKM bundle, which morphe patches directly (merging the
splits, then patching), and the download gate verifies every split's signing cert
before patching. Since X 12.5.0 piko patches the app on its own; the x-shim
compatibility layer that older X versions needed is no longer part of the build.

X keeps pairip (its Play-integrity anti-tamper) and CI cannot log in to X on a
phone, so a green build proves the APK patched and signed; the app itself is
checked by hand on a Pixel 6 (Android 16) after each meaningful change - it
launches, logs in, the timeline loads, and the verified-user filter and the daily
limit behave as described below. X releases are published with `--latest=false`,
so the repo's "latest release" slot stays on a YouTube build - that's the one
carrying `obtainium-config.json`, which the install link above points at.

| Variant | App | Package | Label | Patch source |
|---|---|---|---|---|
| Vantage X | Twitter/X | `com.twitter.android` | X | piko fork (default set + `Hide verified users` + `Daily time limit`) |

### Daily time limit

Vantage X enforces a **mandatory daily time limit**. It is always on, cannot be
disabled, and counts every second the app is in the foreground.

- **Default 30 minutes a day**, configurable from 1 minute up to the build's ceiling
  (see the four builds below), in hours and minutes.
- **The day resets at 5:00 AM** in the phone's time zone, not at midnight.
- **Lowering the limit applies immediately** (a limit below today's usage locks X on
  the spot). **Raising it starts tomorrow at 5:00 AM.** If you change it several
  times, the last value you saved is tomorrow's limit.
- Toasts warn once each at 15, 10, 5 and 1 minutes remaining (a threshold within
  5 minutes of the limit is skipped, and skipped warnings are never stacked).
- When the limit is up, every screen of the app bounces to a lock screen showing
  time used, the countdown to 5:00 AM, a **Change daily limit** button and a
  **Close X** button. Only the limit screen is reachable until the reset.
- The limit screen shows today's usage, a 7-day bar graph, the current limit, a
  short explanation, and hour/minute pickers with a prominent **Save limit** button;
  nothing applies until you save and confirm. It is reachable from X's settings list
  (the row above Piko), from the top of the Piko settings screen, from the lock
  screen, and from the app icon's long-press shortcut.
- **It survives force-close, the back button, deep links, share targets, shortcuts,
  reboot, clearing cache or storage, and reinstalling the app.** Time spent comes
  from Android's own usage statistics (kept by the system, not the app) merged with
  an in-app timer, and both the limit history and the daily counters are written as
  signed records to several places outside the app's data and merged back on read,
  so the strictest surviving copy always wins. Setting the clock forward or back
  does not reset the day either: within a boot the app trusts elapsed time, and the
  day never moves backwards. On first launch X asks for two one-time special
  permissions (Usage access and All files access) and does nothing until both are
  granted. A factory reset, root, or replacing Vantage X
  with a different build clears it - that is the intended ceiling.

Each X release carries **four APKs** that differ only in the highest limit a user can
set (a build-time option, hard-capped at 2 hours):

| APK | Max daily limit | Default limit |
|---|---|---|
| `vantage-x-<ver>-max2h.apk` | 2 hours | 30 minutes |
| `vantage-x-<ver>-max1h.apk` | 1 hour | 30 minutes |
| `vantage-x-<ver>-max30m.apk` | 30 minutes | 30 minutes |
| `vantage-x-<ver>-max15m.apk` | 15 minutes | 15 minutes |

`obtainium-config.json` tracks the `max2h` build; to run a stricter ceiling, install
that APK by hand (same package and key, so it installs over the current one) and
change the Obtainium APK filter to match it. The pure limit rules (5am day keys,
decrease-now / increase-tomorrow, warning de-duplication, record signing and
merging, clock-tamper handling) are covered by JUnit tests in the piko fork.

### Hide verified users

Vantage X's other addition is **Hide verified users**: it hides every tweet and reply
whose author has a verified check - the blue X Premium badge (including a badge the
user has hidden in-UI, since the underlying `is_blue_verified` flag stays set), plus
gold/grey org and legacy verified. It also hides tweets that **reply to, retweet, or
quote-tweet** a verified account (so a reply to a blue-check is hidden even when the
replier is not), and it catches pinned tweets and "show more replies" pagination, not
just the main feed. Upstream piko has no such patch (it is an open, unimplemented
request there), so Vantage X builds from a
[fork of piko](https://github.com/pmaxhogan/piko) that adds it. The patch filters the
raw JSON server response at the same hook piko's own "Log server response" uses,
before the app parses it, so it is independent of the app's per-version obfuscation
and covers the home timeline, profiles, conversations, and search alike. It fails
safe: if a response is not the shape it expects, it is passed through untouched, and
the JSON filter logic is unit-tested. (The reply-to-verified match needs the verified
account present in the same response, so it is reliable inside a tweet's reply thread
and best-effort in the home feed.)

The filter accepts both the current X GraphQL field names (`tweetResult`,
`user_result`, `content`) and the older ones (`tweet_results`, `user_results`,
`itemContent`), and it was re-checked on-device on X 12.19.1: a verified profile
with 108K posts renders an empty Posts tab. Vantage X also **defaults the home tab
to Following** (the For You tab is removed via piko's "Customize timeline top bar"
with the `customisation_timeline_tabs` default set to `hide_forYou`). It stays a
setting, so For You can be restored to "Show both" in piko settings.

### Build details

The package stays `com.twitter.android`, so Vantage X replaces a stock X install
rather than sitting beside it (piko has no package-rename patch for X). The fork
syncs with upstream piko nightly (a sync PR that auto-merges when clean and rebuilds
the `.mpp` on every push), and the X build floats to the fork's latest release and
to the newest X version those patches support, so base and patch versions keep up
without manual bumps - the same shape as the anddea fork the YouTube builds use.
piko's `Block update screen` is on, so an old base never shows X's "update your app"
nag even between bumps.

Its config is the four `config/x-options-max*.json` files, which enable piko's
recommended default set plus the two Vantage patches and differ only in
`maxLimitMinutes`. Four piko patches are left off because they are off upstream for
good reason (`Bring back twitter`, `Dynamic color`, `Export all activities`, and the
debug-only `Browse tweet object`). Every X patch is listed explicitly in the options
files, so flipping any is a one-line change. The target version auto-resolves to the
newest non-`ripped` compatible build, currently X 12.19.1-release.0.

## Claude clones

Claude clones are renamed, recolored copies of the stock Claude Android app for
several accounts signed in at once. Each clone gets its own package id, so it
installs next to the original Claude app and next to the other clones rather
than replacing anything. Each clone shows its number in a small pill pinned to
the top corner of every screen while you use it, and its launcher icon carries
the same number on a recolored background, so the copies are easy to tell apart.

| App | Package | Label | Badge |
|---|---|---|---|
| Claude 2 | `com.anthropic.claude.two` | Claude 2 | 2 |
| Claude 3 | `com.anthropic.claude.three` | Claude 3 | 3 |
| Claude 4 | `com.anthropic.claude.four` | Claude 4 | 4 |

Installing:

1. Download the clone's APK from the latest `claude-v...` release (see the
   table above for the file name pattern, `claude-<N>-<ver>.apk`) and install it
   like any sideloaded app.
2. If an earlier hand-built copy with the same name is already installed,
   uninstall it first - the signing key is different, so Android refuses to
   install over the mismatch.
3. After that first manual install, Obtainium tracks and updates the clone like
   any other app in the bundled config (see [Install](#install) above).
4. No MicroG-RE and no other setup is needed; the clone behaves exactly like a
   normal Claude install once it's on the device.

Like Vantage X, Claude clones build on their own cadence (their own workflow,
`build-claude.yml`) and publish their own release tagged `claude-v...` rather
than riding the YouTube release, since Claude ships new builds roughly daily -
far more often than the YouTube-family patches move. The build downloads
Claude's split bundle (base + arm64-v8a + language + density APKs, since the
app has no single universal APK) from apkcombo or Uptodown, verifies every
split's signing cert individually, merges them into one APK with
[APKEditor](https://github.com/REAndroid/APKEditor), then patches with the
`Clone with badge` patch from a separate bundle,
[vantage-patches](https://github.com/pmaxhogan/vantage-patches), which sets the
package name, label, badge number, and icon color per clone.

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
| Description components | Declutters the video description panel. |
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
| Custom branding for YouTube | Applies the Vantage launcher icon and app name. |
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
APKM download, piko churn) never blocks the YouTube nightly. It resolves the piko
fork's latest release, skips early when it is unchanged (state is the newest
`x-v...` release's `built-versions-x.json`), downloads the split APKM through the
same signature gate, patches it once per daily-limit ceiling (four options files),
asserts each APK, and publishes a release tagged `x-v<date>-piko<v>` (with
`--latest=false`, so the "latest release" slot stays on a YouTube build).
Conversely, the YouTube skip logic ignores `x-v*` tags when it looks for the last
build's manifest. The shared scripts (`lib.sh`, `download-apk.sh`, `patch.sh`,
`assert.sh`) are reused; only the orchestrator and options differ. The fork's own
`sync-upstream.yml` and `build-mpp.yml` keep its `.mpp` current with crimera/piko.

Claude clones build separately too. `.github/workflows/build-claude.yml` runs
`scripts/build-claude.sh` on its own daily schedule. Since Claude's package has
no version gate in the patch bundle, the target version is resolved from
whichever download source answers first (not `morphe-cli list-versions`, which
is built for a curated compatibility tier); the build skips early when both that
version and the vantage-patches bundle are unchanged (state is the newest
`claude-v...` release's `built-versions-claude.json`). It downloads Claude's
split bundle (`download-apk.sh`'s `bundle` container - see
[Stock-APK download](#stock-apk-download)), merges it with APKEditor, patches
once per clone with vantage-patches' `Clone with badge`, asserts each APK
(package, label, the original app's provider authority absent, patch result),
and publishes a release tagged `claude-v<ver>-vp<ver>` (with `--latest=false`,
same reason as X). `lib.sh`, `download-apk.sh`, and `assert.sh` are shared with
the other builds; `build-claude.sh` is its own orchestrator.

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
the script. Claude clones use a separate `assert.sh claude-clone` subcommand
(same failedPatches/cert/size/zip checks via `aapt2`, plus the check that
matters most there: the original app's provider authority - `com.anthropic.claude.provider` -
must be nowhere in the manifest, or the clone would collide with the original
app or another clone at install time instead of sitting beside them).

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
for YouTube/Music, `apkm` for X (a split bundle patched directly), and
`merged.apk` for Claude (a split bundle merged into one APK before caching - see
below). X is fetched only from APKMirror, and its gate extracts every nested
split and checks each one's signing cert, so a mirror that re-signs the bundle
(APKPure serves X under its own key) is rejected. You only need to seed the
cache by hand to bootstrap a package no source carries yet:

```bash
gh release create stock-cache -R <owner>/vantage --prerelease \
  --title "Stock APK cache" --notes "keyed by <package>-<version>.<apk|apkm>"
gh release upload stock-cache -R <owner>/vantage \
  com.google.android.youtube-<ver>.apk \
  com.google.android.apps.youtube.music-<ver>.apk \
  com.twitter.android-<ver>.apkm
```

Claude (`com.anthropic.claude`) ships no single universal APK either, but unlike
X, no mirror serves it as a genuine APKM - APKMirror bot-blocks this app's
pages entirely (not just the usual Cloudflare TLS check most other apps get),
so it isn't in Claude's source list at all. Instead `apkcombo` and `uptodown`
serve an XAPK/APKS zip of splits (base + arch + language + density), and
`download-apk.sh`'s `bundle` container (`verify_bundle()`) extracts just the
four splits the build needs (base + arm64-v8a + `en` + `xxhdpi`), verifies each
one's signing cert individually, and only then merges them into one APK with
[APKEditor](https://github.com/REAndroid/APKEditor) (`scripts/build-claude.sh`
downloads and sha256-pins the jar) - merging first would mean trusting content
nobody had checked yet. In practice `apkcombo` is the source that works: its
download page hands back a signed proxy link with no further gate. `uptodown`
(`scripts/uptodown-dl.py`) is wired up as a second source, but its real file
link is gated behind a live Cloudflare Turnstile challenge, which no amount of
TLS impersonation gets through - see the script's docstring. It's kept as a
fallback in case that ever changes, not because it works today.

## Layout

```
.github/workflows/build.yml        cron + dispatch(force); Java 21; runs build.sh; one Release
.github/workflows/build-x.yml      cron + dispatch(force); runs build-x.sh; X release (x-v*)
.github/workflows/build-claude.yml cron + dispatch(force); runs build-claude.sh; Claude release (claude-v*)
scripts/
  lib.sh                      shared helpers (logging, keystore, SDK-tool finder, sha256, versions)
  resolve-versions.sh         upstream versions + skip decision (state = latest Release)
  download-apk.sh             stock-cache-first, multi-source + signature verify gate (apk, apkm & bundle)
  apkmirror-dl.py             APKMirror resolver (curl_cffi; picks the APK or BUNDLE variant)
  apkpure-dl.py               APKPure resolver (curl_cffi; version-pinned base APK)
  uptodown-dl.py              Uptodown resolver (curl_cffi; Claude fallback, Turnstile-gated in practice)
  patch.sh                    one morphe-cli patch pass; repeatable --patches (X stacks two bundles)
  assert.sh                   keystore pre-flight + post-build guards (nonneg/forbidden/inert/claude-clone)
  build.sh                    YouTube-family orchestrator (also runnable locally)
  build-x.sh                  X (Twitter) orchestrator, isolated; its own x-v* release
  build-claude.sh             Claude clones orchestrator, isolated; its own claude-v* release
  gen-obtainium-config.py     regenerates obtainium-config.json (edit here, not the JSON)
config/
  youtube-options.json        anddea YouTube, 23 enabled
  music-options.json          anddea YouTube Music, default set + branding
  morphe-youtube-options.json Morphe YouTube, default set + Custom branding + package
  x-options-max*.json         piko X, four files differing only in the daily-limit ceiling
  build.env                   pinned morphe-cli/APKEditor, channel selectors, packages, version pins, Claude clone config
  expected-signatures.txt     genuine vendor signing certs the stock download gate accepts
  assertions/*.txt            non-negotiable names, forbidden names, inert allowlists, expected count
  icon/                       custom icon sets per variant
  settings/                   golden RVX settings (optional reset files)
obtainium-config.json         one-tap Obtainium onboarding (MicroG-RE + 4 Vantage apps + 3 Claude clones)
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
- Vantage X keeps pairip (piko does not strip it) and cannot be exercised on a
  logged-in device in CI, so a green build only proves it patched and signed, not
  that it launches or works; that is checked by hand on a Pixel 6 after meaningful
  changes. It is also
  effectively single-source: APKMirror is the only mirror that serves the genuine
  APKM (APKPure re-signs it), so an APKMirror outage stops X builds even though the
  YouTube variants have a fallback. Its pinned signing cert also means an X
  signing-key rotation fails the gate until `config/expected-signatures.txt` is
  updated.
- Claude clones are effectively single-source too, in practice: `apkcombo` is
  the source that works today, and `uptodown` is a real fallback in code but
  currently fails every time because Uptodown gates its actual file link behind
  a live Cloudflare Turnstile challenge that no TLS-impersonation trick gets
  past (see [Stock-APK download](#stock-apk-download)). An apkcombo layout
  change or outage stops Claude builds until a working third source is added.
  Its pinned signing cert has the same rotation caveat as X's.
