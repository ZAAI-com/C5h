# C5h app icon candidates

C5h = **Coding for 5 hours.** Two rounds of seven candidates each, all rendered
at 1024×1024 PNG.

- **Round 1** (`00-contact-sheet.png`) — Time-and-window concepts (clocks,
  rings, hourglasses, dials, arcs).
- **Round 2** (`00-contact-sheet-round2.png`) — Coding-and-window concepts
  (terminal prompts, code braces, JSX tags, mini editors, file metaphors).

To regenerate:

```bash
swift run --package-path Tools/IconForge IconForge
```

The renderer (`Tools/IconForge`) uses Core Graphics directly so it produces
deterministic, raster-clean output.

## Round 1 — Time-only concepts

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

## Round 2 — Coding + 5 hours concepts

These lean into the literal meaning of the product name: **Coding for 5
hours.** Each pairs a recognisable code symbol with the 5h time signal.

### 8. Terminal Prompt — `08-terminal-prompt.png`
Dark editor with macOS traffic lights, monospace `> 5h` and a Claude-orange
cursor block, faint `c5h` shell label. Most direct dev-tool signal.

- **Strengths**: instantly reads as a CLI tool; orange cursor doubles as the
  brand accent; the only icon that names the product.
- **Risks**: small monospace text loses bite at 16×16; very saturated dev
  niche.

### 9. Brace Clock — `09-brace-clock.png`
Two huge `{` `}` curly braces flanking a small clock face with a 5-hour
wedge, on warm cream. Code + time fused in one symbol.

- **Strengths**: literal "coding × 5 hours"; warm cream stands out in a dock
  full of dark icons.
- **Risks**: the clock-inside-braces is the entire idea — no plan B if the
  metaphor doesn't click.

### 10. JSX Tag — `10-jsx-tag.png`
Self-closing `<5h/>` tag in bold white monospace on the Claude→Codex
gradient. Modern web-dev typography.

- **Strengths**: highly distinctive; gradient ties to the in-app brand;
  scales beautifully.
- **Risks**: JSX angle-brackets are web-flavoured (this app doesn't care
  about the language).

### 11. Code Editor — `11-code-editor.png`
Mini macOS code-editor window: traffic lights, "5h.swift" title, syntax-
highlighted code rectangles on numbered lines, and a circular 5h progress
dial in the bottom-right.

- **Strengths**: the most literal "coding for 5h"; very rich at full
  resolution.
- **Risks**: highest detail in the set — risks turning into a colour blob
  at 16×16.

### 12. 5h.swift — `12-filename.png`
Document silhouette with folded corner; "5h" in big Claude orange letters
and ".swift" in monospace below. File-as-icon metaphor.

- **Strengths**: tells the whole story; recognisable at any size; warm
  cream chrome.
- **Risks**: locks the brand to Swift specifically; the language tag may
  feel narrow.

### 13. Block Comment — `13-block-comment.png`
Universal-language block comment `/* 5h */` on a dark editor field, with
the `5h` accented in Claude orange and the comment markers in dim slate.

- **Strengths**: language-agnostic; minimal and confident; orange centre
  is the focal point.
- **Risks**: low silhouette interest at small sizes — the comment markers
  blur into the background.

### 14. Caret Play — `14-caret-play.png`
Triangular play caret + bold `5h` on the Claude→Codex gradient. Action-
oriented: *start the session.*

- **Strengths**: highest call-to-action energy; reads instantly as "begin";
  gradient ties to the brand.
- **Risks**: media-player feel; not specifically a coding tool.

---

## How to pick a winner

When you've decided, drop the chosen 1024×1024 PNG into:

```
C5h/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

…then update the `AppIcon.appiconset/Contents.json` to reference it (or run
`sips` to generate the smaller scales). The IconForge tool can be extended to
output the full appiconset; ask and it'll be wired up.
