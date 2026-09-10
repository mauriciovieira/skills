# Verifying this project

How to see this repository actually working. Written for an agent to execute and for a person
to read, and kept true by `groundwork:verify --sync`.

`control` is the entry point for all of it. Run `./control --help` for the full list.

## What "working" means here

This repository ships documents, not a running service, so there is nothing to boot and
nothing to click. A skill works when an agent can find it, load it under the name everything
else calls it by, and - where the skill ships one - its own test still passes.

That makes the contract in `CLAUDE.md` the thing worth verifying, and nothing checked it
until now. It is exactly the kind of contract that rots quietly: a skill added without its
`plugin.json` entry is invisible, and a private skill added to `README.md` is published to
the world. Neither shows up as a broken build, because there is no build.

## Launch

Nothing to launch. The command exists because the contract says it must, and says so:

```
./control launch
```

## Doctor

Check the environment before trusting any result. A failed check and a tool that is not
installed are different outcomes and must never be reported alike.

```
./control doctor
```

Checks `python3`, `bash` and `git` are present, that `plugin.json` exists and parses, and
reports whether `deslop` is available (its absence downgrades one check, it does not fail).

## Drive

Run every structural check for one skill, or sweep them all:

```
./control drive babysit-with-claude-review
./control drive all
./control drive all --json
```

The checks and what each one is defending are in [features/](features/README.md).

## Prove

Same checks, with the output captured:

```
./control prove <skill>
```

Evidence lands in `evidence/`, which is gitignored scratch. The proof of record is the
output itself pasted into the issue or PR - a path into `evidence/` means nothing to anyone
on another machine or in a later session.

## Clean up

```
./control clean
```

Removes `evidence/`. There is no running state to stop.

## Conventions

- Anything that destroys or mutates state takes `--dry-run` and prints what it would do.
- Every subcommand supports `--json`.
- Errors say what failed, what was expected, and what to try next.
- Exit code is `1` when any check fails, so this drops into CI unchanged.
