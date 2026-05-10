# C5h × Icon Composer

Apple's **Icon Composer** (ships with Xcode 26, found at
`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`) is the
right tool for the new layered Liquid Glass icons. It outputs a single
`.icon` document that Xcode 26 reads natively, generating every platform
size + light/dark/tinted variant from one source — and applies Apple's real
gloss/specular/depth shaders that I can't fake in Core Graphics.

`ictool` (the bundled CLI inside the app) only **exports** existing
documents. Authoring still happens in the GUI for now, but my job is to
hand you the cleanest possible inputs so the GUI step is trivial.

## What's in this folder

Five 2048×2048 PNG **foreground layers**, all black-on-transparent (the
convention Icon Composer expects — it recolors the layer per style):

| File | Foreground glyph |
|---|---|
| `c5h-foreground-at.png`      | **`@C5h`** — your pick from round 4 |
| `c5h-foreground-jsx.png`     | `<C5h/>` |
| `c5h-foreground-braces.png`  | `{C5h}` |
| `c5h-foreground-call.png`    | `C5h()` |
| `c5h-foreground-c5h.png`     | `C5h` (no syntax framing) |

Pick one of these for the foreground layer in Icon Composer.

## Background recipe (matches round 4 / icon #20)

Icon Composer's background controls let you specify a **linear gradient**.
Use these colours for the warm Swift-orange you liked:

```
top-left      → bottom-right
#F5823C       → #D64E20
```

In RGB (0–255): `(245, 130, 60) → (214, 78, 32)`.

Add a soft **white highlight** at roughly **30% from the left, 80% from the
top** at 22% opacity. Icon Composer's "Light Angle" control will give you
that effect; alternatively turn on the built-in **Specular Highlight**.

## Step-by-step

1. Open Icon Composer:

   ```bash
   open "/Applications/Xcode.app/Contents/Applications/Icon Composer.app"
   ```

2. **File → New** (or ⌘N). Pick the macOS / Multi-platform template.

3. **Drag** `c5h-foreground-at.png` (or any of the five) onto the canvas.
   Icon Composer adds it as a foreground layer.

4. With the foreground layer selected, set:
   - **Fill** → White
   - **Material** → Liquid Glass (or "Solid" for a flatter modern look)
   - **Shadow** → off (the warm background already has plenty of contrast)

5. Click the canvas background. In the Inspector:
   - **Style** → Linear Gradient
   - Stops: `#F5823C` (top-left) → `#D64E20` (bottom-right)
   - Optional: enable **Specular** for the soft top highlight

6. **File → Save** as `C5h.icon` somewhere convenient (e.g. inside
   `C5h/Resources/`).

7. In Xcode, drag `C5h.icon` into the project navigator. Update the target's
   **General → App Icon** dropdown to point at it. Xcode 26 handles every
   platform size + variant automatically.

## Verify with `ictool`

Once the document is saved, you can render preview PNGs from the CLI to
sanity-check it without re-opening the GUI:

```bash
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

# macOS Default
"$ICTOOL" /path/to/C5h.icon \
  --export-image \
  --output-file /tmp/C5h-default.png \
  --platform iOS --rendition Default \
  --width 1024 --height 1024 --scale 2

# Tinted Dark variant
"$ICTOOL" /path/to/C5h.icon \
  --export-image \
  --output-file /tmp/C5h-tinted.png \
  --platform iOS --rendition TintedDark \
  --width 1024 --height 1024 --scale 2 \
  --tint-color 0.85 --tint-strength 0.75
```

## Regenerating the foreground layers

```bash
swift run --package-path Tools/IconForge IconForge
```

The `exportIconComposerAssets` function in
`Tools/IconForge/Sources/IconForge/main.swift` produces all five layers.
Edit it to add more variants or change typography.
