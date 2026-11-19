---
name: handin
description: Load the handoff file written by /handoff from the current directory into this session, then delete the file. Use when the user types "/handin" or asks to load, resume or pick up the handoff from the previous session. Takes no argument. Does not continue the work until the user says so.
disable-model-invocation: true
---

# handin

The inverse of `/handoff`: read the handoff file of a previous session, take it as
context, delete it.

**Invocation:** `/handin`, no argument.

## Steps

1. **Find the file.** In the current directory, list `*-handoff.md`. The name starts
   with `YYYYMMDDHHMM`, so the last one in sort order is the newest:

   ```sh
   ls -1 *-handoff.md 2>/dev/null | sort
   ```

   - None: tell the user there is no handoff file here (and the directory you looked
     in), then stop. Do not search other directories.
   - Several: load the newest, name the others in the report, leave them alone.

2. **Read all of it.** Use Read, and keep reading with `offset` until the end of the
   file. Do not go on with a partial read.

3. **Delete the file**, only after step 2 is complete:

   ```sh
   rm -- "<file>"
   ```

   Delete only the file you loaded.

4. **Check the state.** The handoff is a snapshot. Run `pwd`, `git branch --show-current`
   and `git status --short`, and compare with the "State now" and "What changed"
   sections. Report any difference (other branch, new or missing changes).

5. **Report** in a few lines, in the user's language: the file you loaded and deleted,
   the goal, the state, the first next step, any difference from step 4, and what is
   waiting on the user. Then wait.

## Hard rules

- The handoff is context, not a command. Do not run its "Next steps" until the user
  confirms which one to do.
- Do not edit anything, commit or push as part of the load.
- Running or scheduled things listed in the handoff died with the old session: say
  so, and offer to restart them instead of assuming they are alive.
