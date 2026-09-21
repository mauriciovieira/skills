# Skill-owned tests

A skill that ships a test still passes it after the skill is edited.

## What exists today

Three skills ship an executable test. `grilling/test/run.sh` is a three-line wrapper around
`test_grill_stop.py`, 34 assertions over synthetic transcripts covering the Stop hook the
skill ships in `grilling/hooks/`.

`review-with-jev/test/run.sh` is 147 assertions over `evidence-guard.sh`, the deterministic path
filter that decides what leaves the machine for a third-party API, plus drift checks asserting
that `SKILL.md` still names the guard, the env var and its policy version.

Some of those assertions read the guard's **exit code** rather than its printed lines, which is
the part worth stating rather than counting. Two of the eight holes closed in #26 and #27 did
not leak one file: they disarmed the gate, so the exit code reported clean while a secret sat
in the list. A caller reading only that code could not tell "nothing suspicious" from "there
was a secret and I looked away", and a test comparing only stdout passes with the gate wide
open. The suite also asks the prefixed-and-suffixed question of every credential family rather
than of one, after a rule tested only at its literal spelling shipped as an exact match while
95 assertions stayed green.

`ansible-kamal/test/render.sh` is 28 assertions over the renderer, which writes a deploy tree
into somebody else's project. It renders into a temp directory in both `ENV_MODE`s and asserts
that no placeholder and no secret-manager-specific string leaks into the output, that the
generated scripts parse, that `make` expands the recipes to the real command, and that every
`SECRET_CMD` form the contract forbids is refused at render time - a relative path, a leading
`~`, a `$` - while an absolute one is still accepted.

`control` runs any `*.sh` under a `test` path inside the skill's directory, so a further skill
that grows a test is picked up with no change here - which is what happened with `grilling`,
and why its Python test ships behind a `run.sh` wrapper rather than teaching `control` a
second language.

## How a person gets here

Editing a `SKILL.md` and reading the green check on the pull request as confirmation. The
review workflow reviews the diff; it does not run anything.

## How an agent drives it

```
./control drive review-with-jev
./control drive grilling
./control drive ansible-kamal
```

Observable outcome: `own-tests ok  run.sh: 147/147 OK`, `own-tests ok  run.sh: 34/34 OK`, and
`own-tests ok  render.sh: 28/28 OK`. Skills with no test read `skip  none`, which is a fact,
not a pass.

## Known failure modes

Proven to fail: dropping the `(?<![A-Za-z_])` lookbehind from the hook's Bash write pattern
fails assertion 24 of `grilling/test/run.sh`, and dropping its cross-session branch fails
assertion 29. Also proven: removing the `set -f` line from
`ansible-kamal/templates/scripts/kamal-deploy.sh` fails `render.sh` twice, once per
`ENV_MODE`, with `both generated scripts disable globbing`.

`review-with-jev` was mutation-checked one hole at a time, because reverting several together
hides a useless assertion behind a working one. Turning off `shopt -s nocasematch` fails 11,
including `uppercase secret exits 2`. Re-anchoring the SSH key patterns fails 3, `.pgpass` and
`.htpasswd` fail 5, and the `.env` family fails 5. Removing the path normaliser fails 4,
including an exit-code check. Restoring the two dash defences one at a time fails 1 each and
both together fail 5 - which is the pair worth keeping, since either alone still leaks a case
the other misses.

The number in this file has now been wrong twice, both times because a PR grew the test and
left the map behind. A feature map that misstates its own coverage is worse than no map, so
the number and the prose move with the suite or the suite is not done.

41 of 44 skills have no test at all. This check does not pretend otherwise; it reports `skip`,
and a `skip` is not evidence of anything.
