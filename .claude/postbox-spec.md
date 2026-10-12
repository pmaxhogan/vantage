# Postbox - locked spec (ultraquest handoff, 2026-10-11)

Postbox is a patched Instagram for Android for people who do not want to be on
social media but still want to talk to their friends: DMs, stories, the things
people send you, links people share. No feed, no Reels tab, no Explore or
search, no post grids, no infinite scrolling, and no way around any of that via
launcher shortcuts, deep links, startup intents, or settings toggles. It is
built and released from `pmaxhogan/vantage` the way Vantage X is, with its
patches living in the `pmaxhogan/piko` fork the way the X "Daily time limit"
patch does, and it is distributed through Obtainium.

This file is the complete, self-contained spec. It was produced by a finished
`/ub:ultraquest` interview with Max on 2026-10-11. **Every decision under
"Locked decisions" is final. Do NOT re-ask any of them.** Anything not covered
is the executing session's call: pick the option most consistent with the
locked decisions, prefer the reversible one, and record it in the final report
under "judgment calls made without asking".

Paths below are on Max's MacBook Pro: `~/code/vantage`, `~/code/piko`,
`~/code/vantage-patches`. Line numbers are from 2026-10-11 and may drift.

---

## 1. The quest, restated

Produce a release pipeline and patch set such that:

- A user imports `obtainium-config.json` from a Vantage release, installs
  Postbox (package `app.vantage.postbox`, label "Postbox"), logs in, and gets
  exactly these surfaces: login/logout/2FA/settings and the other
  account-management pages; the Home tab reduced to the stories tray (own
  story "+" included) over an empty feed; the Messages tab in full (inbox,
  group chats, replies, reels and posts people send, opened as single items);
  the Profile tab (own profile incl. grid, followers, following); other
  people's profiles with header, bio, highlights, follower and following lists
  but no posts/reels grid; posting stories (and posts, through the Home-header
  "+"); the heart/notifications header button; opening a post or reel from a
  link sent in another app, as a single item with nothing scrollable beneath
  it.
- A user cannot reach: the home feed/timeline, the Reels tab or any reel-to-
  reel paging, Explore or the Search tab, any post/reel grid on other
  profiles, "more posts" chaining below a post, or suggested-content units.
- None of the above can be bypassed via launcher long-press shortcuts, deep
  links (`instagram://` or `https://instagram.com/...`), the startup-tab intent
  extra, notification taps, or any settings toggle in the app.
- Every push to `vantage` main that touches Postbox build files cuts a release
  (no nightly cron), a new patch bundle from the piko fork also cuts a release
  via `repository_dispatch`, Obtainium picks each release up, and Dependabot
  keeps all three repos current with minor/patch auto-merge.

"Done" is observable: the flows in section 7 pass on the Pixel 6 with
screenshot evidence, the release exists on GitHub with the APK, manifest and
regenerated `obtainium-config.json`, Obtainium installs it from that config,
and the dependabot workflows have run green at least once on a real bot PR.

---

## 2. Locked decisions (DO NOT RE-ASK)

### Scope and product

| # | Decision | Value | Why |
|---|---|---|---|
| D1 | Base | piko fork (`pmaxhogan/piko`) is the patch base; the new Postbox lock-down patches are written INSIDE the fork, like the X "Daily time limit" patch. | piko already ships 62 Instagram patches incl. nav bar, Disable explore, Disable Reels scrolling, Hide suggested content, Clone, signature bypass, settings framework. Fork-local patches can force piko's own prefs. `build-mpp.yml` and `sync-upstream.yml` already exist. |
| D2 | Name / package | Label **Postbox**, package **`app.vantage.postbox`**, via piko's `Clone` patch options (`packageName`, `appName`). Installs alongside stock Instagram. | Max picked the name. Clone keeps stock usable on the same device. |
| D3 | Instagram version | **Pinned to piko's supported version** (today `447.0.0.55.81`, arm64, APKM). Bumps follow the fork's upstream sync. | Fingerprints are known-good before a build. FeurStagram floats and rebuilds by hand; we do not. |
| D4 | Stories | **Home tab stays, reduced to the stories tray**: `/feed/timeline/` is blocked at the network layer so the feed is empty; the tray and the own-story "+" remain. | The tray lives on Home; FeurStagram proves the shape. |
| D5 | Bottom bar | **Home, Messages, Profile.** Reels and Search tabs removed. (On this build Create and Notifications are Home-header buttons, not tabs - see Max's screenshot note in section 4.) | Max confirmed from a live screenshot. |
| D6 | Home header buttons | **Keep both**: the "+" create button and the heart (notifications). "Suggested for you" rows inside the activity feed are hidden (piko `ActivityFeedSuggestedProfiles` hook). The "Instagram v" feed-switcher dropdown is hidden. | Max: keep both. Dropdown is meaningless with no feed (inferred, confirmed). |
| D7 | Below a post opened from a link/DM | **Nothing: post, caption, comments only.** Block `/discover/chaining/` and related endpoints and drop netego/ad/suggested units at the parser; if the pager still pages it pages into empty space. Structural pager disable is NOT required for V1. | Max chose the network+parser approach over a pager fingerprint. |
| D8 | Profiles | Other people's profiles show **header, bio, highlights, follower/following lists**; the posts/reels **grid area is hidden**. **Own profile keeps its grid.** | Max's pick. |
| D9 | DM extras | **Keep as is**: Notes bubbles row, Instants "+", no inbox lock. | Max: "Keep as is". |
| D10 | Comments / posting posts | Comments stay stock (viewable, postable). Posting normal posts stays possible through the Home-header "+". | Max said "whatever's easiest"; stock = zero patches. |
| D11 | piko extras | **Exclude** piko's download, ghost-mode/anonymous-viewing and ad-block patches. Only the structural/blocking patches plus Clone, settings and the piko fixes they depend on. | Keeps the suspension profile close to FeurStagram's (no confirmed bans) rather than piko's (several threads, correlated with download/ghost features). |
| D12 | Blocked-surface UX | **Bounce to the inbox** (Messages tab) whenever a forbidden surface is reached anyway. | Max's pick over blank page or interstitial. |

### Lock-down (all four confirmed, all mandatory)

| # | Surface | Required behavior |
|---|---|---|
| L1 | Launcher shortcuts | Static `shortcuts.xml` stripped at patch time (resource patch: remove the `android.app.shortcuts` `<meta-data>` on the launcher activity and/or the xml file). Dynamic shortcuts cleared on every launch and re-checked at most once a minute from `onActivityResumed` (Meta apps re-publish their own; `ShortcutManager` rate-limits background calls). Pinned shortcuts cannot be removed programmatically; `disableShortcuts()` them with a reason string. |
| L2 | Deep links | `instagram://` and `https://(www.)instagram.com/...` links to `/explore`, `/reels`, `/reel/<id>` chaining targets other than the single reel, `/` (home), `/direct/inbox` is allowed, hashtags `/explore/tags/`, locations `/explore/locations/`, search, and the Reels/Search tab targets are **redirected to the inbox**. Links to a post (`/p/<code>`), a reel (`/reel/<code>`, `/reels/<code>`), a profile (`/<user>`), a story (`/stories/<user>/<id>`) and a DM thread **open as single items**. piko's `ValidateLinksPatch` + `Links.signatureCheck` already makes the re-signed APK pass Instagram's in-app "signed by Meta" deep-link gate; keep it. |
| L3 | Startup tab + notification taps | Hook piko's startup seam (`preflightStartup` / `applyStartupTab`, `NavigationBarPatch.java:295-325`) so no intent can land on Home-as-feed, Reels or Search: the `MainActivityAccountHelper.STARTUP_TAB` extra is overwritten when it names a forbidden tab. Cold start lands on **Messages** (judgment call: the inbox is the product's center and the bounce target). Notification taps into a reel/post open only that single item. |
| L4 | Settings toggles | The blocking prefs are **hardcoded at build**: the Postbox patch rewrites the relevant `Pref.*()` getters in the piko extension to constant returns (same technique as `DailyTimeLimitPatch.kt:160-170` rewriting `BuildValues` getters) and removes or hides the corresponding rows from piko's settings screens. NOT Focus Lock (its 24h cool-off is a bypass). piko's settings page may remain for harmless prefs (theme, font). |

