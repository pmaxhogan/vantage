# Vantage custom icon set

The three build variants reference a custom Vantage launcher icon via a folder
path option (not a preset name):

- `config/icon/vantage`       - YouTube (anddea) `Custom branding icon for YouTube` -> `appIcon`
- `config/icon/vantage`       - Morphe YouTube  `Custom branding` -> `customIcon`
- `config/icon/vantage-music` - YouTube Music   `Custom branding icon for YouTube Music` -> `appIcon`

Both YouTube variants share the `vantage` folder; Music uses `vantage-music`.

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

and inside each `mipmap-*` folder these four PNGs:

```
ic_launcher.png
ic_launcher_round.png
adaptiveproduct_youtube_background_color_108.png
adaptiveproduct_youtube_foreground_color_108.png
```

The committed icons build cleanly in folder-path mode across all three variants.
`vantage-music` currently reuses the `vantage` PNGs; swap in a Music-tinted set
here if one is wanted.
