---
name: babysit-with-github-copilot
description: Babysit a PR through GitHub Copilot review until merge. Use when the user asks to "babysit PR #N", "ship PR #N", "/babysit-with-github-copilot", or after opening a PR they want shepherded to merge. Encodes the open → request review → 5-min wait → fetch comments → address → push → re-request → wait for Copilot's post-push review event → merge → cleanup loop. Never merges on silence: a Copilot review dated after the last push is the hard gate.
---

# babysit-with-github-copilot

Drive a pull request from "just opened" (or "ready for review") to merged + clean
worktree, in tight 5-minute cycles around GitHub Copilot review feedback.

**Invocation:** always `/babysit-with-github-copilot` (hyphens, not colons). The
on-disk skill name is `babysit-with-github-copilot`. Use this exact form in any
ScheduleWakeup prompt that re-enters this skill — a colon form is NOT a valid
command and will fail with "Unknown command".

## Hard stops (read first — violations ship broken PRs)

These are non-negotiable. If any would be violated, **stop the turn** and
schedule the next cycle instead of merging.

1. **Never merge in the same agent turn as `git push`.** Push ends the turn.
   Schedule the next cycle (`ScheduleWakeup`, 300 s) and exit.
2. **Never merge in the same agent turn as re-requesting Copilot review.**
   Re-request fires against the new commit; Copilot needs time to respond.
3. **Never merge without completing Step 3 at least once after the latest
   push.** Replying to comment threads is not a substitute for waiting.
4. **Never treat “no CI checks reported” as permission to skip the wait.**
   Absent CI is not a merge signal during the review loop.
5. **Never merge while Copilot comments exist whose `created_at` is after
   `last_push_at` and are not addressed with a code push or a documented
   “won’t fix” reply.**
6. **Never merge while a Copilot review Action is `in_progress` or `queued`.**
   An active Action is a stronger signal than silence — the review is in
   flight, not absent. Merging cancels it mid-scan (the `--delete-branch`
   kills the run), and you ship without seeing comments that were about to
   land. Check via `gh run list --branch <head> --workflow Copilot --limit 3`
   before every merge. Wait for `status: completed` (any conclusion is fine
   — Copilot may produce comments AND a `completed` run, but a still-running
   run means more comments may still appear).
7. **Never merge until Copilot has posted a *review event* dated after
   `last_push_at`.** This is the master gate. After a re-request, Copilot
   always submits a review summary — even "I reviewed your changes and found
   no new comments" is an explicit review event with its own `submittedAt`.
   That event, newer than your last push, is what authorises merge. Until it
   arrives, the absence of comments is **pending review**, not **clean
   review** — keep waiting (ScheduleWakeup), never merge on silence. A
   `completed` Copilot Action is necessary but **not sufficient**: the Action
   can finish seconds before the review summary posts (this exact race has
   shipped PRs with unaddressed comments). Gate on the review event, not the
   Action. Check:
   `gh pr view <N> --json reviews --jq '[.reviews[] | select(.author.login=="copilot-pull-request-reviewer" and .submittedAt > "<last_push_at>")] | length'`
   — must be `≥ 1` before any merge.

If you pushed fixes this turn: commit → push → re-request review (Step 2) →
brief status to user → **ScheduleWakeup** → **stop**. Do not call
`gh pr merge` until a later wake-up completes Step 3.

## Preconditions (verify before starting)