### Pipeline and repo

| # | Decision | Value |
|---|---|---|
| P1 | Release trigger | `build-postbox.yml` in `vantage`: `on: push: branches: [main]` with `paths:` filtered to Postbox build files (the workflow itself, `scripts/build-postbox.sh`, `scripts/lib.sh`, `scripts/patch.sh`, `scripts/download-apk.sh`, `scripts/*-dl.py`, `scripts/assert.sh`, `scripts/gen-obtainium-config.py`, `config/build.env`, `config/expected-signatures.txt`, `config/postbox-options.json`, `config/assertions/postbox-*`), plus `repository_dispatch` (event type `piko-release`) fired by the piko fork's `build-mpp.yml` after it publishes, plus `workflow_dispatch` with a `force` input. **No cron.** |
| P2 | Dependabot merges and releases | A Dependabot merge on `vantage` main releases **only if it touches the path-filtered Postbox files** (follows from P1). |
| P3 | Dependabot scope | `vantage`: github-actions + pip, weekly. `piko` fork: github-actions + gradle, weekly, targeting `main` (upstream's file targets `dev` monthly; the fork overrides it - keep the override out of the files that `sync-upstream` would conflict on if possible, or accept that `.github/dependabot.yml` is a fork-owned file). `vantage-patches`: github-actions + gradle, weekly. |
| P4 | Auto-merge policy | **Minor/patch auto-merge, majors held with a comment**, on all three repos. All three are public, so use the native shape (`~/code/tapshim/.github/workflows/dependabot-auto-merge.yml`: `pull_request` trigger, `dependabot/fetch-metadata@v2`, `gh pr merge --auto --squash`, comment on majors). Requires `allow_auto_merge` on the repo (vantage already true; enable on piko and vantage-patches) and a ruleset/branch protection on `main` requiring the CI check so `--auto` has something to wait on. |
| P5 | Signing | The shared Vantage keystore (`VANTAGE_KEYSTORE_B64/_PASS/_ALIAS/_SHA256`, `VANTAGE_CERT_SHA256` secrets). No new keystore. |
| P6 | Icon and label | Instagram's adaptive icon **recolored** (reuse the vantage-patches Claude "Clone with badge" icon-rewrite technique, or a resource patch in the fork) so it is distinguishable from stock; label "Postbox". Custom art may replace it later. |
| P7 | Obtainium | New entry in `scripts/gen-obtainium-config.py`: id `app.vantage.postbox`, name "Postbox", `apkFilterRegEx` `postbox-.*\.apk`, same `vantage_addl` shape (date-as-version, fallback to older releases). Release assets: `postbox-<igver>.apk`, `built-versions-postbox.json`, `obtainium-config.json`. Tag `postbox-v<date>-piko<ver>`, `--latest=false`. |
| P8 | Docs | Vantage README section (install, the manual "Open supported links" step, what is blocked and why); piko fork README listing the Vantage-only Instagram patches next to the X entries; CLAUDE.md notes in both repos for future agents (fingerprint gotchas, how to re-pin an Instagram version, how the dispatch chain fires). |

### Process

| # | Decision | Value |
|---|---|---|
| X1 | Test account | **Max's real account; Max logs in himself on the Pixel 6.** The implementer installs builds over adb and drives screens; it never types or stores the password. Ask Max (PushNotification) to log in once the first installable build is on the device. Evidence gathered 2026-10-11: piko has ~4 suspension threads since 2025 (anecdotal, correlated with download/ghost-mode use, one note that Instagram calls Play Integrity every ~10 min); FeurStagram's maintainer reports no confirmed ban across ~1k stars. Risk is low and nonzero; Max accepted it. |
| X2 | Verification depth | **Install on Pixel 6, drive every required and forbidden flow, screenshot evidence** (section 7). |
| X3 | Fallback | If the post-chaining or profile-grid hook proves fragile on this build, **ship the degraded fallback and flag it** (network+parser blocking leaving an empty pager; grid hidden by view id if the fragment hook fails). V1 is not held for one fingerprint. |
| X4 | Priority when short on time | **Pipeline first** (build, release, Obtainium with piko's existing patches), **then lock-down surfaces hardest-to-bypass first** (shortcuts, deep links, startup tab, nav bar), then grid and post chaining, dependabot last. |
| X5 | Pre-grants (explicit, from the interview) | Change repo settings on the piko fork and vantage-patches (enable auto-merge, add required-check rulesets, repo variables). Download the Instagram APKM from APKMirror via the existing curl_cffi scripts and add Instagram's signing cert to `config/expected-signatures.txt`. Add Postbox secrets/vars to vantage Actions if a new one is needed (e.g. a dispatch PAT). Install Postbox over stock Instagram on the Pixel 6 if the clone conflicts (stock is not installed there today). Standing grants still apply: adb install/uninstall/clear-data on the Pixel 6, pushing the piko fork and cutting fork releases, creating/editing vantage releases, dispatching workflows, running the repos' builds. |
| X6 | Not granted | Outbound messages of any kind (Discord, email) still go through `~/bin/ask-max-for-approval`. Nothing that bills. |
| X7 | Deploy path | Personal repos: **direct commits to main**, no PRs, no Codex, no tech request. |
| X8 | Comms | PushNotification at each major milestone (first installable build, lock-down complete, first release live, dependabot green), at done, and on any blocker. No Discord. |
| X9 | Model delegation | Orchestrator: **opus, high effort**. Subagents: sonnet for YAML, shell, options JSON, README, docs; opus (high) for the Kotlin patches, the Java extension code, fingerprint work, and the deep-link/shortcut/startup routing. The orchestrator reviews every patch diff itself before it is pushed. Never Fable in a fan-out. |

---

## 3. Architecture

```
pmaxhogan/piko (fork)                       pmaxhogan/vantage
  patches/.../instagram/...  (upstream)       .github/workflows/build-postbox.yml
  patches/.../instagram/postbox/*.kt  NEW ->  scripts/build-postbox.sh        NEW
  extensions/instagram/.../postbox/*.java NEW config/postbox-options.json      NEW
  .github/workflows/build-mpp.yml             config/assertions/postbox-*.txt  NEW
     + repository_dispatch to vantage  NEW    config/build.env (+IG_* vars)
  .github/dependabot.yml (fork-owned)         config/expected-signatures.txt (+IG cert)
  .github/workflows/dependabot-auto-merge.yml scripts/gen-obtainium-config.py (+entry)
                                              README.md, .claude/CLAUDE.md
pmaxhogan/vantage-patches: dependabot.yml + auto-merge workflow only.
```

Build flow (mirror of `scripts/build-x.sh`): resolve the fork's latest
non-prerelease `.mpp` from `releases/latest` -> skip if the last
`postbox-v*` release's manifest already has this piko version (unless forced or
dispatched by a vantage push) -> `setup_morphe_cli` -> pin the Instagram
version (`IG_VERSION_PIN` in `build.env`, or `resolve_target_version` which
reads `list-versions` from the bundle) -> keystore preflight -> download the
APKM through `download-apk.sh <pkg> <ver> arm64-v8a <out> apkm` (APKMirror only,
like X) -> `patch.sh --options config/postbox-options.json` -> `assert.sh
variant` with Postbox nonnegotiable/forbidden lists -> manifest -> release.

The patch selection is entirely in `config/postbox-options.json` (per-patch
`enabled` + `options`, see `config/x-options-max2h.json` for the shape; the
"Daily time limit" entry shows how options are passed). Postbox enables:
piko `Add settings` (dependency root), `Clone` (`packageName`
`app.vantage.postbox`, `appName` `Postbox`), `Customize navigation bar`,
`Disable explore`, `Disable Reels scrolling`, `Hide suggested content`,
`Disable discover people`, `Disable swipe to create`, `Sanitize share links`,
`Change version code` (turns off store updates for the clone) and the new
Postbox patches. It disables every piko patch not needed (downloads, ghost
mode, ad block, theme, font, etc. - D11). Because morphe-cli offers every patch
in the bundle to every build, the options file must list the X patches as
`enabled: false` too, or `--exclusive` must be used with explicit `-e` names
(patch.sh supports `--exclusive`; prefer it so a future default-on upstream
patch cannot sneak in).

---

## 4. Research findings the implementer should not re-derive

### 4.1 Toolchain
- Everything is **Morphe** (ReVanced fork): morphe-cli (`MorpheApp/morphe-cli`,
  floats to latest stable with last-good fallback, `vantage/scripts/lib.sh:151-188`),
  `.mpp` bundles, Gradle plugin `app.morphe.patches` 1.3.3 and
  `app.morphe:morphe-patches-library` (piko `gradle/libs.versions.toml`).
  Registry is GitHub Packages (`maven.pkg.github.com/MorpheApp/registry`) and
  needs `GITHUB_ACTOR` + `GITHUB_TOKEN` (`read:packages`) to build. Local JDK:
  Temurin 21 at `/Library/Java/JavaVirtualMachines/temurin-21.jdk`; the fork's
  `build-mpp.yml` uses Java 17. Android SDK at `~/Library/Android/sdk`
  (`apksigner` is under `build-tools/*/`, not on PATH). `adb` at
  `/opt/homebrew/bin/adb`; the Pixel 6 (`24021FDF6001U4`) is connected and
  authorized. Stock Instagram is NOT installed on it; Vantage X and the
  Vantage YouTube apps are.
- Local tools already cached: `vantage/build/tools/morphe-cli-1.18.1-all.jar`,
  `APKEditor-1.4.9.jar`, `piko-3.9.0.mpp`.
- Patch DSL (piko, Morphe): `bytecodePatch(name, description, default) {
  compatibleWith(COMPATIBILITY_INSTAGRAM); dependsOn(...); execute { ... } }`,
  `resourcePatch { execute { document("AndroidManifest.xml").use { } } }`,
  fingerprints as `object X : Fingerprint(definingClass=, name=, returnType=,
  parameters=, strings=, accessFlags=, filters=OpcodesFilter..., custom={ m, c -> })`,
  edits via `method.addInstructions(index, smali)`, `addInstructionsWithLabels`,
  `replaceInstruction`, `findFreeRegister`, `getReference<MethodReference>()`.
  Options: `stringOption`, `intOption`, `booleanOption` (intOption for bare
  digits - morphe-cli parses them as numbers).
- piko Instagram extension namespace: `app.morphe.extension.instagram.*`
  (`extensions/instagram/src/main/java/app/morphe/extension/instagram/`).
  Patches namespace: `app.crimera.patches.instagram.*`. Constants:
  `patches/src/main/kotlin/app/crimera/patches/instagram/utils/Constants.kt`
  (`COMPATIBILITY_INSTAGRAM`, `ApkFileType.APKM`, version `447.0.0.55.81`,
  versionCode `385311895` for ARM64_V8A; `PATCHES_DESCRIPTOR`, `USER_SESSION_CLASS`,
  `USER_DETAIL_VIEW_MODEL_CLASS = Lcom/instagram/profile/fragment/UserDetailViewModel;`).
- Fork-only patch precedent for X: `patches/.../twitter/misc/timelimit/DailyTimeLimitPatch.kt`
  (resource patch adds manifest activities L48-94; bytecode patch hooks
  `Application.onCreate` after `invoke-super` L128-137; **rewrites extension
  `BuildValues` const getters to bake options in** L160-170) and
  `extensions/twitter/.../timelimit/TimeLimit.java` (`ActivityLifecycleCallbacks`
  bouncing EVERY activity incl. deep links/shortcuts/notification taps L24-33;
  dynamic-shortcut publish with 60s re-check from `onActivityResumed` L111-147).

### 4.2 piko Instagram pieces to reuse (paths under `~/code/piko`)
- **Navigation bar**: `patches/.../instagram/misc/navigation/NavigationBarPatch.kt`
  + `extensions/.../patches/navigation/NavigationBarPatch.java`. Tabs enum
  HOME/REELS/MESSAGES/SEARCH/PROFILE/NOTIFICATIONS/CREATE (`Tab`, L30-40 of the
  Java). Config string `v2|home:1,reels:0,messages:1,search:0,profile:1,create:0,notifications:0|messages`
  (`encodeConfig` L365-374; order list then `|` startup key). Stored via
  `Pref.navigationTabs()` / `Settings.NAVIGATION_TABS`; there are also
  `HIDE_NAVIGATION_FEED/REELS/DIRECT/SEARCH/CREATE` booleans
  (`settings/Settings.java:101-106`). `transformNavigationTabs(current, all)`
  is the tab-list hook; `preflightStartup(Intent, boolean)` and
  `applyStartupTab(Intent, boolean, List)` (L295-325) are the startup seam:
  they only act when `coldDefaultPath` is true and the intent has no
  `MainActivityAccountHelper.STARTUP_TAB` extra. **Postbox must also act when
  the extra IS present** (overwrite a forbidden value) - that is the gap L3
  closes. `startupChoices` L376-384 prefers `config.startup()` then HOME.
- **Explore**: `links/distractionFree/DisableExplorePatch.kt` just calls
  `enableSettings("disableExplore")`; the blocking is in
  `extensions/.../patches/Links.java` `interceptUri(URI)` (blocks
  `/discover/topical_explore*`, `/fbsearch/recent_searches/`, `/fbsearch/top_serp/`
  when `DISABLE_EXPLORE || FocusLock.isForced(...)`). `interceptUriPatch`
  (`links/InterceptUriPatch.kt`) hooks `TigonServiceLayer.startRequest`
  (unobfuscated, stable) and is the one network choke point: Postbox adds its
  own path list there (D4, D7) - see 4.4.
- **Reels paging**: `misc/reels/DisableReelsScrollingPatch.kt` disables
  `ViewPager2.setUserInputEnabled(false)` on the clips pager (fingerprint string
  `ClipsViewPagerImpl_getViewAtIndex`) and kills pull-to-refresh on
  `instagram/features/clips/viewer/ui/ClipsSwipeRefreshLayout`. Gated on
  `Pref.disableReelsScrolling()`.
- **Suggested units at the parser**: `ads/HideSuggestedContentPatch.kt` hooks
  `unsafeParseFromJson` (strings `clips_netego`, `stories_netego`,
  `bloks_netego`, `suggested_*`) and routes the type key through
  `Constants.JSONPARSER_CHECK_DESCRIPTOR`. Activity-feed suggestions:
  `links/misc/ActivityFeedSuggestedProfiles.kt` (`hideActivityFeedSuggestions`).
- **Settings forcing**: `extensions/.../utils/Pref.java` has one static getter
  per setting (`disableExplore()` L144, `disableReelsScrolling()` L168,
  `hideSuggestedContent()` L58, `disableDiscoverPeople()`, `disableSwipeToCreate()`
  L172, `hideNavigationFeed/Reels/Direct/Search/Create()` L341-367,
  `navigationTabs()` L377, `limitFollowingFeed()` L156). `SettingsStatus`
  (`settings/SettingsStatus.java`) flags which patches are present;
  `enableSettings("x")` in `utils/Utils.kt:17` adds a call to
  `SettingsStatus.x()` at load. `Links.java` caches `DISABLE_EXPLORE =
  Pref.disableExplore() && SettingsStatus.disableExplore` in a static
  initializer, so rewriting `Pref.disableExplore()` to `const/4 v0,1; return v0`
  is sufficient and survives any UI toggle.
- **Clone**: `misc/clone/ClonePatch.kt` (options `packageName`, `appName`;
  rewrites manifest package, custom permissions, provider authorities, and
  string constants in bytecode). Do NOT also enable Morphe's universal
  "Change package name".
- **Signature / deep-link gate**: `links/validateLinks/ValidateLinksPatch.kt` +
  `Links.signatureCheck(Object)` - already part of `settingsPatch`'s dependsOn.
  FeurStagram independently documents the failure mode it fixes: a re-signed
  APK fails Meta's key-hash allowlist and the deep-link dispatcher silently
  drops to the home feed (`jean-voila/FeurStagram` issue #36;
  `patches/.../signature/SignatureCheckBypassPatch.kt` matches the class by the
  string "Invalid SHA256 key hash"). If piko's gate ever stops covering a link
  type, port that patch.
- **Settings UI**: `misc/settings/SettingsPatch.kt` ("Add settings",
  `default = true`) depends on `mainFeedActionBarButtonPatch` and
  `hideHomeActionButtonsPatch` (`misc/actionBar/mainFeedActionBarButton/`).
  Verify on the first build that these do not remove the Home-header "+" or
  heart (D6); if they do, the Postbox options must keep those visible.
- **Home feed empty**: piko has `Limit feed to following profiles`
  (`misc/distractionFree/LimitFeedToFollowingProfiles.kt`) - NOT used (D4 is
  "empty", not "following"). FeurStagram's `/feed/timeline/` network block is
  the model; its `Block.java` list of suggested/ads endpoints is a good
  starting list for D7.

### 4.3 FeurStagram cross-reference (GPLv3, `jean-voila/FeurStagram`, Morphe)
Same patcher family, so its Kotlin reads 1:1. Worth copying ideas from:
`Block.java` (network path lists: `/feed/timeline/`, `/discover/topical_explore`,
`/clips/home/`, `/clips/discover`, `/clips/get_blend_medias/`,
`/discover/chaining/`, `/discover/ayml/`, `/discover/sectioned_ayml/`, the
ads list), `FeedItemFilterPatch.kt` (rewrite a blocked unit's type token to an
invalid one so the parser drops it: no throw, no crash),
`Hiders.java` (view-id based hiding via `OnGlobalLayoutListener` with
`resources.getIdentifier(name, "id", pkg)`: ids `feed_tab`, `search_tab`,
`clips_tab`, `creation_tab`, `direct_tab`, `profile_tab`, `tab_bar`,
`swipeable_tab_view_pager`, `cf_hub_recycler_view` (notes),
`creation_entrypoint`, `action_bar_buttons_container_right`),
`HiddenTabSwipeSkipper.java` (horizontal swipe landing on a hidden tab skips
to the next visible one), `SettingsEntryPointPatch.kt` (fingerprint for the
tab-bar binder: `<init>(View)` on an `LX/` class storing a ViewGroup and a
View field). Its `Readme.md` and `docs/INSTALL.md` are the model for the
"Open supported links" install step. Attribution: keep NOTICE lines if any
code is copied (GPLv3 §7 terms in both piko and FeurStagram).

### 4.4 What is genuinely new (no prior art in piko or FeurStagram)
1. **Shortcut kill** (L1): a resource patch that strips the static shortcuts
   meta-data from the manifest, plus an extension `ActivityLifecycleCallbacks`
   that calls `ShortcutManager.removeAllDynamicShortcuts()` and
   `disableShortcuts(pinnedIds, "Not available in Postbox")` from
   `onActivityResumed`, re-checked every 60s (`TimeLimit.java` pattern). Verify
   on the real APK what Instagram ships (`aapt dump xmltree` the manifest for
   `android.app.shortcuts`, and `adb shell dumpsys shortcut` after a launch).
2. **Deep-link router** (L2): the cleanest seam is an `ActivityLifecycleCallbacks`
   `onActivityPreCreated` that inspects `activity.getIntent().getData()` for
   every activity (covers VIEW intents from other apps, notification taps and
   shortcuts in one place), classifies the URL by path (allow: `/p/`, `/reel/`,
   `/reels/<code>`, `/stories/`, `/direct/`, `/<username>` profile; deny:
   `/explore*`, `/reels` bare, `/` bare, hashtag/location/search/`/accounts/`
   discovery pages, `instagram://` schemes naming feed/reels/explore/search),
   and on deny rewrites the intent to the inbox (set the STARTUP_TAB extra to
   the DIRECT enum name - get it from `NavigationBarPatch.Tab.MESSAGES` enum
   names "DIRECT" - clear the data URI, and `activity.setIntent(...)` before
   super.onCreate) or finishes the activity and starts `MainActivity` with the
   inbox extra. A second layer: the Tigon network block for the surfaces
   themselves, so even a route that escapes the router renders empty.
3. **Startup-tab override** (L3): extend piko's `applyStartupTab` path (or a
   Postbox hook placed in the same `installStartup` seam,
   `NavigationBarPatch.kt` `installStartup`) so a present `STARTUP_TAB` extra
   naming FEED/CLIPS/SEARCH is replaced by DIRECT.
