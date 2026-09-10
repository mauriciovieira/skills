# Private skills stay private

A skill in `personal/` or `in-progress/` is not published to anyone.

## What exists today

`CLAUDE.md` says skills in those two buckets must NOT appear in the top-level `README.md` or
in `plugin.json`. This is the inverse of registration and the more consequential half: a
missing registration makes a skill invisible, while an accidental one publishes something
that was deliberately held back - a draft, or something tied to a private setup.

`mauriciovieira/skills` is a public repository, so the blast radius is the internet.

## How a person gets here

Promoting a skill by moving it into `engineering/` and reverting the move, but not the
registration. Or adding a skill to the indexes first and deciding later where it lives.

## How an agent drives it

```
./control drive <skill>
./control drive all
```

Observable outcome: for a skill in an unpublished bucket, `readme-top` and `plugin-json` read
`ok  unpublished, correctly absent`. A leak reads
`FAIL - <bucket>/ skill is listed in README.md`.

## Known failure modes

This is the check most worth having and the least likely to be caught by review, because the
leak is a line added to an index file, not a change to the skill itself. Reviewing the skill's
own diff cannot see it.

Not checked: whether a skill is in the right bucket at all. Nothing mechanical can tell that a
skill *should* have been private.
