# RVX settings files (optional reset-to-baseline)

The Vantage behaviors (Shorts nav button hidden, start page = Subscriptions,
etc.) are runtime settings stored in the app's `shared_prefs/revanced.xml`, not
something a patch sets by itself. The anddea patch fork we build from bakes these
defaults into its `.mpp`, so a fresh install already behaves correctly with no
in-app import step.

> Note: Shorts playback is hard-disabled in the build itself - a fork change to
> the Shorts playback-start hook (`ShortsPatch.openShortInRegularPlayer`), not a
> setting. Every entry point (channel Shorts tab, home-screen widget, direct
> link, playlist, Liked Videos) is intercepted so no Short can play, and there is
> no toggle to re-enable it. The `hide_shorts_*` settings below only remove Shorts
> from view; the hard block is what makes playback impossible.

The files here are just optional reset-to-baseline exports: import one to snap a
customized install back to the shipped defaults. They are not the delivery
mechanism.

## File format

These are the app's own RVX settings export format, not generic JSON:

- A JSON object body with no wrapping `{ }` braces and no trailing comma -
  exactly what RVX's "Export settings to a file" writes and its "Import settings"
  reads back. RVX reads its own braceless export back fine, so don't "fix" it into
  strict JSON - keep it byte-compatible with RVX.
- Keys have the `revanced_` prefix stripped (e.g. `change_start_page`, not
  `revanced_change_start_page`). The `scripts/assert.sh` settings-key guard
  re-adds the prefix when checking the APK dex.
- Only non-default settings appear. Anything already at its build default
  (SponsorBlock enabled, Return YouTube Dislike, disable-resume-Shorts, hide-ads)
  is absent - it is already on in the build.
- RVX import is reset-then-apply, not merge: importing a file resets all other
  RVX settings to their defaults and applies only the listed keys. Fine for a
  fresh install; be aware when importing over a customized one.

## Files

- `vantage-youtube.json` - the YouTube (anddea) baseline. Captured on a Pixel 6
  (signed out): start page = Subscriptions; Shorts nav button hidden and Shorts
  shelves hidden everywhere (master `hide_shorts_shelf` + channel + watch-history;
  home/subscriptions/search are default-on); comments section hidden; community
  posts hidden (channel + subs); DeArrow alternative thumbnails on all 5 surfaces;
  copy-video-URL and copy-timestamp-URL overlay buttons shown; Playables hidden
  from the feed; the AI-generated video summary and Ask (Gemini) sections hidden
  in the video description. SponsorBlock / RYD
  / disable-resume-Shorts / hide-ads are RVX build defaults (already on, so not
  listed). `hide_shorts_shelf` is a master toggle - without it on, the per-surface
  Shorts-shelf hiding does nothing (this was the "still see Shorts" gap).
- `vantage-music.json` - the Music baseline. Not yet captured (placeholder `{}`):
  Music's core behaviors (no ads, background play) are build defaults, so v1 ships
  without a Music file. Capture later if Music needs non-default toggles.

## Capture procedure (for future re-capture)

Configure the target toggles once via the app UI, use RVX Settings toolbar
Export (writes the non-default file), `adb pull` it, strip any transient
runtime-cache line (e.g. `morphe_spoof_video_streams_player_js_hash_value` - a
player-JS hash cache, not a preference), commit it here, and attach it to the
release. Then run the round-trip test: perturb a setting, Import the file,
restart, confirm the setting reverts.