4. **Profile grid hide** (D8): hook the profile fragment. Anchors:
   `USER_DETAIL_VIEW_MODEL_CLASS`, `entity/profileinfo/Fingerprint.kt`
   (`ProfileUserInfoViewBinderFingerprint`, `IsSelfProfileExtensionFingerprint`
   gives self-vs-other), `misc/userProfile/*`. Fallback (X3): hide by view id
   via a global-layout hider on the profile tab host (find the grid/tab-strip
   ids with `aapt dump --values resources` on the APK; FeurStagram-style).
   Block `/feed/user/<id>/` and `/clips/user/` at Tigon when the request is
   not for the self user (the self user id is available from
   `UserDataEntity`), so the grid is also empty at the network layer.
5. **Post chaining** (D7): Tigon block of `/discover/chaining/`,
   `/media/<id>/chaining*`, `/feed/injected_reels_media`, `/clips/chaining*`,
   `/discover/ayml/`, `/discover/sectioned_ayml/`, plus the parser-level drop
   for `clips_netego`, `stories_netego`, `bloks_netego`, `ad4ad`, `suggested_*`,
   `vibes_in_feed_unit`, `in_feed_survey`. Use `adb logcat`-free discovery:
   piko's `Links.java` already has a debug hook pattern; add a Postbox
   `Log.i("PostboxNet", path)` behind a build option (`enableTestHooks`-style,
   default false, asserted false in release like `build-x.sh:123`) to list
   every endpoint a surface requests, then block. Never ship the trace on.
