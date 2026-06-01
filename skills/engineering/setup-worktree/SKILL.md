---
name: setup-worktree
description: Use when the user is in a linked git worktree and needs to bootstrap it from the main repo - symlinks language-agnostic dependency directories (node_modules, .venv, vendor, target, deps) and copies env files. Trigger phrases include "setup worktree", "/setup-worktree", "bootstrap worktree", or when the user just created a worktree and wants to install/run dev.
---

# setup-worktree

Bootstrap a linked git worktree from its main repo without re-installing dependencies. Language-agnostic: detects manifests (`package.json`, `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py`, `Gemfile`, `go.mod`, `Cargo.toml`, `composer.json`, `mix.exs`) and symlinks the matching deps dir from main if it exists.

## What it does

For each manifest found in the main repo, symlinks the corresponding deps dir into the worktree at the same relative path:

| Manifest | Deps dir candidates (first existing wins) |
|---|---|
| `package.json` | `node_modules` |
| `pyproject.toml` / `requirements.txt` / `Pipfile` / `setup.py` | `.venv`, `venv`, `env` |
| `Gemfile` | `vendor/bundle`, `.bundle` |
| `go.mod` | `vendor` |
| `Cargo.toml` | `target` |
| `composer.json` | `vendor` |
| `mix.exs` | `deps`, `_build` |

Env files copied (not linked, since they may diverge per branch): `.env`, `.env.local`, `.env.development`, `.env.test`.

## When to use

- User just ran `git worktree add .worktrees/<name>` and wants to start working without `npm ci` / `bundle install` / `pip install` again.
- User says "set up the worktree", "/setup-worktree", "bootstrap this worktree".
- Worktree is missing `.env` / `node_modules` / `.venv` / `vendor` and the main repo has them.

## When NOT to use

- Inside the main repo (script refuses — exits with error).
- When deps in main repo are stale or for a different branch's lockfile. In that case, install fresh in the worktree instead.
- For deps that the language prefers per-checkout (e.g., Rust's `target` may bloat — user can rm the symlink if they want isolation).

## How to invoke

```bash
~/.claude/skills/setup-worktree/setup-worktree.sh
```

Or via slash command: `/setup-worktree` (alias defined in `~/.claude/commands/setup-worktree.md`).

Run from inside the worktree (any subdirectory works — script resolves the worktree root via `git rev-parse --show-toplevel`).

## Safety

- Refuses to run outside a linked worktree (compares `git rev-parse --git-common-dir` against `--git-dir`).
- Never overwrites existing files or symlinks in the worktree.
- Skips deps dirs that don't exist in main (no broken symlinks).
- Idempotent: rerunning is a no-op when everything is already linked/copied.

## Repo-level Makefile integration

Repos that previously had a hand-rolled `setup-worktree` Make target should replace it with a thin wrapper:

```makefile
setup-worktree:
	@~/.claude/skills/setup-worktree/setup-worktree.sh
```

If the script isn't installed (other contributors not using this skill), the Make target should fall back to a clear error message pointing at the skill repo.

## Common mistakes

- **Running from main repo:** Script refuses with `not in a linked worktree`. Run from inside `.worktrees/<name>/` instead.
- **Expecting deps to be copied:** They're symlinked. Modifying them affects main. To isolate, replace the symlink with a real install.
- **Stale lockfile:** Symlinked `node_modules` reflects main's last install. If your branch changes `package.json`, run a fresh install in the worktree (which will replace the symlink with a real dir).
