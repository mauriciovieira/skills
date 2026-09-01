---
name: babysit-with-claude-review
description: Babysit a PR through Claude's own GitHub review (anthropics/claude-code-action) until merge. Use when the user asks to "babysit PR #N", "ship PR #N", "/babysit-with-claude-review", or after opening a PR in a repo where the Claude Code Review workflow runs. Encodes the open -> trigger review -> wait for the workflow run on the exact head SHA -> fetch comments -> address -> push -> wait for the new run -> merge -> cleanup loop. Never merges on silence: a completed review run whose headSha equals the current head SHA is the hard gate, because a clean Claude review posts nothing at all.
---

# babysit-with-claude-review

Drive a pull request from "just opened" (or "ready for review") to merged +
clean worktree, in cycles around review feedback from Claude running on GitHub
(`anthropics/claude-code-action`).

**Invocation:** always `/babysit-with-claude-review` (hyphens, not colons). The
on-disk skill name is `babysit-with-claude-review`. Use this exact form in any
ScheduleWakeup prompt that re-enters this skill - a colon form is NOT a valid
command and will fail with "Unknown command".

## Why this is not the Copilot loop

`/babysit-with-github-copilot` gates on a **review event**: after a re-request,
Copilot always submits a review summary, even "I reviewed your changes and
found no new comments". That event is the merge authorisation.

Claude on GitHub does not do this. Observed behaviour on a real PR
(`OmnicodeSolutions/bora-turma#30`):

| | Copilot | Claude Code Review |
|---|---|---|
| Clean review | posts an explicit "no new comments" review event | **posts nothing at all** |
| Findings | one review event with N inline comments | **N review events, one per inline comment, every body empty** |
| Trigger | `--add-reviewer` | `pull_request` workflow event (auto), or `@claude` comment |
| Merge signal | `review.submitted_at > last_push_at` | **workflow run with `headSha == <current head SHA>` reaching `completed`** |

Consequence: **silence is ambiguous here.** "Claude re-reviewed and found
nothing" and "Claude has not started yet" look identical on the PR. Every
copilot-style timestamp watermark on reviews or comments is therefore unusable
as a gate. The workflow run is the only signal that distinguishes the two, and
this skill gates on it.

Second consequence: since no review event ever says "clean", the PR is closed
by an **extra run** rather than by a verdict. After fixing findings you push,
let the review run again, and merge only if that run requested nothing new
(Step 5). The trail left on the PR is one reply per finding plus a resolved
thread (Step 4a) - never a summary comment.

## Hard stops (read first - violations ship broken PRs)

Non-negotiable. If any would be violated, **stop the turn** and schedule the
next cycle instead of merging.

1. **Never merge in the same agent turn as `git push`.** Push ends the turn.
   Schedule the next cycle (`ScheduleWakeup`, 300 s) and exit.
2. **Never merge in the same agent turn as triggering a review.** The run fires
   against the new commit; it needs time.
3. **Never merge without completing Step 3 at least once after the latest
   push.** Replying to comment threads is not a substitute for waiting.
4. **Never treat "no CI checks reported" as permission to skip the wait.**
5. **Never merge on silence.** No comments from the reviewer bot is NOT a clean
   review. Only a **`completed` review run whose `headSha` equals the PR's
   current `headRefOid`** authorises merge. This is the master gate.
6. **Never accept a run that did not review the current head commit.** In auto
   mode that means `run.headSha == <current headRefOid>` exactly - a run on the
   previous commit reviewed code you have since changed, and a branch-name
   match is not enough. In mention mode `run.headSha` is the **default
   branch's** tip, not the PR head (GitHub runs `issue_comment` workflows
   against the default branch), so the SHA equality test can never pass; use
   the mention-mode matcher in Step 3 instead. Never relax the auto-mode test
   to a branch match to work around this.
