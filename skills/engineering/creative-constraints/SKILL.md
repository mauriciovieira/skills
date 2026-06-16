---
name: creative-constraints
description: Roll a fresh, machine-random set of binding design constraints before any visual design work, so no two sessions converge on the same "safe" layout. Use when starting any web/UI design, landing page, hero, portfolio, or redesign — and especially when the user says designs feel samey, generic, templated, or "like every other Claude page."
---

# Creative Constraints

Forces design divergence by rolling random constraints **before** any markup is
written. The model's default instinct is the statistical average of all websites
(status pills, soft-rounded cards, centered hero + subtitle, muted slate). This
skill replaces that average with a fresh, opinionated constraint set each run.

## Workflow

1. **Roll.** Run the dice script — do not pick the constraints yourself, the
   entropy is the whole point:

   ```sh
   node ~/.claude/skills/creative-constraints/scripts/roll.mjs
   ```

   It picks one option from each of four binding axes:
   - **Layout primitive** — diagonal · single-column scroll · split-screen · broken-grid · radial · full-bleed type
   - **Type** — one typeface only · serif display + sans body · variable-weight extremes · oversized numerals
   - **Color** — monochrome + 1 accent · duotone · high-contrast B/W · single saturated hero color
   - **Signature move** — oversized footer · sideways nav · text-as-image · no visible nav

2. **Present for approval.** Show the rolled set verbatim, plus **one line per
   axis** on how you'll honor it for *this specific* page/brand. Then ask the
   user to approve, or re-roll any single axis they dislike. Do not write code
   before approval.

3. **Design within the constraints.** All four are binding — not suggestions,
   not "accents." If a constraint feels awkward, that friction is the source of
   the novelty; solve it, don't soften it.

## Banned defaults

Regardless of the roll, never reach for these house-style tells:

- status-pill / badge with a colored dot
- monospace micro-labels
- soft drop-shadows on evenly-rounded cards in a grid
- centered hero with a subtitle
- muted sage / slate / zinc as the base palette

If you catch yourself adding one, stop and find another solution.

## Notes

- **Re-roll, don't override.** If the user wants a different layout primitive,
  re-run with the script — keep the choice machine-made.
- One axis at a time is fine: `roll.mjs --json` emits JSON if you want to swap a
  single value programmatically.
- This is a *flexible* skill in spirit but the four rolled constraints are
  *rigid* once approved. Don't quietly drop one mid-build.
