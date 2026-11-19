---
name: handoff
description: Write a complete handoff of the current session into the current directory as YYYYMMDDHHMM-handoff.md, so a new session (for example after switching Claude accounts) can pick up the work with /handin. Use when the user types "/handoff" or asks to hand off, pass on or save the session context. Takes no argument. Never commits or pushes the file.
disable-model-invocation: true
---

# handoff

Write everything a fresh session needs to continue this one without asking the user
to repeat anything. The reader is another Claude session with zero context. `/handin`
loads the file and deletes it.

**Invocation:** `/handoff`, no argument.

## Steps

1. **Name and place.** The file goes in the current directory (the worktree, when the
   session runs in one), named with the current time, year to minute:

   ```sh
   f="$(date +%Y%m%d%H%M)-handoff.md"
   ```

   If `$f` already exists, overwrite it: it is the same minute, the same session.

2. **Keep it out of git.** The file holds the whole session, so it must never be
   committed by accident. Inside a git repo, exclude it locally, idempotently:

   ```sh
   exclude="$(git rev-parse --git-common-dir)/info/exclude"
   grep -qxF '*-handoff.md' "$exclude" || echo '*-handoff.md' >> "$exclude"
   ```

3. **Read the real state, do not trust memory.** Run `pwd`, `git branch --show-current`,
   `git status --short`, `git worktree list`, `git log --oneline -5` and, when a PR
   exists for the branch, `gh pr view --json number,url,state,title`. Copy the output
   that matters into the file.

4. **Write the file**, in the language the user used in the session, with these sections
   (drop one only when it is truly empty):

   - `# Handoff <date and time>`, then one line: project, directory, branch.
   - **Goal**: what the user asked for, in their words where it matters.
   - **State now**: what is done, what is half done, what works, what does not.
   - **Decisions**: each decision with the why, and the options that were ruled out.
   - **What changed**: files edited or created (absolute paths), commands that mattered,
     branches, worktrees, PRs, tickets, commits. Say what is uncommitted or unpushed.
   - **Facts to keep**: paths, ids, URLs, ticket keys, environment names, versions, output
     of commands the next session would otherwise run again.
   - **User preferences and corrections** given during the session.
   - **Open questions**: what is waiting on the user or on someone else.
   - **Running or scheduled things**: background commands, subagents, loops, cron jobs,
     and whether they die with this session.
   - **Next steps**: ordered, concrete, the first one ready to execute.

5. **Never write**: secrets, tokens, passwords, cookies, or data of real people (PII, PHI).
   Name where the secret lives instead ("token in `$GITHUB_TOKEN`, set by the shell profile").
   Do not paste long raw output; keep the lines that carry the fact.

6. **Writing rules.** No em dash, en dash, curly quotes, ellipsis character, arrows or
   bullet glyphs (use `-`, `"`, `...`, `->`). When `deslop` is installed, run
   `deslop --check "$f"` and, on a hit, `deslop "$f"`.

7. **Report** to the user in two lines at most: the full path of the file and the
   command to run in the new session (`/handin`, from the same directory). Do not print
   the handoff back.

## Hard rules

- Write only that one file (plus the exclude line). No commit, push, or other change.
- Complete beats short: a missing fact costs the next session a question to the user.