6. **Pref hardcoding** (L4): one Postbox bytecode patch that depends on the
   piko patches it forces and rewrites these `Pref` getters to constants:
   `disableExplore()`->true, `disableReelsScrolling()`->true,
   `hideSuggestedContent()`->true, `disableDiscoverPeople()`->true,
   `disableSwipeToCreate()`->true, `hideNavigationReels()`->true,
   `hideNavigationSearch()`->true, `hideNavigationCreate()`->true (Create is a
   header button here, not a tab; confirm on device), `hideNavigationFeed()`->false,
   `hideNavigationDirect()`->false, `navigationTabs()`-> the fixed config
   string with startup `messages`, and `focusLock*`/legacy getters left as is.
   Then hide those rows in piko's settings screens (`settings/preference/ScreenBuilder.java`
   and the `NavigationBarPreference`/`NavigationStartupPreference` widgets) or
   make them read-only; the getter rewrite is the actual lock, the UI change is
   hygiene.
7. **Feed-switcher dropdown hide** (D6): view-id hider on the Home action bar
   title (find id on the APK; likely `action_bar_title`/`feed_switcher`).

### 4.5 Vantage pipeline anchors (paths under `~/code/vantage`)
- Template workflow: `.github/workflows/build-x.yml` (Java 21 Temurin,
  `pip install curl_cffi`, `permissions: contents: write`, keystore secrets as
  env, `bash scripts/build-x.sh $FORCE --release`, logs uploaded on failure).
  Postbox's adds `on: push` with `paths:` and `repository_dispatch:
  types: [piko-release]`, keeps `workflow_dispatch` with `force`.
- Template script: `scripts/build-x.sh` (piko release resolve L55-64, skip
  logic vs last `x-v*` manifest L66-88, toolchain L90-95, version pin/resolve
  L97-100, keystore preflight L103, APKM download L105-107, patch loop
  L109-148, manifest L150-159, release L161-204). `scripts/patch.sh` args:
  `--jar --patches --options --keystore --apk --out --result --log --tmp
  [--exclusive]`. `scripts/download-apk.sh <pkg> <ver> <arch> <out> apkm`
  (stock-cache release checked first; `X_DL_SOURCES="apkmirror"`; cert gate
  `verify_apkm` L332). `scripts/assert.sh variant --variant --result --log
  --apk --package --label --nonneg --inert --forbidden --min-size-mb`
  (`assert_variant` L38). Lists live in `config/assertions/` (`x-nonnegotiable.txt`
  is the model: exact patch names, one per line).
- `config/build.env`: add `IG_PACKAGE=com.instagram.android`,
  `IG_DL_SOURCES="apkmirror"`, `IG_ARCH=arm64-v8a`, `IG_VERSION_PIN=` (empty =
  resolve from the bundle's `list-versions`, which for piko yields exactly the
  one supported version), `POSTBOX_PACKAGE=app.vantage.postbox`,
  `POSTBOX_LABEL=Postbox`. Reuse `PIKO_REPO=pmaxhogan/piko`.
- `config/expected-signatures.txt`: add Instagram's Play signing cert
  (`apksigner verify --print-certs` on the downloaded base split; cross-check
  against piko's / Morphe's published list before committing). Format:
  `<package>  <sha256-lowercase>`.
- `scripts/gen-obtainium-config.py`: `app(app_id, name, author, url, addl)`
  + `vantage_addl(regex)`; add the Postbox entry next to the X one (L77-102).
- Release naming: tag `postbox-v<YYYY.MM.DD>-piko<ver>`, assets
  `postbox-<igver>.apk`, `built-versions-postbox.json`
  (`{builtAt, pikoVersion, morpheCliVersion, igVersion, package}`),
  `obtainium-config.json`. `--latest=false` always (YouTube's skip logic
  ignores non-`v*` tags, and X's ignores non-`x-v*`; make Postbox's ignore
  non-`postbox-v*`).
- `apkmirror-dl.py` serves APKM for X today; Instagram is on APKMirror as APKM
  (arm64-v8a + nodpi variants exist - pick arm64-v8a, nodpi).
- README structure: per-app sections (`## Vantage X (Twitter/X)` at L82;
  install at L14-45; the apps table around L104; file map L480-492).

