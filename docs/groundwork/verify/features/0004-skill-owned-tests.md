# Skill-owned tests

A skill that ships a test still passes it after the skill is edited.

## What exists today

Three skills ship an executable test. `babysit-with-claude-review/test/verdict.sh` is 11
assertions over trimmed real run logs, plus drift checks asserting that the gate conditions
it tests still appear in `SKILL.md`. Editing the prose without the test, or the test without
the prose, fails it. `grilling/test/run.sh` is a three-line wrapper around
`test_grill_stop.py`, 34 assertions over synthetic transcripts covering the Stop hook the
skill ships in `grilling/hooks/`.

Nothing ran it. Not CI, not the review workflow, not a pre-commit hook. It passed or failed
only when someone remembered to type `bash test/verdict.sh` - which, on the change that
prompted this whole asset, nobody did until after the pull request was open.

`review-with-jev/test/run.sh` is 39 assertions over `evidence-guard.sh`, the deterministic path
filter that decides what leaves the machine for a third-party API, plus drift checks asserting
that `SKILL.md` still names the guard, the env var and its policy version.

`control` runs any `*.sh` under a `test` path inside the skill's directory, so a further skill
that grows a test is picked up with no change here - which is what happened with `grilling`,
and why its Python test ships behind a `run.sh` wrapper rather than teaching `control` a
second language.

## How a person gets here

Editing a `SKILL.md` and reading the green check on the pull request as confirmation. The
review workflow reviews the diff; it does not run anything.

## How an agent drives it

```
./control drive babysit-with-claude-review
./control drive grilling
```

Observable outcome: `own-tests ok  verdict.sh: all checks passed`, and
`own-tests ok  run.sh: 34/34 OK`. Skills with no test read `skip  none`, which is a fact,
not a pass.

## Known failure modes

Proven to fail: changing the clean-verdict pattern in `SKILL.md` without touching the test
produces `own-tests FAIL - drift check: condition missing from SKILL.md`. Also proven:
dropping the `(?<![A-Za-z_])` lookbehind from the hook's Bash write pattern fails assertion
24 of `run.sh`, and dropping its cross-session branch fails assertion 29.

Appending `exit 1` to the end of `verdict.sh` does NOT fail it - the script ends in
`exit "$fail"`, so anything after that is unreachable. Worth knowing before trusting a
hand-rolled check of the checker.

42 of 45 skills have no test at all. This check does not pretend otherwise; it reports `skip`,
and a `skip` is not evidence of anything.
