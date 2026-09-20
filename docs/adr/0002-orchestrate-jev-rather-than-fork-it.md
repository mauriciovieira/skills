# Orchestrate the Jev MCP tool rather than fork it

`review-with-jev` drives the `jev_review` MCP tool from
[NiazMorshed2007/jev-review](https://github.com/NiazMorshed2007/jev-review) without modifying
it. The upstream plugin bundles its own skill, also called `jev-review`, whose stated shape is
"a repeated scalar feedback loop ... rescore with the previous evaluation until important
metrics improve". Ours is the opposite discipline on the same tool, so it ships as a separate
skill under a separate name instead of a fork.

That buys the thing a fork would cost: upstream stays updateable, and the two skills coexist
rather than one shadowing the other. The name follows the house `<verb>-with-<thing>` pattern
(`grill-with-docs`, `babysit-with-claude-review`), which also happens to be exactly what a
person types - "review this with Jev".

## What we took, and from where

The `SKILL.md` carries the full list under **Provenance**. The two decisions worth recording
separately:

**We deliberately override upstream's severity band.** Upstream derives severity from the score
alone (`<= 3` high, `<= 5` medium, else low). A score alone cannot separate a cosmetic nit from
a shipped authorization hole, so `review-with-jev-policy@1` classifies on score *plus*
confidence, dimension weight, deterministic evidence, regression against the previous run, blast
radius, and whether the behaviour is externally observable. The policy is named and versioned,
borrowing that habit from devagrawal09's workflows, so a change to it is visible rather than
silent.

**The router is our own design, not an adoption.** The brief that prompted this skill framed it
as adopting a staged router from `devagrawal09/jev-review` and `devagrawal09/jev-code`. Neither
repo has one: the first asks all five of its dimensions on every file, and the second routes a
user *request* to a workflow, never a diff to a subset of dimensions. `jev_review` likewise asks
all 57 of its questions (3 per metric x 19) on every call, with no subset parameter. So routing
here cannot buy a cheaper or narrower call. It buys evidence selection, attention, and the
decision not to call at all. Saying otherwise would invent a lineage.

## Why the evidence guard is a script

The upstream server performs no redaction, no path exclusion and no size capping - it sends
exactly what the caller passes. Every privacy guarantee therefore lives in the caller. A prose
rule saying "never send `.env`" fails silently, and the blast radius is a third-party API, so
the exclusion list is `evidence-guard.sh` with a test rather than a paragraph. Exclusions are
printed with a reason instead of dropped, because a silent drop is indistinguishable from an
oversight.

This makes `review-with-jev` the third skill in the repo to ship its own test, and the second
deliberate divergence from the `mattpocock/skills` mirror after `grilling`.