### 4.6 piko fork anchors (paths under `~/code/piko`)
- `.github/workflows/build-mpp.yml`: push to main (path-filtered to
  `extensions/**`, `patches/**`, gradle files, itself) + dispatch; computes
  `VVER=<upstream version>-vantage.<VANTAGE_REV>` (env `VANTAGE_REV`, L48-50;
  bump it for a fork-only rebuild); runs `:extensions:twitter:testDebugUnitTest`
  then `:patches:buildAndroid -Pversion=$VVER`; publishes `v$VVER` with asset
  `patches-$VVER.mpp`, prerelease per repo var `MPP_PRERELEASE`. Add: an
  Instagram extension test task if tests are added, and a final step
  `gh api repos/pmaxhogan/vantage/dispatches -f event_type=piko-release`
  (needs a PAT with `repo` scope on the fork as a secret, e.g. `VANTAGE_DISPATCH_TOKEN`,
  since `GITHUB_TOKEN` cannot dispatch to another repo - pre-granted under X5).
- `.github/workflows/sync-upstream.yml`: nightly 07:00 UTC, opens a PR from
  `crimera:main`, merges only if MEMBER/MERGEABLE checks pass, then dispatches
  build-mpp. Fork-only files must avoid touching upstream-owned lines
  (`gradle.properties` is kept byte-identical). New Postbox files live in new
  directories so they never conflict.
