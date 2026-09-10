# Skill-owned tests

A skill that ships a test still passes it after the skill is edited.

## What exists today

One skill ships an executable test: `babysit-with-claude-review/test/verdict.sh`, 11
assertions over trimmed real run logs, plus drift checks asserting that the gate conditions
it tests still appear in `SKILL.md`. Editing the prose without the test, or the test without
the prose, fails it.

Nothing ran it. Not CI, not the review workflow, not a pre-commit hook. It passed or failed
only when someone remembered to type `bash test/verdict.sh` - which, on the change that
prompted this whole asset, nobody did until after the pull request was open.

`control` runs any `*.sh` under a `test` path inside the skill's directory, so a second skill
that grows a test is picked up with no change here.

## How a person gets here

Editing a `SKILL.md` and reading the green check on the pull request as confirmation. The
review workflow reviews the diff; it does not run anything.

## How an agent drives it

```
./control drive babysit-with-claude-review
```

Observable outcome: `own-tests ok  verdict.sh: all checks passed`. Skills with no test read
`skip  none`, which is a fact, not a pass.

## Known failure modes

Proven to fail: changing the clean-verdict pattern in `SKILL.md` without touching the test
produces `own-tests FAIL - drift check: condition missing from SKILL.md`.

Appending `exit 1` to the end of `verdict.sh` does NOT fail it - the script ends in
`exit "$fail"`, so anything after that is unreachable. Worth knowing before trusting a
hand-rolled check of the checker.

44 of 45 skills have no test at all. This check does not pretend otherwise; it reports `skip`,
and a `skip` is not evidence of anything.
