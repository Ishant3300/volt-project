# Volt brand assets

| File | Purpose |
|---|---|
| `logo.svg` | In-app logo (splash + login). Transparent background, matches the `Subtract.svg` convention used by Apex. |
| `icon_source.svg` | Source for the launcher icon — the brand mark on an opaque white background. |
| `adaptive_foreground_source.svg` | Source for the Android adaptive-icon foreground. viewBox is expanded so the mark sits inside the 66% safe zone. |
| `icon.png` | 1024×1024 launcher icon, generated from `icon_source.svg`. |
| `adaptive_icon_foreground.png` | 1024×1024 adaptive foreground, generated from `adaptive_foreground_source.svg`. |

## Regenerating the PNGs

No SVG rasterizer (`rsvg-convert` / ImageMagick / Inkscape) is installed on this
machine, so the PNGs were produced with macOS QuickLook:

```bash
cd assets/volt
mkdir -p .tmp_png
qlmanage -t -s 1024 -o .tmp_png icon_source.svg
qlmanage -t -s 1024 -o .tmp_png adaptive_foreground_source.svg
cp .tmp_png/icon_source.svg.png              icon.png
cp .tmp_png/adaptive_foreground_source.svg.png adaptive_icon_foreground.png
rm -rf .tmp_png
```

### Why `adaptive_icon_background` is white

`qlmanage` flattens transparency onto white, so `adaptive_icon_foreground.png`
has an **opaque white** background rather than a transparent one.

This is intentionally paired with `adaptive_icon_background: "#FFFFFF"` in
`flutter_launcher_icons-volt.yaml`. Because the brand mark's own negative space
is already white, a white background layer makes the flattened foreground
render **identically** to a properly transparent one under every Android mask
(circle, squircle, rounded square).

If you later install a real rasterizer and want a transparent foreground, run:

```bash
rsvg-convert -w 1024 -h 1024 adaptive_foreground_source.svg -o adaptive_icon_foreground.png
```

…and you may then change `adaptive_icon_background` to any colour you like.
