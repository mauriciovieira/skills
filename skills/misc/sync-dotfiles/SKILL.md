---
name: sync-dotfiles
description: Sync your local agent/editor config (e.g. ~/.claude/, ~/.cursor/) into a dotfiles git repo, show the diff, and prompt for a commit. Use when the user asks to "sync dotfiles", "push my claude/cursor config", "save my editor settings to dotfiles", or after editing global config that should propagate to other machines.
---

# sync-dotfiles

Propagate intentional edits to your local agent/editor config back into a
**dotfiles git repo** so they ship to your other machines.

This skill is config-agnostic: it asks you where your dotfiles repo lives and
which sources to sync. It never hardcodes a private path.

## Core safety model

- **Only copy when BOTH source and destination already exist.** This prevents
  introducing new tracked files implicitly — adding a *new* tracked file is a
  deliberate, manual `cp`, not a side effect of sync.
- **Never `git push`** and **never `git commit --amend`** — local commit only.
- **Never write outside the dotfiles repo.**
- Skip per-machine churn files (e.g. `~/.claude/settings.local.json`).

## Step 1 — Locate the dotfiles repo

Ask the user for their dotfiles repo path if you don't already know it.

```
Where is your dotfiles repo? (absolute path, e.g. ~/dotfiles or
~/Repositories/<you>/dotfiles)
```

Set `DOTFILES="<their answer>"`. If `[ ! -d "$DOTFILES/.git" ]`, report that
it's not a git repo and stop.

> Tip: if the user syncs often, suggest they record the path in their project
> or global `CLAUDE.md` so this skill can skip the question next time.

## Step 2 — Agree on the sync list

Ask which sources to sync (offer the common defaults; let them add/remove).
Each entry is a **source → destination** pair where the destination is a path
*inside* `$DOTFILES`. Common defaults:

| Source (local) | Destination (in repo) | Copy mode |
|---|---|---|
| `~/.claude/CLAUDE.md` | `<repo>/.claude/CLAUDE.md` | file |
| `~/.claude/settings.json` | `<repo>/.claude/settings.json` | file |
| `~/.claude/skills/` | `<repo>/.claude/skills/` | `rsync -aL --delete` |
| `~/.cursor/cli-config.json` | `<repo>/.cursor/cli-config.json` | file |
| `~/.cursor/mcp.json` | `<repo>/.cursor/mcp.json` | file |
| `~/.cursor/rules/` | `<repo>/.cursor/rules/` | `rsync -a --delete` |

Confirm the destination layout matches how the user's repo is actually
organised (some keep config at the repo root, others under a `dotfiles/` or
`.config/` subdir). Adjust the destination paths to match before copying.

Exclusions to confirm with the user:
- `~/.claude/settings.local.json` — per-machine accept-list churn, skip.
- Any local-only skill that symlinks to a sibling repo not present on every
  machine — exclude from the `rsync` (e.g. `--exclude='browser-harness/'`).

## Step 3 — Verify a clean baseline for the tracked paths

```bash
git -C "$DOTFILES" status --porcelain <destination paths from the sync list>
```

If non-empty, show the user and ask: continue, stash, or abort. Default abort.

## Step 4 — Copy (only when both source and destination exist)

For each **file** pair:

```bash
if [ -f "$SRC" ] && [ -f "$DST" ]; then
    cp -f "$SRC" "$DST"
fi
```

For each **directory** pair (use `-L` to dereference symlinks so symlinked
skills/configs are captured as real files and the repo stays portable):

```bash
if [ -d "$SRC" ] && [ -d "$DST" ]; then
    rsync -aL --delete --exclude='<local-only entries>' "$SRC" "$DST"
fi
```

Never copy excluded files (e.g. `settings.local.json`).

## Step 5 — Show the diff

```bash
git -C "$DOTFILES" diff --stat <destination paths>
git -C "$DOTFILES" diff <destination paths>
```

If the diff is empty, report "no changes to sync" and stop.

## Step 6 — Draft a commit message and confirm

Draft a **Conventional Commits** message from what changed. Examples:

- `chore(claude): update settings.json — add pnpm permission`
- `chore(cursor): sync mcp.json from machine`
- `chore(claude,cursor): propagate hook updates`

**Show the user the proposed message. Ask: approve, edit, or abort.**

## Step 7 — Commit (on approval only)

```bash
git -C "$DOTFILES" add <destination paths>
git -C "$DOTFILES" commit -m "<approved message>"
git -C "$DOTFILES" rev-parse --short HEAD
```

Report the commit SHA. **Do NOT** `git push`. **Do NOT** `--amend`.

## Hard rules

- Never touch per-machine churn files (`settings.local.json` and similar).
- Never `git push`. Never `--amend`.
- Never write to any path outside `$DOTFILES`.
- Only copy when both source and destination already exist. Adding a new
  tracked file requires an explicit, deliberate `cp` — this skill will not
  introduce new tracked files on its own.