- Latest fork release: `v3.10.0-vantage.2` (2026-10-11), asset
  `patches-3.10.0-vantage.2.mpp`. Upstream latest `v3.10.0` (2026-10-10).
- Upstream `.github/dependabot.yml` targets `dev`, monthly (gradle, npm,
  github-actions). The fork override (weekly, `main`) will be a standing
  conflict source on upstream edits to that file; accept it (sync-upstream
  leaves conflicting PRs open for Max) or keep the fork's copy identical and
  rely on a separate fork-owned workflow file. Prefer: override the file, note
  it in CLAUDE.md.
- Existing twitter extension has JUnit tests (`build-mpp.yml:74-80`); the
  Instagram extension has none. Add unit tests for the pure logic in the new
  Postbox extension (URL classifier, shortcut-id filter, nav config string)
  under `extensions/instagram/src/test/java/...` and run them in build-mpp.

### 4.7 Dependabot auto-merge templates
- Public repos (all three here): copy `~/code/tapshim/.github/workflows/dependabot-auto-merge.yml`
  (`pull_request` -> `dependabot/fetch-metadata@v2` -> `gh pr merge --auto
  --squash` for minor/patch, comment for major) and `~/code/tapshim/.github/dependabot.yml`
  (weekly Monday, groups). Native auto-merge needs `allow_auto_merge: true`
  (vantage: already true; piko, vantage-patches: false - enable via
  `gh api -X PATCH repos/pmaxhogan/<r> -f allow_auto_merge=true`) AND a
  ruleset on `main` requiring the CI status check, otherwise `--auto` merges
  immediately with no check. vantage has no `pull_request` CI today: add a
  cheap `ci.yml` (shellcheck + `python3 -m py_compile` + `jq` validation of the
  options/config JSON + `bash -n`) and make it the required check. piko fork:
  `build_pull_request.yml` exists upstream; vantage-patches: add a gradle
  compile check or reuse its build workflow on `pull_request`.
- Gotchas from the leaveby session (2026-10-11): no workflow-level
  `concurrency` group on the merge workflow (a group drops queued merges);
  Dependabot PRs get no Actions secrets, so CI must not need the keystore on
  bot PRs (guard with `github.event.pull_request.user.login == 'dependabot[bot]'`
  or keep CI secret-free); several bot PRs touching the same manifest conflict
  after the first merge and Dependabot rebases them itself; a GITHUB_TOKEN
  merge does not trigger push workflows, so if a dependabot merge must release
  (P2 says only when it touches Postbox files), the release workflow needs
  `workflow_dispatch` and the merge job dispatches it - or accept that bot
  merges release only via the next human push. Decision: accept the latter;
  note it in CLAUDE.md.
- `gh pr merge` and `gh pr comment` by hand are hook-gated on this machine
  (approval queue). Workflows running in Actions are not.

