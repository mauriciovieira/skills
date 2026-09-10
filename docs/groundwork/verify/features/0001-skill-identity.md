# Skill identity

An agent that invokes a skill by name gets that skill.

## What exists today

Each skill is a directory under `skills/<bucket>/<name>/` containing `SKILL.md`, whose
frontmatter carries `name:` and `description:`. Everything else in the repository - both
READMEs, `plugin.json`, cross-references between skills - addresses the skill by its
directory name. The frontmatter `name` is what the agent runtime loads it as.

When those two disagree, nothing errors. The skill installs, appears in listings, and fails
to resolve under the name every document uses for it.

## How a person gets here

Renaming a skill directory without editing its frontmatter, or the reverse. Both look
complete on their own.

## How an agent drives it

```
./control drive <skill>
./control prove <skill>
```

Observable outcome: the `identity` row reads `ok` with the resolved name, and `description`
reads `ok`. A mismatch prints both sides: `frontmatter says 'X', directory says 'Y'`.

## Known failure modes

Proven to fail, not assumed: setting `name: tdd-renamed` in `skills/engineering/tdd/SKILL.md`
produces `identity FAIL - frontmatter says 'tdd-renamed', directory says 'tdd'`.

The `description` check only asserts the line exists. Whether a description is good enough to
make the agent load the skill at the right moment is not mechanically checkable, and this
does not pretend to check it.
