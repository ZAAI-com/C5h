# Fresh C5h app icons

Generated May 9, 2026 with the built-in `image_gen` tool, then composed
deterministically with `compose.swift`.

This folder intentionally ignores the earlier `Docs/Icons` candidates.

## Output

- `raw/` contains the 12 untouched generated base images copied from
  `/Users/m/.codex/generated_images/019e0dfb-2049-7771-9f62-5a010a996f99/`.
- `final/` contains the 1024x1024 composed candidates.
- `review/01-final-contact-sheet.png` shows the full candidate set.
- `review/02-small-size-check.png` shows 256, 64, and 32 px legibility checks.

The installed app icon uses:

```txt
final/02-premium-bracket-prism-c5h.png
```

It was selected as the default because it best matches the requested
premium-abstract direction with a minimal deterministic `C5h` mark.

## Candidates

1. Premium focus core, no text.
2. Premium bracket prism with deterministic `C5h`.
3. Premium five-hour orbit, no text.
4. Premium code-time monogram with deterministic `{C5h}`.
5. Native scheduler glyph, no text.
6. Native compact timer with deterministic `C5h`.
7. Native provider-lane focus block, no text.
8. Native command timer with deterministic `> run`.
9. Developer editor glow, no text.
10. Developer terminal horizon with deterministic `C5h`.
11. Developer focused workspace, no text.
12. Developer run-session scene with deterministic `run(5h)`.

## Prompt themes

All generation prompts requested 1024x1024 macOS app icon base artwork,
full-square composition, no transparency, no readable generated text, no
watermarks, and no existing brand logos.

The 12 prompt directions were:

- Premium abstract focus core with five orbit segments and code-bracket geometry.
- Premium bracket prism around a central time crystal.
- Five-hour orbit symbol with luminous arc segments.
- Abstract code-time monogram base with timer wedge and nested brackets.
- Native scheduler glyph with a five-hour highlighted block.
- Compact timer tile with progress ring and command-key inspired center.
- Provider-lane focus block with orange and blue lanes.
- Command/timer symbol with run-button energy.
- Developer editor glow scene with abstract syntax bars.
- Terminal horizon scene with orange five-hour arc.
- Focused top-down code workspace scene.
- Run-session editor/terminal scene with a glowing command capsule.

## Regenerate composed assets

```bash
swift Docs/Icons/Fresh/compose.swift
```

The script writes the composed candidates, review sheets, and all required
macOS AppIcon PNG sizes.