- Current branch has commits ahead of `origin/main` (or repo's default).
- Working tree clean (or only files you're about to commit yourself).
- `gh` is authenticated for the repo.
- Conventional Commits already used on the branch's history.
- A spec exists at `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` if the
  repo follows that convention. Don't fabricate one — if absent
  and the change is non-trivial, flag it before opening the PR.

If any precondition fails, stop and report. Don't paper over.

## Loop state to track between cycles

Persist across wake-ups (in the wakeup prompt or session notes):

| Field | Meaning |
|-------|---------|
| `<N>` | PR number |
| `last_review_at` | ISO timestamp of the latest Copilot review `submittedAt` |
| `last_push_at` | ISO timestamp of the most recent fix push (empty if none yet) |
| `awaiting_rereview` | `true` after a fix push until Step 3 completes once post-push |

Reset `awaiting_rereview` to `false` only after a full Step 3 wake-up that
finds (a) a Copilot review event with `submittedAt > last_push_at` and (b) no
unaddressed Copilot comments newer than `last_push_at`. The **merge gate** is
`last_review_at > last_push_at` — a fix push always makes `last_push_at` newer
than `last_review_at`, so you cannot merge again until Copilot re-reviews.

## Step 1 — Open the PR (if not already open)

1. Lint + test locally first. The user's repo conventions take precedence
   (`make lint && make test`). Don't push if lint or unit tests fail —
   fix first.
2. Rebase onto the upstream default branch:
   `git fetch origin --prune && git rebase origin/main`
3. Push: `git push -u origin <branch>`.
4. Compose the PR body from the repo's template at
   `.github/WORKFLOW_TEMPLATES/pull_request.md` (or `PULL_REQUEST_TEMPLATE.md`).
   Fill it in fully — no placeholder bullets, no "TBD". Sections expected:
   Summary, Context, What changed, Test plan, Risk & rollback, Checklist.
5. Open via `gh pr create --title "<conventional title>" --body-file <path>`.
   Pass the body via `--body-file`, never inline `--body "$(cat ...)"`.
6. Capture the returned PR URL + number; the rest of the loop hangs off `<N>`.

## Step 2 — Request Copilot review

```sh
gh pr edit <N> --add-reviewer copilot-pull-request-reviewer
```

Copilot may auto-review on PR creation in some repos; the explicit add is a
no-op if so, and a trigger if not. Don't request other human reviewers unless
the user told you to.

## Step 3 — The 5-minute cycle (mandatory gate)

**You must sleep 5 minutes before deciding to merge.** Use `ScheduleWakeup` with
`delaySeconds: 300` and a `prompt` that re-enters this skill. Do not poll in a
tight loop; do not skip because “CI is empty” or “comments look addressed”.

On wake-up, do all of the following before deciding next move:

```sh
gh pr checks <N>                            # CI status
gh pr view <N> --json reviews \
  --jq '.reviews | map({author: .author.login, state: .state, submitted: .submittedAt})'

# Copilot review Action — separate from CI checks. An in-flight Copilot run
# blocks merge (see Hard Stop #6). Note: `gh pr checks` can lag and report
# `pending` for a job that's already completed — verify any "pending" via
# `gh run view <runId> --json status,conclusion` before treating it as live.
gh run list --branch <head-branch> --workflow Copilot --limit 3 \
  --json status,conclusion,createdAt
```

Then fetch inline comments newer than the relevant watermark:

```sh
# After a fix push, filter against last_push_at; otherwise last_review_at:
gh api repos/<owner>/<repo>/pulls/<N>/comments \
  --jq '.[] | select(.created_at > "<ISO watermark>") | {path, line, body, created_at, user: .user.login}'
```

Update `last_review_at` from the latest Copilot review. **Compute the merge
gate explicitly:** is there a Copilot review with `submittedAt > last_push_at`?

```sh
gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login=="copilot-pull-request-reviewer" and .submittedAt > "<last_push_at>")] | length'
```

`0` → Copilot has not re-reviewed yet; you may NOT merge this cycle no matter
how quiet the PR looks (Step 4 #6). `≥ 1` → the post-push review has landed;
now check whether it carried new comments. If Copilot left new comments after
`last_push_at`, they are **unaddressed** until fixed and pushed (or replied
“won’t fix” with reason).

## Step 4 — Decide

Decision tree, in order. **If the answer sends you to Step 3, do not merge this
turn.**

1. **CI failing** → investigate. Reproduce locally if possible. Push a fix.
   Set `last_push_at`, `awaiting_rereview=true`. Re-request review (Step 2).
   **Stop turn → Step 3.** Do NOT merge with red CI.
2. **CI still pending after 5 minutes** → wait one more cycle, then escalate
   to the user if it's still pending — usually means a stuck runner.
3. **New Copilot comments since watermark** (see Step 3) → address every
   comment that has substance. Skip nothing without justification (a "won't
   fix" gets a one-line reply on the comment with the reason). Run lint +
   tests again. Commit + push. Set `last_push_at`, `awaiting_rereview=true`.
   **For every addressed comment, complete Step 4a (reply + resolve + echo)
   before re-requesting review.** Re-request Copilot via Step 2.
   **Stop turn → Step 3.** Do NOT merge.
4. **`awaiting_rereview` is true** → you pushed since the last completed
   cycle. Even if comments look answered, **waited time has not elapsed**.
   Apply Step 5 on this wake-up only; do not merge on the push turn itself.
5. **Copilot review Action is `in_progress` or `queued`** → wait one more
   cycle. ScheduleWakeup 270s. Do NOT merge — see Hard Stop #6.
6. **No Copilot review event dated after `last_push_at` yet** → Copilot has
   not finished re-reviewing, even if its Action shows `completed` (the
   summary posts seconds after the Action ends). Wait one more cycle
   (ScheduleWakeup 270s). Do NOT merge — see Hard Stop #7. If no review event
   arrives after ~3 consecutive cycles (~15 min), surface to the user and let
   them decide; never auto-merge on silence.
7. **CI green (or no checks) AND a Copilot review event exists with
   `submittedAt > last_push_at` AND that review left no unaddressed comments
   since `last_push_at` AND no Copilot Action in flight** → merge. Skip to
   Step 6.

Note: branch **#7** is the only path to merge. Branches **#1**, **#3**, **#5**,
**#6**, and the push turn of **#4** all require another Step 3 cycle first.

## Step 4a — Reply, resolve, and echo every addressed comment (mandatory)

After pushing the fix commit(s), for **each** comment you addressed (whether
applied or "won't fix"):

1. **Compose the reply text.** One concise sentence: what changed, where, why.
   - Applied: `"Done in <sha> — <one-line summary> (file:line)."`
   - Won't fix: `"Skipping — <reason>. (Tracked: <link/issue> if applicable.)"`
2. **Echo the reply to the agent terminal BEFORE posting.** Print exactly what
   you are about to send, prefixed with the comment's `path:line` and the
   reviewer login. The user must be able to read the verbatim reply text in
   the agent transcript without opening GitHub.
3. **Post the reply on the comment thread:**
   ```sh
   gh api -X POST \
     repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies \
     -f body="<reply text>"
   ```
4. **Resolve the review thread.** Get the thread id via GraphQL by matching
   the comment's `databaseId`:
   ```sh
   gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -f query='
     query($owner: String!, $repo: String!, $number: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $number) {
           reviewThreads(first: 100) {
             nodes {
               id
               isResolved
               comments(first: 1) { nodes { databaseId } }
             }
           }
         }
       }
     }'
   ```
   Then resolve:
   ```sh
   gh api graphql -f threadId="<thread_id>" -f query='
     mutation($threadId: ID!) {
       resolveReviewThread(input: {threadId: $threadId}) {
         thread { id isResolved }
       }
     }'
   ```
5. **Verify** `isResolved: true` in the mutation response.

A comment is not "addressed" until reply + resolve + terminal echo all
complete. Re-requesting review with unresolved threads is a Step 4 #3
violation.

## Step 5 — The post-push review gate (post-fix only)

Applies **only when `awaiting_rereview` is true** and Step 3 has completed
**once** after that push (i.e., you are on a wake-up, not the push turn).

The gate is a **Copilot review event**, not silence and not a finished Action.
After every fix push you re-request review (Step 2); Copilot responds by
submitting a review summary — and it does so **even when it has nothing to
add** ("I reviewed your changes and found no new comments"). That summary is
an explicit review with its own `submittedAt`. Wait for it.

**Two mandatory pre-checks before merge:**

1. **Action `completed`** — the Copilot review Action on the head branch must
   not be `in_progress`/`queued` (Hard Stop #6 / Step 4 #5).
2. **Review event present** — there must be a review by
   `copilot-pull-request-reviewer` whose `submittedAt > last_push_at`
   (Hard Stop #7 / Step 4 #6). A `completed` Action alone does **not** clear
   this; the summary commonly posts a few seconds *after* the Action ends, and
   merging in that gap ships unaddressed comments.

Then branch on what that review carried:

- **Review event present, no new inline comments since `last_push_at`** → this
  is the clean "no new comments" summary. Merge (CI green or absent). Go to
  Step 6.
- **Review event present, new inline comments since `last_push_at`** → go to
  Step 4 #3 (fix round). Do not merge.
- **No review event yet** → keep waiting (Step 4 #6). Do not merge on silence.
  After ~3 empty cycles (~15 min), surface to the user; never auto-merge.

This gate **never** overrides the hard stops: it does not permit merging in the
same turn as push/re-request, nor skipping Step 3, nor merging with a Copilot
Action still in flight.

## Step 6 — Merge

Use the project's preferred merge style. Default is squash:

```sh
gh pr merge <N> --squash --delete-branch
```

`--delete-branch` removes the remote branch. Confirm with `gh pr view <N>` that
state is `MERGED`.

## Step 7 — Local cleanup

```sh
git fetch origin --prune
# Drop local branches whose upstream is gone:
git branch -vv | awk '/: gone]/{print ($1 == "*" ? $2 : $1)}' \
  | while read -r b; do
      git branch -d "$b" || echo "skip $b (not fully merged locally — inspect)"
    done
```

If the work was in a worktree under `.worktrees/<name>/`:

```sh
git worktree remove .worktrees/<name>
```

Worktree removal will fail if there are uncommitted changes — investigate
before forcing.

## House rules (do NOT skip)

- **Conventional Commits** on every commit, including review-feedback commits.
  `fix(frontend): apply Copilot round-N feedback on …` is a fine pattern.
- **Never `--no-verify`** to dodge a hook. If a pre-commit hook fails, fix the
  underlying issue.
- **Never `--amend`** a published commit. New commits only.
- **Never force-push** unless the user explicitly asked. Rebase + `git push`
  fast-forwards if your local history is a clean superset; otherwise stop.
- **Never weaken security controls** to make e2e easier (no bypassing 2FA
  freshness gates, no disabling CSRF). Stub at the test layer instead
  (Playwright `page.route`, fixture monkeypatch).
- **Don't merge with failing CI.** Don't merge with unaddressed Copilot
  comments unless you've explicitly justified each as "won't fix" with a reply.
- **Spec parity:** when a review comment exposes drift between the spec and
  the shipped code, update the spec in the same fix commit. Spec must match
  what merges.

## Notes for the babysit loop

- Each cycle should send a brief status to the user: round number, # of new
  comments, what you applied, next ETA. One short paragraph, not prose.
- Use the user's preferred output style if they're in caveman / lite mode.
- Spec the wakeup `prompt` to re-enter this skill verbatim, so the next firing
  picks up where this one left off. Include `<N>`, `last_push_at`, and
  `awaiting_rereview` in the prompt.
- If review rounds stack past 5+ without convergence, surface that to the user
  before continuing — Copilot may be looping on style nits and the user may
  want to ship anyway.

## Anti-patterns

- Marking a Copilot comment "applied" without actually pushing the change.
- Replying on GitHub that a fix landed **without** pushing, then merging.
- Re-requesting review before pushing the fix commit (review fires against
  stale code).
- **Merging in the same turn as push or re-request** — the most common failure
  mode; always ScheduleWakeup and stop.
- **Treating Step 5 as “merge immediately after replies”** — Step 5 requires
  one completed 5-minute cycle after the push.
- **Merging on Copilot silence before its post-push review summary posts** —
  the canonical race. A `completed` Action is not the review; Copilot posts
  its "no new comments" (or its new comments) a few seconds later. Merging in
  that gap ships unaddressed comments. Gate on the review event
  (`submittedAt > last_push_at`), never on a quiet PR (Hard Stop #7).
- Letting CI go untested for >2 cycles without flagging.
- Merging with a `chore:` review-feedback commit that contains unrelated
  refactors. Keep review-fix commits tightly scoped.
- Treating "Copilot has nothing new" as license to merge while CI is still red
  or pending.
- Treating "no checks reported" as license to skip the 5-minute wait.
- **Resolving a thread without posting a reply** — the GitHub history loses
  the audit trail of what was done.
- **Posting a reply without resolving the thread** — leaves the PR UI
  cluttered with stale "Unresolved" badges; reviewer can't tell at a glance
  what's still open.
- **Marking resolved without echoing the reply text to the agent terminal** —
  the user reads the agent transcript to audit the loop; hiding what you said
  on GitHub breaks that trust loop.
- **Merging while a Copilot review Action is `in_progress` or `queued`** —
  `gh pr merge --delete-branch` cancels the run mid-scan and the comments
  it was about to post are lost. Treat an active Action as a stronger
  signal than comment silence; wait for the run to reach `completed`
  before invoking Step 5. See Hard Stop #6.

## Quick reference — one turn, one phase

| Phase this turn | Allowed actions | Forbidden |
|-----------------|-----------------|-----------|
| Fix round | edit, commit, push, re-request, reply to comments, status, ScheduleWakeup | `gh pr merge` |
| Wait wake-up | fetch checks/comments, decide Step 4, maybe merge (Step 5/6) | push unless Step 4 #1 or #3 triggered |