### 4.8 Android facts to verify on the first build (do not assume)
- Instagram's static shortcuts: expect `res/xml/shortcuts.xml` referenced by
  `<meta-data android:name="android.app.shortcuts">` on the launcher activity
  (typical entries: Camera, New post, Direct, Activity). Dynamic shortcuts are
  published at runtime; `adb shell dumpsys shortcut --package app.vantage.postbox`
  shows both after one launch.
- App Links: `assetlinks.json` on instagram.com lists only Meta's package+cert,
  so a clone never auto-verifies. On Android 12+ the user opens Settings >
  Apps > Postbox > Open by default and adds `instagram.com` links by hand.
  Document it (P8); do not attempt to patch around it.
- Whether piko's `normalize()` (NavigationBarPatch.java L328+) accepts a
  3-tab config with Home visible: should, since HOME is in DEFAULT_VISIBLE.
- Whether the Home-header "+"/heart survive `hideHomeActionButtonsPatch`.
- Which Instagram request paths the profile grid, post chaining, Explore and
  Reels surfaces use on 447.x (trace with the debug-only logging hook, then
  block).

---

## 5. Work ordering and gates

**Wave 0 - orientation (opus orchestrator, no subagents).** Read this spec.
`git -C ~/code/piko fetch && git status`; `git -C ~/code/vantage status`.
Download the pinned Instagram APKM locally through `scripts/download-apk.sh`
(after adding the cert) and decode what is needed (`aapt`, `apktool d` or
morphe-cli's `-t` scratch dir) to confirm section 4.8. PushNotification: "Postbox
started".

**Wave 1 - pipeline with piko's existing patches only (sonnet subagents for
YAML/shell/JSON; orchestrator reviews).** Gate: a `postbox-v*` release exists
with a signed APK built from `config/postbox-options.json` that enables Clone
(`app.vantage.postbox`/"Postbox"), nav bar config, Disable explore, Disable
Reels scrolling, Hide suggested content; `assert.sh` passes; Obtainium entry
regenerated; the APK installs on the Pixel 6 and reaches the login screen.
PushNotification asking Max to log in. Also in this wave: `build-mpp.yml`
dispatch step + `VANTAGE_DISPATCH_TOKEN`, path-filtered `on: push`.

**Wave 2 - lock-down, hardest-to-bypass first (opus subagents for Kotlin/Java;
orchestrator reviews every diff).** Order: (a) Pref hardcoding + nav config +
startup override (L3, L4); (b) shortcuts (L1); (c) deep-link router + Tigon
blocks for feed/explore/reels/chaining (L2, D4, D7); (d) profile grid (D8);
(e) feed-switcher dropdown, activity-feed suggestions (D6). Each item lands
as its own commit in the fork, `build-mpp` releases, vantage rebuilds via
dispatch, the implementer installs and verifies that item's flows on the
device before the next. Gate: all section-7 flows pass with screenshots.
PushNotification at the end of (c) and at the end of the wave.

**Wave 3 - dependabot + docs (sonnet subagents).** dependabot.yml + auto-merge
workflow + required-check ruleset + `allow_auto_merge` on all three repos; a
minimal `ci.yml` on vantage; README sections; CLAUDE.md notes; fork README
patch list. Gate: `gh api repos/pmaxhogan/<r> --jq .allow_auto_merge` true on
all three; the auto-merge workflow has run (trigger a Dependabot check via
`gh api -X POST repos/<r>/dependabot/...` is not available - instead confirm
by waiting for the first weekly PR or by opening one bot-style PR is not
possible; so: verify the workflow file lints, the ruleset exists, and leave a
note that first live proof arrives Monday). PushNotification: "Postbox done".

**Stuck policy.** Park-and-document after two failed attempts on one
fingerprint: ship the X3 fallback for that item, write the failure (what was
tried, the smali context) into the final report and `.claude/CLAUDE.md`, move
on. Escalate to Max (PushNotification, then AskUserQuestion if he is present)
only for: a departure from a locked decision, anything that bills, outbound
messages, or a contradiction between two locked decisions. "Which fingerprint
strategy" is never an escalation.

---

## 6. Process rules (verbatim grants and limits)

- Pre-granted (X5 + standing): adb install/uninstall/clear-data/reboot on the
  Pixel 6 (restore after); running an emulator; pushing to `pmaxhogan/piko`
  main and cutting fork releases; dispatching workflows; creating and editing
  GitHub releases on `pmaxhogan/vantage`; changing repo settings on the piko
  fork and vantage-patches (auto-merge, rulesets, variables); adding Actions
  secrets/variables on vantage and the fork for the dispatch PAT; downloading
  the Instagram APKM from APKMirror; installing over stock Instagram on the
  Pixel 6 if the clone conflicts; reading `~/.unbroker-secrets/`, `.env.local`.
- Not granted: Discord/email/any outbound message (approval queue only);
  spending money; touching Max's Instagram password (he logs in himself);
  enabling any debug/trace option in a release build (assert it off, as
  `build-x.sh:123` does for `enableTestHooks`).
- Git: direct commits to main in all three repos; conventional-commit subjects
  (`feat(instagram): ...`, `ci: ...`, `docs: ...`); no em-dashes anywhere; LF
  endings. Public repos: these clones carry `"attribution": false` in
  `.claude/settings.local.json` - before the first push run
  `git show -s --format=%B HEAD` and confirm there is no `Co-Authored-By: Claude`
  or `Claude-Session:` trailer.
- Review: the orchestrator reads every patch and extension diff before push.
  No Codex, no PR gate.
- Tech request: none (personal project).
- Standing-answers to record (the executing session appends these to
  `~/unbroker/.claude/ultraquest-standing-answers.md` under a new
  `### pmaxhogan/vantage + pmaxhogan/piko (Postbox quest, 2026-10-11)` heading,
  dated):
  - Dependabot on personal public repos: weekly, minor/patch auto-merge via
    the tapshim-shaped `pull_request` workflow, majors commented and held;
    requires `allow_auto_merge` + a required-check ruleset.
  - Release triggers for Vantage apps added from now on: push-to-main with
    path filters + `repository_dispatch` from the patch repo, no cron, unless
    the quest says otherwise.
  - Instagram test login: Max's own account, he types it; agents never hold
    Instagram credentials.
  - Modified-client ban evidence (2026-10-11): piko ~4 anecdotal suspension
    threads, FeurStagram none confirmed; keep Postbox to structural blocking
    patches only.

---

## 7. Verification (X2) - the acceptance checklist

Run on the Pixel 6 with Max logged in. Capture a screenshot per line
(`adb exec-out screencap -p > <name>.png`) and attach them to the final report.