7. **Never count a run that skipped the review as a review** - whether it
   skipped at the run level or inside itself.
   - **Run-level `skipped`.** The mention workflow
     (`.github/workflows/claude.yml`, usually named "Claude Code") fires on
     `issue_comment` / `pull_request_review` / `pull_request_review_comment`
     and exits `skipped` whenever the trigger phrase is absent. **Your own
     replies to review threads spawn a burst of these** - on PR #30, ten
     `skipped` runs in six seconds. They are noise that looks exactly like
     review activity in `gh run list`. Gate on the **review** workflow only,
     matched by workflow file path (Step 0), and require `conclusion: success`.
   - **Self-skip inside a `success` run.** The action refuses to review when
     the workflow file on the PR branch is not byte-identical to the version on
     the default branch, and it does so as a `##[warning]` in the step - so the
     **run still reports `completed` + `success`, with zero comments**. That is
     a merge-on-silence trap that `conclusion` cannot see. Real case, run
     `33479468831` on `mauriciovieira/skills`:
     ```
     completed  success  fc1b82c
     ##[warning]Skipping action due to workflow validation: Workflow validation
     failed. The workflow file must exist and have identical content to the
     version on the repository's default branch.
     ```
     Detect it in the log (Step 3). **Do not use `annotations_count`** - a
     genuinely clean run carries unrelated annotations (a real one had
     `annotations_count: 1`, purely a `Node.js 20 is deprecated` runner
     warning), so counting annotations rejects good reviews and is not a test
     of anything. Grep the log for the marker instead.
8. **Never count a `failure`, `cancelled`, or `timed_out` run as a review.**
   The review did not happen. Re-trigger (Step 2) or surface to the user - a
   failed run posts no comments, which is indistinguishable from clean.
9. **Never merge while the review run for the current head SHA is `queued` or
   `in_progress`.** `gh pr merge --delete-branch` cancels it mid-scan and the
   comments it was about to post are lost. Observed run durations on a small
   repo: 51 s to **13 minutes**. Budget accordingly; do not escalate early.

If you pushed fixes this turn: commit -> push -> ensure a review is triggered
(Step 2) -> brief status to user -> **ScheduleWakeup** -> **stop**. Do not call
`gh pr merge` until a later wake-up completes Step 3.

## Preconditions (verify before starting)

