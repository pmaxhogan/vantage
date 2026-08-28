# Vantage custom icon set

The four build variants reference a custom Vantage launcher icon via a folder
path option (not a preset name):

- `config/icon/vantage`        - YouTube (anddea) `Custom branding for YouTube` -> `customIcon`
- `config/icon/vantage-alt`    - YouTube Alt      `Custom branding for YouTube` -> `customIcon`
- `config/icon/vantage-morphe` - Morphe YouTube   `Custom branding` -> `customIcon`
- `config/icon/vantage-music`  - YouTube Music    `Custom branding for YouTube Music` -> `customIcon`

anddea 4.3.0-dev.2 merged its three branding patches (icon / name / header) into
one `Custom branding for X` patch and moved to morphe's asset naming, so all four
folders now use the same file names.

## Folder layout

Each icon folder holds the mipmap PNG set at five densities:

```
config/icon/<name>/
  mipmap-mdpi/
  mipmap-hdpi/
  mipmap-xhdpi/
  mipmap-xxhdpi/
  mipmap-xxxhdpi/
```

and inside each `mipmap-*` folder these two adaptive layers:

```
morphe_adaptive_background_custom.png
morphe_adaptive_foreground_custom.png
```

Optionally a `drawable/` folder with `morphe_adaptive_monochrome_custom.xml` and
`morphe_notification_icon_custom.xml` (only `vantage-morphe` ships those today).

The leftover `ic_launcher*.png` files in some folders are from the pre-dev.2
`appIcon` layout and are no longer read by any patch - harmless, kept as source
art. The committed icons build cleanly in folder-path mode across all variants.
The background layer is shared; each variant has its own foreground.
