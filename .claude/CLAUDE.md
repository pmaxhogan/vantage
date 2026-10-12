# Vantage - notes for agents

Builds and releases patched Android apps (YouTube family, Vantage X, Claude clones,
Postbox) and the Obtainium config that installs them. README.md covers the user-facing
side; these notes are the traps. The Postbox decisions are locked in
`.claude/postbox-spec.md` (do not re-ask them).

## Hygiene

- Never `git add -A` or `git add .`: an untracked `nohup.out` sits at the repo root and
  is not part of any change. Add files by name.
- ASCII `-` only, no em/en-dashes. LF endings.
- Direct commits to main are the norm here, which makes the next section matter.

## Postbox (patched Instagram)

### A push to a Postbox path releases immediately

`build-postbox.yml` fires on any push to main that touches: the workflow itself,
`scripts/build-postbox.sh`, `lib.sh`, `patch.sh`, `download-apk.sh`, `scripts/*-dl.py`,
`assert.sh`, `gen-obtainium-config.py`, `config/build.env`,
`config/expected-signatures.txt`, `config/postbox-options.json` or
`config/assertions/postbox-*`. Push and dispatch runs pass `--force`, so it builds and
publishes regardless of the piko version. A docs-only or README change does not fire it,
but a one-character edit to `lib.sh` (shared with every other build) does. There is no
cron. Batch Postbox-path edits into one push, and know that a half-finished push is a
live release attempt.

### The dispatch chain, end to end

1. A push to the piko fork's main touching `extensions/**`, `patches/**` or gradle files
   runs the fork's `build-mpp.yml`: Instagram + X extension unit tests, then
   `:patches:buildAndroid -Pversion=<upstream>-vantage.<VANTAGE_REV>`, then a GitHub
   release `v<upstream>-vantage.<VANTAGE_REV>` with asset `patches-<ver>.mpp`. Whether
   it is a prerelease is the fork repo variable `MPP_PRERELEASE` (default false).
2. The last step, "Notify vantage (repository_dispatch)", sends
   `event_type=piko-release` (payload `piko_version`) to `pmaxhogan/vantage` using the
   fork secret `VANTAGE_DISPATCH_TOKEN`. It skips with a warning when the secret is
   absent, skips when the release is a prerelease (vantage reads `/releases/latest`,
   which hides prereleases), and never fails the fork job.
3. vantage's `build-postbox.yml` receives `repository_dispatch: [piko-release]` and runs
   `build-postbox.sh --force --release`: resolve the fork's latest release, patch,
   assert, publish `postbox-v<date>-piko<ver>`.

The token is a fine-grained PAT for `pmaxhogan/vantage` only, Contents read+write,
Metadata read (`GITHUB_TOKEN` cannot dispatch across repos).

Prove it fired, do not infer it:

- Fork side: the "Notify vantage" step log says `dispatched piko-release (<ver>) to
  pmaxhogan/vantage`. The warning `VANTAGE_DISPATCH_TOKEN is not set` means the chain is
  broken at step 2 (`gh secret list -R pmaxhogan/piko`).
- Vantage side: `gh run list -R pmaxhogan/vantage --workflow "Build Postbox" --event
  repository_dispatch` shows a run created seconds after the fork release. Then
  `gh release list -R pmaxhogan/vantage | grep postbox-v` and check the release's
  `built-versions-postbox.json` `pikoVersion` equals the fork release you expected.
- A dispatch run that is green but published nothing is possible only on the manual
  path (the skip-if-piko-unchanged check). Push and dispatch runs always build.

### Following an Instagram version bump

- The binding constraint is the piko fork's supported version, not what Instagram ships.
  `resolve_target_version` (`scripts/lib.sh`) reads `morphe-cli list-versions` from the
  bundle, so with `IG_VERSION_PIN` empty in `config/build.env` Postbox builds exactly
  the one version piko supports (447.0.0.55.81, arm64-v8a, as of 2026-10-11). A bump
  arrives as a new fork release after the fork syncs upstream piko; do not pin a
  version piko does not list. `IG_VERSION_PIN` is for holding at a supported version.
- `list-versions` lines for Instagram carry a per-ABI block:
  `447.0.0.55.81 [versionCodes: ARM64_V8A=385311895] (52 patches)`. `resolve_target_version`
  strips the `[versionCodes: ...]` suffix with its last `sed` expression. If a
  morphe-cli release changes that format, the version resolves to junk and the
  download step fails on a nonsense file name; look there first.
- The stock APKM must be in the `stock-cache` release as
  `com.instagram.android-<ver>.apkm` before the build can run. APKMirror and APKPure
  both put Instagram behind an interactive Cloudflare challenge the `curl_cffi`
  resolvers cannot pass (and must not try to), so there is no live-download fallback.
  How a cache entry gets seeded for a new version was still being decided with Max on
  2026-10-11: do not invent a procedure; ask.
- `build-postbox.sh` runs `verify_apkm` on whatever came back, because
  `download-apk.sh` trusts a cache hit: every split must be signed by one of the two
  Instagram certs in `config/expected-signatures.txt` and the base must report the
  right package and version. Those certs came from
  `https://www.instagram.com/.well-known/assetlinks.json`; the comment in that file
  says they were NOT yet confirmed against a real downloaded base split
  (`apksigner verify --print-certs`). Confirm that the first time a real APKM is in hand.
