# Skill registration

A skill in a published bucket can be found by someone who does not already know it exists.

## What exists today

`CLAUDE.md` requires every skill in `engineering/`, `productivity/` or `misc/` to appear in
three places: the top-level `README.md`, its bucket's `README.md`, and `.claude-plugin/plugin.json`.
The two READMEs are how a person finds it; `plugin.json` is how the plugin installer finds it.

Nothing enforced this before. A skill missing from `plugin.json` is committed, reviewed,
merged, and simply never installs - there is no build to fail and no test to go red.

## How a person gets here

Adding a skill and updating two of the three places. The odd one out is usually
`plugin.json`, because the READMEs are the ones you are already looking at.

## How an agent drives it

```
./control drive <skill>
./control drive all
```

Observable outcome: `readme-top`, `readme-bucket` and `plugin-json` all read `ok`. Each
failure names the file it looked in.

## Known failure modes

Proven to fail: removing `./skills/engineering/tdd` from `plugin.json` produces
`plugin-json FAIL - ./skills/engineering/tdd missing from plugin.json`.

The README checks match the exact markdown link `[<name>](./path/to/SKILL.md)`, so a skill
mentioned in prose but not linked correctly reads as missing. That is deliberate -
`CLAUDE.md` requires the link, not a mention.

An earlier version of this check reported every skill as unregistered, because the
parentheses of the markdown link were left unescaped in an ERE pattern and were read as
grouping. It was caught by running the check rather than by reading it.
