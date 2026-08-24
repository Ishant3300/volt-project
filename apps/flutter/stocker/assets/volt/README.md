# Volt brand assets

| File | Purpose |
|---|---|
| `logo.svg` | In-app logo (splash + login). Transparent background, matches the `Subtract.svg` convention used by Apex. |
| `icon_source.svg` | Source for the launcher icon — the brand mark on an opaque white square, inset to 62% so there's a white margin. Used for iOS and the legacy pre-API-26 Android icon. |
| `adaptive_foreground_source.svg` | Source for the Android adaptive-icon foreground. Inset to 46% of the canvas — see the sizing note below. |
| `icon.png` | 1024×1024 launcher icon, generated from `icon_source.svg`. |
| `adaptive_icon_foreground.png` | 1024×1024 adaptive foreground, generated from `adaptive_foreground_source.svg`. |

## Adaptive-icon sizing (why the mark looks small in the source)

Android renders the adaptive foreground on a **108dp** canvas but only ever shows
the centre **72dp** — the outer ring is reserve for masking and parallax. So
content scaled to X% of the source renders at **X / 66.7%** of what the user
actually sees.

The brand mark is 368 units wide (it spans 72..440 of the original 512 box), and
the viewBox is expanded to 800 units:

| | value |
|---|---|
| mark ÷ canvas | 368 / 800 = **46%** |
| visible area | 66.7% × 800 = 533 units |
| mark ÷ **visible** | 368 / 533 = **~69%** |

~69% of the visible area is comfortable breathing room under every mask (circle,
squircle, rounded square).

> A first attempt used an 800→588 canvas, i.e. 63% of the canvas but **94% of the
> visible area**, which made the icon look edge-to-edge on the home screen. If
> you rescale the mark, always check the ratio against the *visible* 72dp — not
> the full canvas.

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
