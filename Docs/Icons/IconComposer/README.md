# C5h × Icon Composer

Apple's **Icon Composer** ships with Xcode 26 at:

```bash
/Applications/Xcode.app/Contents/Applications/Icon Composer.app
```

The app icon is now built as an Icon Composer document at:

```txt
C5h/Resources/AppIcon.icon
```

Xcode compiles that `.icon` package directly during the asset catalog step and
emits the final `AppIcon.icns` for the macOS app.

## What's in this folder

This folder keeps reusable Icon Composer input layers from earlier iterations.
They are not the active app icon.

The active app icon source lives in `C5h/Resources/AppIcon.icon` and uses the
orange Liquid Glass `<C5h>` calendar image as a single Icon Composer layer.

The legacy layer assets here are 2048×2048 PNG foreground layers, all
black-on-transparent:

| File | Foreground glyph |
|---|---|
| `c5h-foreground-at.png`      | **`@C5h`** — your pick from round 4 |
| `c5h-foreground-jsx.png`     | `<C5h/>` |
| `c5h-foreground-braces.png`  | `{C5h}` |
| `c5h-foreground-call.png`    | `C5h()` |
| `c5h-foreground-c5h.png`     | `C5h` (no syntax framing) |

You can still drag these into Icon Composer for alternate concepts.

## Active document

The active `AppIcon.icon` package contains:

```txt
AppIcon.icon/
├─ icon.json
└─ Assets/
   └─ C5h-LiquidGlass.png
```

`icon.json` enables the Icon Composer renderer with:

- `fill: automatic`
- neutral shadow at `0.5`
- `specular: true`
- `translucency` enabled at `0.5`
- `supported-platforms.squares: ["macOS"]`

## Open in Icon Composer

```bash
open "/Applications/Xcode.app/Contents/Applications/Icon Composer.app" \
  "C5h/Resources/AppIcon.icon"
```

## Verify with `ictool`

Render a 1024×1024 preview from the committed `.icon` package:

```bash
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

"$ICTOOL" C5h/Resources/AppIcon.icon \
  --export-image \
  --output-file /tmp/C5h-iconcomposer-preview.png \
  --platform macOS --rendition Default \
  --width 1024 --height 1024 --scale 1
```

## Regenerating the foreground layers

```bash
swift run --package-path Tools/IconForge IconForge
```

The `exportIconComposerAssets` function in
`Tools/IconForge/Sources/IconForge/main.swift` produces all five layers.
Edit it to add more variants or change typography.