- After a bump also check: `postbox-nonnegotiable.txt` names still match piko's patch
  names exactly (an upstream rename should fail the build, that is the point),
  `postbox-inert-allowlist.txt` (empty on 447.0.0.55.81), and the `--min-size-mb 40`
  floor in `build-postbox.sh`, a guess to tighten once a real build exists.

### Options-file invariants (`config/postbox-options.json`)

- Every patch in the piko bundle is listed with an explicit `enabled`; the build passes
  `--exclusive`, so anything not enabled does not run even if a future upstream patch
  defaults on. When the fork gains a patch, add it as `false`.
- Enabled set: `Add settings`, `Clone` (`packageName` `app.vantage.postbox`, `appName`
  `Postbox`), `Customize navigation bar`, `Disable explore`, `Disable Reels scrolling`,
  `Hide suggested content`, `Disable discover people`, `Disable swipe to create`,
  `Sanitize share links`, `Change version code`, and the four fork-only `Postbox settings lock`, `Postbox
  shortcut lock`, `Postbox link router`, `Postbox network block`. `postbox-nonnegotiable.txt`
  lists exactly these fourteen.
- `postbox-forbidden.txt` (downloads, ghost mode, typing status, read receipts, ad
  blocking, screenshot detection, theme, font, Focus Lock, Inbox lock, Limit feed to
  following profiles, the Unlock patches). `check_postbox_options`
  in `build-postbox.sh` refuses an options file that enables one, and `assert.sh`
  re-checks what actually applied, because morphe can pull a deselected patch back in
  as a dependency.
- The `traceNetwork` option of `Postbox network block` must stay `false`. It logs every
  request path to logcat and is only for endpoint discovery on a verification build.
  `build-postbox.sh` refuses to build when ANY enabled patch has an option whose key
  matches `test|debug|trace` and is truthy; a patch entry with no `enabled` key counts
  as enabled. Never work around that to ship a trace build as a release.
- `Change version code` is enabled, as the spec says (section 3), so a store can never
  offer the clone an update. It is compatible with both X and Instagram
  (`compatibleWith(COMPATIBILITY_X, COMPATIBILITY_INSTAGRAM)` in piko's
  `ChangeVersionCodePatch.kt`). Trap when checking that kind of thing with
  `list-patches --with-packages`: read the whole "Compatible packages" block. A
  truncated view once showed only `com.twitter.android` and the patch was wrongly
  dropped as "X-only" for a few hours on 2026-10-11.

### Release behaviour worth knowing

- Tag `postbox-v<YYYY.MM.DD>-piko<ver>`, always `--latest=false` (the "latest" slot must
  stay on a YouTube release because the README install link and `obtainium-config.json`
  hang off it). Assets: `postbox-<igver>.apk`, `built-versions-postbox.json`,
  `obtainium-config.json`. The script refuses a config copy that lacks the
  `app.vantage.postbox` entry, so regenerate it with `scripts/gen-obtainium-config.py`
  and commit it before a Postbox push.
- Same-day rebuild with the same piko version updates that release in place (assets
  clobbered). Obtainium keys on the release DATE (`releaseDateAsVersion`), so it does
  not offer that rebuild to phones that already took the day's build. To force a
  phone onto a rebuild, uninstall/reinstall by hand or wait for the next day's tag;
  do not expect Obtainium to notice.
- The YouTube and X skip logic ignore `postbox-v*` tags, and Postbox's ignores everything
  else.

## Dependabot and CI

- Weekly (Monday) on all three repos: vantage (github-actions + pip via
  `requirements.txt`, which now holds `curl_cffi` for the workflows), the piko fork
  (github-actions + gradle, targeting main), `vantage-patches` (github-actions + gradle).
- Auto-merge is a `workflow_run` job that runs after the PR CI finishes green: workflow
  `CI` in vantage and vantage-patches, `Vantage CI` in the fork. Minor and patch updates
  are squash-merged with `--match-head-commit`; majors and PRs with no semver type get
  one comment and wait for a human. No ruleset on main, because a required check would
  also gate direct pushes (and the fork's sync PR, opened with `GITHUB_TOKEN`, never
  triggers `pull_request` workflows).
- Do not add a workflow-level `concurrency` group to the auto-merge workflow: a group
  keeps one pending run and drops the rest, losing queued merges.
- `ci.yml` must stay secret-free (Dependabot PRs get no Actions secrets) and its `name`
  must stay `CI`, or the auto-merge workflow listens to nothing.
- A merge made with the workflow token triggers no push workflows. So a bot merge that
  touches a Postbox path releases nothing by itself; the next human push does (or a
  manual run of `build-postbox.yml`).
- Dependabot version updates are OFF by default on a fork. They must be enabled once in
  the fork's Settings > Advanced Security (the `dependabot.yml` there does nothing
  until then).
- `gh pr merge` and `gh pr comment` by hand are hook-gated on this machine; workflows
  running in Actions are not.

## Not verified yet

Nothing about Postbox has been checked on a device as of 2026-10-11, and the signing
certs and the size floor are unconfirmed against a real APKM (see above). The README
says the same; when that changes, update both.