- Current branch has commits ahead of `origin/main` (or the repo's default).
- Working tree clean (or only files you are about to commit yourself).
- `gh` is authenticated for the repo.
- Conventional Commits already used on the branch's history.
- **The repo actually runs Claude on GitHub** - verify in Step 0. If no Claude
  review workflow exists, stop and tell the user to install it
  (`/install-github-app` in Claude Code, or add
  `.github/workflows/claude-code-review.yml`). Do not fall back to babysitting
  a PR with no reviewer.
- A spec exists at `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` if the
  repo follows that convention. Do not fabricate one - if absent and the change
  is non-trivial, flag it before opening the PR.

If any precondition fails, stop and report. Do not paper over.

## Step 0 - Identify the review workflow and the reviewer login (once per PR)

Everything downstream keys off two values. Resolve them before the loop and
persist them in loop state.

```sh
# Active workflows. You are looking for TWO different Claude workflows:
#   - "Claude Code Review" / claude-code-review.yml  -> the REVIEWER (gate on this)
#   - "Claude Code"        / claude.yml              -> the @claude MENTION bot (noise)
gh api repos/<owner>/<repo>/actions/workflows \
  --jq '.workflows[] | select(.state=="active") | [.name, .path, .id] | @tsv'
```

Pick the **review** workflow: the one whose path is `claude-code-review.yml`,
or - if named differently - the Claude workflow whose `on:` block contains
`pull_request`. Read it to be sure, and to learn the trigger style:

```sh
gh api repos/<owner>/<repo>/contents/.github/workflows/<file>.yml \
  --jq '.content' | base64 -d | sed -n '1,40p'
```

- **`on: pull_request`** -> **auto mode**. Every push to the PR starts a review
  run by itself. Step 2 is a no-op.
- **`on: issue_comment` + `trigger_phrase`** -> **mention mode**. Nothing runs
  until you post the trigger phrase. Step 2 is mandatory after every push.

A repo can have both. If the review workflow is auto, prefer it and treat
mention mode as a manual re-trigger for when a run did not fire.

**If this PR touches the review workflow file itself, it cannot be reviewed.**
The action requires the file to be byte-identical to the version on the default
branch and self-skips otherwise - while still reporting `success` (Hard Stop
#7). Land the workflow change on the default branch first, then rebase or merge
it into the PR so the two match, and only then expect a review. Check with:

```sh
git show origin/main:.github/workflows/<file>.yml | git hash-object --stdin
git hash-object .github/workflows/<file>.yml
```

Equal hashes, or no review.

**Reviewer login.** Default is `claude[bot]`, but the action posts under a
different account when the workflow overrides `github_token` (commonly
`github-actions[bot]`). Detect rather than assume:

```sh
gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate \
  --jq '[.[].user.login] | unique'
```

Persist as `reviewer_login`. Match with `startswith("claude")` OR the exact
detected string; never hardcode across repos.

## Loop state to track between cycles

Persist across wake-ups (in the wakeup prompt or session notes):

| Field | Meaning |
|-------|---------|
| `<N>` | PR number |
| `review_workflow` | Workflow file, e.g. `claude-code-review.yml` (from Step 0) |
| `trigger_mode` | `auto` or `mention` (from Step 0) |
| `reviewer_login` | e.g. `claude[bot]` (from Step 0) |
| `head_sha` | PR's current `headRefOid` - **the thing the gate matches on** |
| `review_run_id` | Run id of the review for `head_sha`, once found |
| `trigger_posted_at` | Mention mode only: `created_at` of the `@claude` comment you last posted |
| `last_push_at` | ISO timestamp of the most recent fix push (empty if none) |
| `awaiting_rereview` | `true` after a fix push until Step 3 completes once post-push |

`head_sha` is the watermark, not a timestamp. Every push changes it, which
invalidates the previous run and closes the gate automatically - no clock
comparison, no propagation race.

Reset `awaiting_rereview` to `false` only on a wake-up (never on the push turn)
where Step 3 found a `completed` + `success` review run for the current
`head_sha` and both comment surfaces returned zero. It is belt-and-braces on
top of the SHA watermark: the watermark closes the gate, this flag stops you
merging on the same turn you pushed.

## Step 1 - Open the PR (if not already open)

1. Lint + test locally first. Repo conventions take precedence
   (`make lint && make test`). Do not push if lint or unit tests fail.
2. Rebase onto the upstream default branch:
   `git fetch origin --prune && git rebase origin/main`
3. Push: `git push -u origin <branch>`.
4. Compose the PR body from the repo's template at
   `.github/WORKFLOW_TEMPLATES/pull_request.md` (or `PULL_REQUEST_TEMPLATE.md`).
   Fill it in fully - no placeholder bullets, no "TBD". Sections expected:
   Summary, Context, What changed, Test plan, Risk & rollback, Checklist.
5. Open via `gh pr create --title "<conventional title>" --body-file <path>`.
   Pass the body via `--body-file`, never inline `--body "$(cat ...)"`.
6. Capture the PR number `<N>`; the rest of the loop hangs off it.

## Step 2 - Trigger the review

**Auto mode:** nothing to do. The `pull_request` event already queued a run for
the new head SHA. Confirm in Step 3 that a run exists for that SHA; if none
appeared after two cycles, fall back to the mention form below.

**Mention mode:** post the trigger phrase as a PR comment.

```sh
gh pr comment <N> -R <owner>/<repo> \
  --body "@claude review the latest commit on this PR"

# Record the trigger watermark - Step 3's mention-mode matcher needs both.
trigger_posted_at=$(gh api repos/<owner>/<repo>/issues/<N>/comments --paginate \
  | jq -s -r 'add | sort_by(.created_at) | last | .created_at')
head_sha=$(gh pr view <N> -R <owner>/<repo> --json headRefOid --jq '.headRefOid')
```

Notes:

- A new `@claude` comment is the only way to re-trigger. **Replying inside an
  existing `claude[bot]` review thread does not re-trigger a review** - it only
  spawns a `skipped` run of the mention workflow (Hard Stop #7).
- Comment-triggered runs report `headBranch: main` **and `headSha` = the
  default branch's tip**, not your PR branch or its head commit. Filter them by
  workflow + `createdAt >= trigger_posted_at`, and assert separately that
  `headRefOid` has not moved since the trigger. Never filter by branch, and
  never expect `headSha` to equal the PR head in this mode.
- Do not request other human reviewers unless the user told you to.

## Step 3 - The wait cycle (mandatory gate)

**You must sleep before deciding to merge.** Use `ScheduleWakeup` with
`delaySeconds: 300` and a `prompt` that re-enters this skill. Do not poll in a
tight loop; do not skip because "CI is empty" or "comments look addressed".

On wake-up, run all of the following before deciding the next move:

```sh
head_sha=$(gh pr view <N> -R <owner>/<repo> --json headRefOid --jq '.headRefOid')

gh pr checks <N> -R <owner>/<repo>          # CI status

# The gate. Match on the REVIEW workflow file (--workflow takes the file name,
# which is stable across workflow renames), then narrow by trigger_mode.
runs=$(gh run list -R <owner>/<repo> --workflow "<review_workflow>" --limit 20 \
         --json databaseId,headSha,status,conclusion,createdAt,updatedAt)

case "<trigger_mode>" in
  auto)
    # The run reviewed the PR head itself, so match the SHA exactly.
    run=$(printf '%s' "$runs" | jq --arg sha "$head_sha" \
            'map(select(.headSha == $sha)) | sort_by(.createdAt) | last') ;;
  mention)
    # issue_comment workflows run against the DEFAULT branch, so headSha is
    # main's tip and can NEVER equal $head_sha - matching on it deadlocks the
    # loop forever. Match on "started after the trigger comment I posted", and
    # separately assert the PR head has not moved since the trigger; if it has,
    # the run reviewed superseded code.
    if [ "$head_sha" != "<head_sha when trigger was posted>" ]; then
      echo "head moved since the trigger - gate closed, re-trigger (Step 2)"
      run=null
    else
      run=$(printf '%s' "$runs" | jq --arg t "<trigger_posted_at>" \
              'map(select((.createdAt|fromdateiso8601? // 0) >= ($t|fromdateiso8601? // 0)))
               | sort_by(.createdAt) | last')
    fi ;;
esac

run_id=$(printf '%s' "$run" | jq -r '.databaseId? // empty')
run_status=$(printf '%s' "$run" | jq -r '.status? // "none"')
run_concl=$(printf '%s' "$run" | jq -r '.conclusion? // "none"')
run_start=$(printf '%s' "$run" | jq -r '.createdAt? // empty')
printf 'gate: sha=%s run=%s status=%s conclusion=%s\n' \
  "$head_sha" "${run_id:-none}" "$run_status" "$run_concl"
```

Then, **only if** `run_status` is `completed` and `run_concl` is `success`,
confirm the run did not skip the review inside itself (Hard Stop #7). A
`success` run that self-skipped posts zero comments and is indistinguishable
from a clean one on `conclusion` alone:

**Fetch the log and grep it as two separate operations, and fail closed.**
Piping `gh run view --log` straight into `grep` collapses "the log says no
skip" and "the log never arrived" into the same empty output, and the grep then
reports clean - reopening the exact merge-on-silence hole this check exists to
plug. Logs go missing for reasons unrelated to the code: GitHub expires them
after 90 days, and rate limits or network failures hit at any time.

```sh
log=$(mktemp)
if ! gh run view "$run_id" -R <owner>/<repo> --log > "$log"; then
  echo "could not fetch log for run $run_id - gate CLOSED (cannot verify)"
  # Retry next cycle; escalate after 3 consecutive fetch failures (see below).
elif grep -qiE 'workflow validation failed|skipping action due to workflow' "$log"; then
  echo "run $run_id self-skipped - NOT a review, gate CLOSED"
  # Usual cause: this PR edits the review workflow file, so it no longer
  # matches the default branch. See Step 0. Do NOT merge.
elif grep -q '"is_error": *true' "$log"; then
  echo "run $run_id errored inside the action - NOT a review, gate CLOSED"
else
  # The action's result JSON. Echo these every cycle - see below on denials.
  grep -oE '"(subtype|is_error|num_turns|permission_denials_count)": *[^,]*' "$log" \
    | tail -4
  echo "run $run_id genuinely reviewed ($(wc -l < "$log") log lines)"
fi
```

**On `permission_denials_count`: report it, do not auto-gate on it.** A run can
finish green having been blocked from doing its job - a documented case reviewed
nothing in 2m49s with `permission_denials_count: 16`. But a nonzero count is
*not* by itself proof of that: run `33479917884` on `mauriciovieira/skills`
had `permission_denials_count: 1` alongside `subtype: success`,
`is_error: false` and `num_turns: 4`, and was a genuine clean review. Gating on
`> 0` would have wedged that PR for nothing.

Two data points do not calibrate a threshold, so this skill does not invent
one. **Echo the count and surface any nonzero value to the user** with the
run's `num_turns` beside it - a review blocked out of doing its work shows up
as denials *and* an implausibly small `num_turns` for the size of the diff.
Let the human make that call rather than wedging the PR or waving it through.
`is_error: true` is the part that is unambiguous, and that one closes the gate.

An unreadable log is an **unverifiable** run, and unverifiable is never clean.
This can wedge a PR for a reason that has nothing to do with its code - that is
the intended trade: every ambiguous state in this skill resolves to "wait", and
escalating to a human beats merging something no one checked.

**Why 3 fetch failures here, but ~6 cycles in Step 4 #5.** The two waits are
not the same measurement, and the numbers should not be unified. Step 4 #5
waits on a run still executing - progress is happening, and runs have been
observed taking 13 minutes, so escalating at 3 cycles would interrupt normal
work. This wait is on a *finished* run whose log will not load: that is
unavailability, not slowness. Rate limits and network blips clear in a cycle or
two; a log expired past GitHub's 90-day retention never loads at all, and
retrying it six times changes nothing. Escalate sooner because waiting longer
buys no new information. Do not "fix" this to 6 for consistency.

Only once the run is confirmed genuinely reviewed, read what it posted. Two
surfaces, both needed:

```sh
# Inline review comments. Claude posts one review event per comment, all with
# empty bodies, so /reviews tells you nothing - read the comments directly.
# commit_id is the primary filter; the run window is the cross-check.
gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate \
  | jq -s --arg sha "$head_sha" --arg login "<reviewer_login>" --arg start "$run_start" \
      'add
       | map(select(.user.login == $login
                    and (.commit_id == $sha
                         or ((.created_at|fromdateiso8601? // 0) >= ($start|fromdateiso8601? // 0)))))
       | {count: length, comments: [.[] | {id, path, line, body}]}'

# Sticky summary comment, when the workflow sets use_sticky_comment. It is
# UPDATED IN PLACE, so filter on updated_at, never created_at.
gh api repos/<owner>/<repo>/issues/<N>/comments --paginate \
  | jq -s --arg login "<reviewer_login>" --arg start "$run_start" \
      'add
       | map(select(.user.login == $login
                    and (.updated_at|fromdateiso8601? // 0) >= ($start|fromdateiso8601? // 0)))
       | {count: length, bodies: [.[].body]}'
```

Interpret:

- **No run for `head_sha`** -> the review has not been triggered for this
  commit. Gate closed. Auto mode: wait one cycle. Mention mode: go to Step 2.
- **Run `queued` / `in_progress`** -> gate closed, wait (Hard Stop #9).
- **Run `completed`, conclusion not `success`** -> the review did not happen.
  Gate closed (Hard Stop #8). Inspect with
  `gh run view $run_id -R <owner>/<repo> --log-failed`, then re-trigger or
  surface to the user.
- **Run `completed` + `success`, but the log could not be fetched** -> the run
  is unverifiable. Gate closed. Retry next cycle; after 3 consecutive failures
  surface to the user. Never merge a run you could not check.
- **Run `completed` + `success`, but the log grep matched** -> the action
  skipped itself; no review happened. Gate closed (Hard Stop #7). Fix the cause
  - almost always this PR editing the review workflow file - and re-run.
- **Run `completed` + `success`, log grep clean, zero comments on both
  surfaces** -> genuinely clean review. Merge-eligible. Claude says nothing
  when it finds nothing; the successful, non-self-skipped run on the matching
  SHA is what makes that meaningful.
- **Run `completed` + `success`, >= 1 comment** -> unaddressed until fixed and
  pushed (or replied "won't fix" with a reason). Go to Step 4 #3.

## Step 4 - Decide

Decision tree, in order. **If the answer sends you to Step 3, do not merge this
turn.**

1. **CI failing** -> investigate, reproduce locally, push a fix. Set
   `last_push_at`, `awaiting_rereview=true`, trigger review (Step 2).
   **Stop turn -> Step 3.** Never merge with red CI.
2. **CI still pending after 5 minutes** -> wait one more cycle, then escalate
   to the user if still pending; usually a stuck runner.
3. **Review comments on the current head SHA** -> address every comment with
   substance. Skip nothing without justification (a "won't fix" gets a one-line
   reply with the reason). Run lint + tests again. Commit + push. Set
   `last_push_at`, `awaiting_rereview=true`, refresh `head_sha`.
   **For every addressed comment, complete Step 4a (reply + resolve + echo)
   before triggering the re-review.** Then Step 2.
   **Stop turn -> Step 3.** Do NOT merge.
4. **`awaiting_rereview` is true and this is the push turn** -> waited time has
   not elapsed. Stop, ScheduleWakeup.
5. **No review run for the current `head_sha`, or it is `queued`/`in_progress`**
   -> wait one cycle (ScheduleWakeup 300 s). Do NOT merge (Hard Stops #5, #9).
   Runs have been observed taking 13 minutes; do not escalate before ~6
   consecutive empty cycles (~30 min), then surface to the user and let them
   decide. Never auto-merge on silence.
6. **Review run for `head_sha` completed but not `success`** -> Hard Stop #8.
   Re-trigger or surface. Do NOT merge.
7. **CI green (or no checks) AND a review run exists for the current
   `head_sha` AND it is `completed` with conclusion `success` AND both comment
   surfaces return zero for that run** -> merge. Go to Step 5.

Branch **#7** is the only path to merge.

## Step 4a - Reply, resolve, and echo every addressed comment (mandatory)

**Exactly one reply per finding, on that finding's own thread, then resolve it.**
Never aggregate several findings into one comment, and never substitute a
single summary comment on the PR for the per-finding replies - the reply has to
sit on the thread it answers, or the reviewer cannot tell which finding it
closed.

After pushing the fix commit(s), for **each** comment you addressed (whether
applied or "won't fix"):

1. **Compose the reply text.** One concise sentence: what changed, where, why.
   - Applied: `"Applied in <sha> - <one-line summary> (file:line)."`
   - Won't fix: `"Not taking this - <reason>. (Tracked: <link/issue> if any.)"`
2. **Echo the reply to the agent terminal BEFORE posting.** Print exactly what
   you are about to send, prefixed with the comment's `path:line` and the
   reviewer login. The user must be able to read the verbatim reply text in the
   transcript without opening GitHub.
3. **Post the reply on the comment thread:**
   ```sh
   gh api -X POST \
     repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies \
     -f body="<reply text>"
   ```
   Each of these spawns a `skipped` mention-workflow run. Expected; ignore them
   (Hard Stop #7).
4. **Resolve the review thread.** Get the thread id via GraphQL by matching the
   comment's `databaseId`:
   ```sh
   gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -f query='
     query($owner: String!, $repo: String!, $number: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $number) {
           reviewThreads(first: 100) {
             nodes { id isResolved comments(first: 1) { nodes { databaseId } } }
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
complete. Triggering a re-review with unresolved threads is a Step 4 #3
violation.

## Step 5 - The extra-run gate (post-fix only)

Applies whenever you pushed a fix for review feedback, i.e. `awaiting_rereview`
is `true`. **You may never merge on the same run that produced the findings.**
Fixing the comments and merging is one round short: the fix itself is
unreviewed code.

The closing condition for the PR is therefore an **extra review run, started
after the fix push, that requested nothing new**:

1. The run exists in GitHub Actions for the current `head_sha` (Step 3's
   matcher, per `trigger_mode`).
2. It reached `completed` with conclusion `success` - not `skipped`, not
   `failure` (Hard Stops #7, #8).
3. Both comment surfaces return **zero** new comments from `reviewer_login`
   for that run.

Only all three together close the PR. Two of three is a wait, not a merge.

Echo the gate to the agent terminal before merging, so the transcript shows
which run authorised it:

```
gate: run <run_id> (<review_workflow>) on <head_sha> -> completed/success
      at <run_updated_at>, 0 new comments from <reviewer_login>. CI: <status>.
```

Do **not** post this as a PR comment. The PR's audit trail is one reply per
finding plus a resolved thread (Step 4a) - a summary comment on top of that is
noise, and on a PR with no findings there is nothing to report.

Then Step 6.

## Step 6 - Merge

Use the project's preferred merge style. Default is squash:

```sh
gh pr merge <N> -R <owner>/<repo> --squash --delete-branch
```

Confirm with `gh pr view <N> -R <owner>/<repo>` that state is `MERGED`.

## Step 7 - Local cleanup

```sh
git fetch origin --prune
git branch -vv | awk '/: gone]/{print ($1 == "*" ? $2 : $1)}' \
  | while read -r b; do
      git branch -d "$b" || echo "skip $b (not fully merged locally - inspect)"
    done
```

If the work was in a worktree under `.worktrees/<name>/`:

```sh
git worktree remove .worktrees/<name>
```

Removal fails with uncommitted changes - investigate before forcing.

## House rules (do NOT skip)

- **Conventional Commits** on every commit, including review-feedback commits.
  `fix(frontend): apply Claude round-N review feedback on ...` is fine.
- **Never `--no-verify`** to dodge a hook. Fix the underlying issue.
- **Never `--amend`** a published commit. New commits only.
- **Never force-push** unless the user explicitly asked. Rebase + `git push`
  fast-forwards if your local history is a clean superset; otherwise stop.
- **Never weaken security controls** to make e2e easier (no bypassing 2FA
  freshness gates, no disabling CSRF). Stub at the test layer instead.
- **Do not merge with failing CI.** Do not merge with unaddressed review
  comments unless each is explicitly justified as "won't fix" with a reply.
- **Spec parity:** when a review comment exposes drift between the spec and the
  shipped code, update the spec in the same fix commit.
- **Push a review comment's fix as its own commit** before replying. Replying
  that a fix landed without pushing it is the worst failure mode in the loop.

## Notes for the loop

- **Disambiguate the repo with `-R <owner>/<repo>` on every `gh pr ...` /
  `gh run ...` call** when the clone has more than one remote. Without `-R`,
  `gh` may resolve against the wrong remote and silently report another repo's
  PR - which can fake-pass or fake-fail the gate. The
  `gh api repos/<owner>/<repo>/...` form is already explicit.
- Each cycle sends a brief status to the user: round number, run id + SHA,
  number of new comments, what you applied, next ETA. One short paragraph.
- Use the user's preferred output style if they are in caveman / lite mode.
- Spec the wakeup `prompt` to re-enter this skill verbatim. Include `<N>`,
  `head_sha`, `review_workflow`, `trigger_mode`, `reviewer_login`, and
  `awaiting_rereview`.
- If review rounds stack past 5+ without convergence, surface that to the user
  before continuing.

## Anti-patterns

- **Merging on silence.** The canonical failure. Claude posts nothing on a
  clean review, so "no new comments" alone proves nothing. Real case: PR #30
  was merged 111 s after the re-review run for the fix commit completed. That
  run was in fact clean - but nothing on the PR said so, so the merge was
  indistinguishable from one with no re-review at all, and the loop itself had
  no way to tell the two apart. Close the PR on an extra run that requested
  nothing new (Step 5), and echo which run authorised it.
- **Matching the run by branch instead of head SHA.** A run on the previous
  commit reviewed code you have since changed. Mention-triggered runs also
  report `headBranch: main`, so branch matching is doubly wrong.
- **Counting `skipped` runs as reviews.** Your own thread replies spawn them in
  bursts. They mean "trigger phrase absent", not "reviewed".
- **Counting a `failure`/`cancelled` run as clean** because it posted no
  comments. A crashed review posts nothing, exactly like a clean one.
- **Trusting `conclusion: success` alone.** A run that self-skipped on workflow
  validation is `completed` + `success` with zero comments. Grep the log
  (Step 3).
- **Gating on `annotations_count == 0`.** Clean runs carry unrelated
  annotations - a real one had a single `Node.js 20 is deprecated` warning - so
  this rejects good reviews while proving nothing about whether the review ran.
- **Piping `gh run view --log` into `grep` in one command.** A failed fetch and
  a clean log both produce no match, so the check silently passes on exactly
  the runs it cannot verify. Fetch to a file, test the exit status, then grep.
- **Auto-gating on `permission_denials_count > 0`.** A genuine clean review had
  exactly one denial. Report the count with `num_turns`, let the human judge.
- **Gating on `/pulls/<N>/reviews`.** Claude's review events all have empty
  bodies and there is one per inline comment - the endpoint carries no verdict.
- **Filtering the sticky summary comment by `created_at`.** It is updated in
  place; `created_at` stays frozen at the first round forever.
- **Replying in a `claude[bot]` thread and expecting a re-review.** Only a new
  `@claude` comment (mention mode) or a new push (auto mode) starts a run.
- **Merging while the review run is `in_progress`** - `--delete-branch` cancels
  it and loses the comments it was about to post.
- **Escalating after 3 quiet cycles while a run is still executing.** Runs have
  taken 13 minutes. Wait ~6. (This does not apply to the 3-failure limit on
  fetching a finished run's log - that one measures unavailability, not
  slowness. See Step 3.)
- **Merging on the same run that produced the findings.** Fixing the comments
  and merging leaves the fix itself unreviewed. The PR closes on the *next*
  run, not the one you are answering (Step 5).
- **Aggregating replies into one summary comment on the PR.** One reply per
  finding, on its own thread, then resolve. A summary comment answers nothing
  and leaves every thread open.
- Marking a comment "applied" without actually pushing the change.
- **Merging in the same turn as push or trigger** - always ScheduleWakeup.
- **Resolving a thread without posting a reply** - loses the audit trail.
- **Posting a reply without resolving the thread** - leaves stale "Unresolved"
  badges; the reviewer cannot tell what is still open.
- **Marking resolved without echoing the reply text to the terminal** - the
  user audits the loop from the transcript.
- Merging with a review-feedback commit that contains unrelated refactors.

## Quick reference - one turn, one phase

| Phase this turn | Allowed actions | Forbidden |
|-----------------|-----------------|-----------|
| Fix round | edit, commit, push, trigger review, reply/resolve comments, status, ScheduleWakeup | `gh pr merge` |
| Wait wake-up | fetch checks/run/comments, decide Step 4, maybe clear the extra-run gate + merge (Steps 5/6) | push unless Step 4 #1 or #3 triggered |
