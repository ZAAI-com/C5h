# C5h app icon candidates

Seven distinct concepts rendered at 1024×1024 PNG. Open `00-contact-sheet.png`
for a side-by-side overview, or browse the individual files below.

To regenerate:

```bash
swift run --package-path Tools/IconForge IconForge
```

The renderer (`Tools/IconForge`) uses Core Graphics directly so it produces
deterministic, raster-clean output.

## Candidates

### 1. Wedge Clock — `01-wedge-clock.png`
Warm orange squircle with a white clock face and a bold 5-hour wedge sweeping
from 12 to 5. Hands point at 5. Most literal: *"5 hours starts now."*

- **Strengths**: instantly readable; brand-orange dominant; tells the whole
  story in one glyph.
- **Risks**: clock metaphor is generic; doesn't hint at the dual-provider
  story.

### 2. Activity Rings — `02-activity-rings.png`
Apple-Watch-style concentric rings: outer Claude-orange + inner Codex-blue,
each filled 5/24 of the way (the share of a day a 5-hour window represents),
on a deep navy field with `5h` in the centre.

- **Strengths**: native macOS feel; encodes both providers; energetic.
- **Risks**: leans on Apple's visual language; might read as "fitness app."

### 3. Stacked Bars — `03-stacked-bars.png`
Two horizontal lanes (Claude orange, Codex blue) with narrow translucent
"planned" bars and wide solid "actual" bars on a cream gridded field —
literally the calendar UI miniaturised.

- **Strengths**: unique to this product; reflects the in-app visualization;
  understated.
- **Risks**: low contrast at 16×16; least dramatic of the seven.

### 4. Numeral 5h — `04-numeral-5h.png`
Bold white **5h** on a vertical Claude-orange → Codex-blue gradient. Pure
typographic confidence.

- **Strengths**: highly memorable; works at any size; the gradient encodes both
  providers without forcing the metaphor.
- **Risks**: relies on type quality; the slightly diagonal gradient is the
  whole personality.

### 5. Hourglass Split — `05-hourglass-split.png`
Dark navy hourglass on warm cream; sand is split orange (Claude) above and
blue (Codex) below, with a falling stream that gradients between them.

- **Strengths**: rich metaphor (time + two providers); cream warmth differs
  from the rest of the macOS dock.
- **Risks**: skeuomorphic; the hourglass icon convention is widely overused
  for "loading."

### 6. Compass Dial — `06-compass-dial.png`
Tactical 24-tick navigation dial on a deep navy field with a Claude-orange
5-hour arc and faint crosshairs. `5h` in the centre.

- **Strengths**: serious productivity-tool aesthetic (Linear, Things-style);
  the only dark icon in the set; precise.
- **Risks**: small details lose at 16×16; could feel cold next to friendlier
  apps in the dock.

### 7. Sunrise Arc — `07-sunrise-arc.png`
Dawn-to-dusk vertical gradient with a dotted white arc connecting a yellow
sun (start) to a crescent moon (end), plus a `5h` label. The arc represents
the focused window.

- **Strengths**: poetic, evocative of "deep work"; differentiated palette;
  warm.
- **Risks**: less obviously a tool; reads more like a wellness/journaling
  app.

---

## How to pick a winner

When you've decided, drop the chosen 1024×1024 PNG into:

```
C5h/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

…then update the `AppIcon.appiconset/Contents.json` to reference it (or run
`sips` to generate the smaller scales). The IconForge tool can be extended to
output the full appiconset; ask and it'll be wired up.