Required flows (must work):
1. Cold launch lands on the Messages tab. Bottom bar shows exactly Home,
   Messages, Profile.
2. Home tab shows the stories tray and the own-story "+"; the area below is
   empty (no posts, no "suggested", no ads). Header shows "+" and heart; no
   feed-switcher dropdown.
3. Tap a friend's story: it plays; stories advance normally.
4. Post a story (camera or gallery): it appears in the tray.
5. Inbox: open a 1:1 thread and a group thread, send a text reply.
6. In a thread, open a reel someone sent: it plays as a single item; a
   vertical swipe does not reveal another reel.
7. In a thread, open a post someone sent: post, caption and comments show;
   nothing scrolls in below it.
8. From another app (Chrome, Signal, etc.) open an `instagram.com/p/...` link
   and an `instagram.com/reel/...` link with Postbox chosen as handler: each
   opens as a single item (after the one-time "Open supported links" setup).
9. Profile tab: own profile shows grid, followers, following lists open.
10. Open another person's profile from a DM: header, bio, highlights,
    follower/following lists work; no posts/reels grid is rendered.
11. Heart: the activity feed opens; no "suggested for you" rows.
12. Settings: log out, log back in with 2FA, change a harmless setting.

Forbidden routes (must be blocked, each lands on the inbox or an empty surface
per D12):
13. Long-press the Postbox launcher icon: no Instagram shortcuts (Camera, New
    post, Direct, Activity) are offered; `adb shell dumpsys shortcut --package
    app.vantage.postbox` lists no dynamic/static shortcuts.
14. `adb shell am start -a android.intent.action.VIEW -d https://www.instagram.com/explore/ app.vantage.postbox`
    lands on the inbox. Same for `https://www.instagram.com/reels/`,
    `https://www.instagram.com/`, `https://www.instagram.com/explore/tags/cats/`,
    `instagram://explore`, `instagram://reels`, `instagram://feed`.
15. `adb shell am start -n app.vantage.postbox/<MainActivity> --es MainActivityAccountHelper.STARTUP_TAB CLIPS`
    (and `SEARCH`, `FEED`) lands on the inbox or stories-only Home, never on
    Reels or Search.
16. Open a reel from a notification (if one arrives) or from a profile
    highlight: single item, no paging.
17. In piko's settings page (if still reachable): no toggle can re-enable
    Reels, Explore, Search, the feed or suggested content; the rows are gone
    or read-only, and flipping any that remain changes nothing after restart.
18. Horizontal swipe from the Home tab does not open the camera/create pane
    (piko `Disable swipe to create`) and does not land on a hidden tab.

Build-level:
19. `assert.sh` passes with `config/assertions/postbox-nonnegotiable.txt`
    listing every Postbox and piko patch that must apply (exact names) and
    `postbox-forbidden.txt` listing the excluded piko patches (downloads, ghost
    mode, ad block, theme).
20. The release tag, assets and regenerated `obtainium-config.json` exist;
    Obtainium on the Pixel 6 imports the config and shows Postbox installable
    (Obtainium is installed there for Vantage already).
21. `repository_dispatch` chain proven: a fork release triggered a vantage
    run (link the run ids in the report).

---

## 8. Ops and reminders

- No status-dashboard entry (personal project, not Unbroker gatus).
- `MPP_PRERELEASE` repo variable on the fork gates whether vantage sees a new
  bundle; leave it `false` once Postbox patches are ready, use `true` to stage.
- Bump `VANTAGE_REV` in `build-mpp.yml` for fork-only rebuilds on the same
  upstream version.
- Keep `gradle.properties` byte-identical to upstream in the fork.
- Release notes template (from `build-x.sh:169-191`): state the Instagram
  version, piko version, morphe-cli version, package, what is blocked, the
  "Open supported links" step, and that it installs alongside stock Instagram.
- Never leave `nohup.out` or build outputs untracked in vantage (it is in
  `.gitignore`? check; today `nohup.out` is untracked at the repo root - leave
  it alone, it is not yours).

---

## 9. Current-state snapshot (2026-10-11, late evening CT)

- `~/code/vantage` main at `e35c414` ("docs: list the vantage-patches Music
  patches"), clean except untracked `nohup.out`. `allow_auto_merge=true`.
  Workflows: `build.yml` (YouTube, cron 09:00 UTC), `build-x.yml` (cron
  10:00 UTC), `build-claude.yml` (cron 11:30 UTC), `probe-sources.yml`. No
  dependabot, no `pull_request` CI.
- `~/code/piko` main at `7b3b3233` ("fix(ci): sync-upstream tolerates a
  workflow-file merge it cannot perform"), fork of `crimera/piko`, upstream at
  `v3.10.0` (2026-10-10), fork release `v3.10.0-vantage.2` (2026-10-11).
  `allow_auto_merge=false`. piko Instagram target `447.0.0.55.81` (versionCode
  385311895, arm64-v8a, APKM).
- `~/code/vantage-patches` main, `allow_auto_merge=false`, no dependabot.
  Not otherwise touched by this quest.
- Pixel 6 `24021FDF6001U4` connected over adb; stock Instagram NOT installed;
  Vantage X, Vantage YouTube/Music installed; Obtainium present.
- Local toolchain: Temurin 21, Android SDK with build-tools and platform-tools,
  `morphe-cli-1.18.1-all.jar` and `APKEditor-1.4.9.jar` cached in
  `vantage/build/tools/`. No Instagram APK anywhere locally yet.
- Peer sessions live on this machine (ListAgents): `triage` (coordinator),
  `leaveby-add-dependabot-auto-merge` (just shipped the leaveby auto-merge;
  source of the gotchas in 4.7). Message them before touching anything they
  might be standing in; neither is in vantage or piko today.
- Standing answers file: `~/unbroker/.claude/ultraquest-standing-answers.md`
  (section "pmaxhogan/vantage + pmaxhogan/piko (personal, 2026-09-07...)")
  holds the X-quest grants reused here.

---

## 10. Judgment calls made during the interview (already decided, listed for transparency)

- Cold-start tab is Messages (not Home) - follows from D12 and the product
  goal; Max did not pick it explicitly.
- piko's "Change version code" is enabled so the clone never receives Play
  Store update prompts; harmless and standard for clones.
- "Sanitize share links" is enabled (strips tracking params from links the
  user shares out); harmless, low-risk.
- Postbox keeps piko's settings entry point, stripped of the locked rows,
  rather than removing the settings framework entirely (removing it would
  also remove the crash handler and the fixes `settingsPatch` carries).
