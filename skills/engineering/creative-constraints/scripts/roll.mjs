#!/usr/bin/env node
// Roll a fresh design-constraint set. Real entropy on purpose:
// an LLM asked to "pick randomly" converges on the same choices every
// time, which is the sameness we're fighting. Let the machine roll.
import { randomInt } from "node:crypto";

const AXES = {
  "Layout primitive": [
    "diagonal",
    "single-column scroll",
    "split-screen",
    "broken-grid",
    "radial",
    "full-bleed type",
  ],
  Type: [
    "one typeface only",
    "serif display + sans body",
    "variable-weight extremes",
    "oversized numerals",
  ],
  Color: [
    "monochrome + 1 accent",
    "duotone",
    "high-contrast B/W",
    "single saturated hero color",
  ],
  "Signature move": [
    "oversized footer",
    "sideways nav",
    "text-as-image",
    "no visible nav",
  ],
};

const pick = (arr) => arr[randomInt(arr.length)];
const roll = Object.fromEntries(
  Object.entries(AXES).map(([axis, opts]) => [axis, pick(opts)]),
);

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(roll, null, 2));
} else {
  const w = Math.max(...Object.keys(roll).map((k) => k.length));
  console.log("\n  🎲 Constraint set for this session\n");
  for (const [axis, choice] of Object.entries(roll)) {
    console.log(`  ${axis.padEnd(w)}  →  ${choice}`);
  }
  console.log("\n  All four are binding. Honor every one.\n");
}
