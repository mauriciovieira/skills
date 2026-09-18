#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stop hook - when the turn wrote code, block the end of it and make the agent
interrogate the user about the domain decisions it just took.

Idea (Lucas Montano, on Matt Pocock's grill-me skill): instead of YOU reviewing
every line the AI generated, the AI reviews YOUR understanding of what it
generated. Here that becomes a deterministic trigger: it holds for
groundwork:build, :quick, :tdd, superpowers, or a loose "just fix this" - any
path that ends in a file write goes through here.

Gates, in this order:
  1. stop_hook_active -> exit (avoids a re-block loop)
  2. ~/.claude/.grill-active missing -> exit (opt-in, same pattern as
     .ponytail-active / .caveman-active)
  3. the LAST real user message says "stop the grill" -> exit
  4. no file write since the last real user message -> exit
     (Edit/Write/NotebookEdit, or Bash with a write idiom - see BASH_WRITE_RE)

Gate 3 is the per-turn escape valve: it silences the hook without making you
leave the conversation to delete the sentinel, and it re-arms on its own on the
next message that does not carry the phrase. Only the LAST real message counts -
which is why MUTE_RE is recomputed on every user turn and never accumulated.

No ceiling: every turn that writes code gets interrogated. There used to be a
limit of 3 per session; it was removed because on a long session it went quiet
early, exactly where unagreed decisions pile up the most.

When a Stop hook blocks, Claude Code injects the reason back into the transcript
as a user turn ("Stop hook feedback: ..."). That entry must NOT be mistaken for
a real user message - see FEEDBACK_RE.

Stop hook contract: reads JSON on stdin (transcript_path, stop_hook_active).
To block: print {"decision":"block","reason":...} and exit 0.
Fail open: any error -> exit 0 (a bug in here never wedges the session).
"""
import json
import os
import re
import sys

# Overridable only so the test can point at a sentinel of its own instead of
# mutating the live one. Nothing else sets it.
SENTINEL = os.path.expanduser(os.environ.get("GRILL_SENTINEL", "~/.claude/.grill-active"))
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}
# Bash was once left out, on the argument that it would need a heuristic over the
# command. That does not hold any more: auto mode explicitly tells the agent to
# write with sed / heredoc / redirect instead of Edit/Write, and on those turns
# the grill died quietly. Sweeping recent transcripts: writing via Bash is the
# same order of magnitude as writing via Edit/Write, so ignoring Bash is
# ignoring half the turns.
#
# Write idioms only, and the target has to look like a path (a slash or an
# extension) - that drops `if x > 5` and `2>&1` inside a heredoc. /dev/* is
# filtered after the match. `git commit -m "$(cat <<'EOF' ...)"`, the most common
# heredoc here, does not match: a heredoc is `<<`, not `>`.
# Deliberate bias: a false positive costs one extra question, a false negative
# costs the whole hook in silence. When in doubt, fire.
#
# The `>` must not sit right after a letter or underscore. That is what
# separates a real redirect from the `>` that closes a placeholder: in
# `sed -E 's/(ghp_)[A-Za-z0-9_]+/\1<REDACTED>/g'` the old pattern read `>` as a
# redirect and `/g` as an absolute path, and blocked a read-only secret scan.
# Known cost: `echo hi>/x/f.txt`, with no space, stops firing. `> f`, `>> f`,
# `2>f` and `&>f` all still do.
#
# Known and accepted false positive: a write idiom QUOTED AS DATA
# (`grep -n "tee -a ./x.txt" file`, a fixture inside `python3 -c '...'`) fires
# just the same, because a regex cannot tell a command from a string. Dropping
# every command that carries an interpreter flag would kill it, at the cost of
# missing `python3 -c '...' > out.txt`, which is a real write - the wrong side of
# the bias above. So it stays, and the reason ends with a line that lets an agent
# recognising none of the files say so and finish.
# ponytail: a regex, not a shell parser. A write from inside `python3 - <<PY`
# with open() does not fire. If that becomes routine, the next step is a
# PreToolUse hook on Bash, not more regex here.
_PATH = r"(?:[~.]?/[\w./~-]+|[\w-]+\.[A-Za-z][\w]{0,7})"
BASH_WRITE_RE = re.compile(
    r"(?:(?<![A-Za-z_])>>?|\btee\s+(?:-a\s+)?|\bsed\s+-i\b[^;&|\n]*?\s)\s*['\"]?(" + _PATH + r")"
)
# Purpose-built badge: never shows up in normal prose, only in the reason below.
MARKER = "[grill-stop:v1]"
# FALLBACK for is_real_user_turn, only for harnesses that do not stamp
# promptSource. Identifies THIS hook's feedback coming back through the
# transcript: it requires the marker to open a line, which is how the reason is
# emitted - the harness prefixes "Stop hook feedback:\n" before it. Searching for
# a loose MARKER is not enough: a user message that MENTIONS the hook ("explain
# this [grill-stop:v1] thing") is a real turn and must clear the accumulator.
# Matching on line start rather than on the prefix text keeps that true if the
# harness rewords the prefix.
FEEDBACK_RE = re.compile(r"^\s*" + re.escape(MARKER), re.M)
# The only origins that are a genuinely typed message. Everything else arriving
# with type=user is synthetic: a subagent's <task-notification> and a
# cross-session message come with promptSource="system", a skill injection and
# this hook's own feedback come with isMeta=true. Before this, the hook treated
# all of them as real turns, so a subagent finishing cleared the accumulator and
# killed the grill.
REAL_PROMPT_SOURCES = {"typed", "sdk"}
# A subagent writes into its own transcript, invisible to the parent. The
# completion notification carries the task-id, which names the file under
# <session>/subagents/.
TASK_ID_RE = re.compile(r"<task-id>(\w+)</task-id>")
SUB_TAG = " [subagent]"
# A cross-session message is another conversation driving this one, not a
# continuation of the same diff. It arrives as type=user with isMeta=true, so
# is_real_user_turn drops it and the accumulator never cleared: every peer-driven
# turn re-blocked with the SAME stale list, and the escape valve was out of
# reach. It clears the list, but only once that list has already been grilled - a
# peer message landing MID-turn, between two writes, must not erase writes nobody
# has been asked about yet. It deliberately does not touch `muted`: the escape
# valve is the user's, not a peer's.
CROSS_RE = re.compile(r"<cross-session-message\b")
# Per-turn escape valve. Both phrases work: the English one for anyone reading
# this file, the Portuguese one because it is what the author's fingers type.
# The Portuguese form demands the exact imperative, so "como faco pra parar com o
# grill?" does NOT match - asking about the escape is not using it. English has no
# such split (the question and the command read the same), so "how do I stop the
# grill?" does mute, for that one turn. \s+ tolerates line breaks.
MUTE_RE = re.compile(r"(?:stop\s+the\s+grill|pare\s+com\s+o\s+grill)", re.I)


def user_text(obj):
    """Text of a type=user entry, or "" when it is not a message.
    A tool result comes back as type=user too, and does not count."""
    if obj.get("type") != "user":
        return ""
    content = obj.get("message", obj).get("content", "")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        return " ".join(
            c.get("text", "")
            for c in content
            if isinstance(c, dict) and c.get("type") == "text"
        ).strip()
    return ""


def is_real_user_turn(obj, text):
    """Is this type=user entry a typed message, and not a synthetic entry?

    Only a real turn clears the accumulator. Subagent notifications,
    cross-session messages, skill injections and this hook's own feedback all
    arrive as type=user and have to pass through untouched."""
    if obj.get("isMeta"):
        return False
    ps = obj.get("promptSource")
    if ps is not None:
        return ps in REAL_PROMPT_SOURCES
    return not FEEDBACK_RE.search(text)


def add_writes(content, touched, tag=""):
    """Append to `touched` the files written by the tool_use blocks of `content`."""
    if not isinstance(content, list):
        return
    for c in content:
        if not isinstance(c, dict) or c.get("type") != "tool_use":
            continue
        name = c.get("name")
        inp = c.get("input") or {}
        if name in WRITE_TOOLS:
            hits = [inp.get("file_path", "")]
        elif name == "Bash":
            hits = [
                p
                for p in BASH_WRITE_RE.findall(inp.get("command", ""))
                if not p.startswith("/dev/")
            ]
        else:
            continue
        for fp in hits:
            if not fp:
                continue
            entry = os.path.basename(fp) + tag
            if entry not in touched:
                touched.append(entry)


def add_transcript_writes(path, touched, tag=""):
    """Same, over a whole transcript. Used for subagents, which have no user-turn
    logic - their whole execution is the window."""
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("type") == "assistant":
                add_writes(obj.get("message", obj).get("content", ""), touched, tag)


def scan(path):
    """(files written since the last real user message, muted, task-ids of the
    subagents that finished in that window), in a single pass."""
    touched = []
    tasks = []
    muted = False
    grilled = False
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            text = user_text(obj)
            if text:
                if is_real_user_turn(obj, text):
                    touched = []
                    tasks = []
                    muted = bool(MUTE_RE.search(text))
                    grilled = False
                elif FEEDBACK_RE.search(text):
                    grilled = True
                elif grilled and CROSS_RE.search(text):
                    touched = []
                    tasks = []
                else:
                    tasks.extend(TASK_ID_RE.findall(text))
                continue
            if obj.get("type") == "assistant":
                before = len(touched)
                add_writes(obj.get("message", obj).get("content", ""), touched)
                if len(touched) > before:
                    grilled = False
    return touched, muted, tasks


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("stop_hook_active"):
        return 0
    if not os.path.exists(SENTINEL):
        return 0
    path = data.get("transcript_path")
    if not path:
        return 0
    try:
        touched, muted, tasks = scan(path)
    except Exception:
        return 0
    if muted:
        return 0

    # Every subagent that finished this turn has its own transcript under
    # <session>/subagents/agent-<task-id>.jsonl. A missing or unreadable file
    # (agent still running, unknown id) is skipped - it never clears the parent.
    sub_dir = os.path.splitext(path)[0] + "/subagents"
    for tid in tasks:
        try:
            add_transcript_writes(
                os.path.join(sub_dir, "agent-" + tid + ".jsonl"), touched, SUB_TAG
            )
        except Exception:
            continue

    if not touched:
        return 0

    shown = ", ".join(touched[:8])
    if len(touched) > 8:
        shown += " (+%d)" % (len(touched) - 8)
    reason = (
        MARKER + " This turn wrote code (" + shown + "). Before you finish, "
        "invert the review - instead of the user re-reading your diff, test "
        "their understanding of what you decided. Re-read your own diff and pull "
        "out the decisions that carry a domain or business rule: every "
        "conditional, guard clause, threshold, default, ordering, error path and "
        "side effect you chose without the user asking for it explicitly. Ignore "
        "what is mechanical (formatting, imports, renames). A file tagged "
        "[subagent] was written by an agent YOU dispatched: read its diff before "
        "asking, because the decisions it took are yours to defend.\n"
        "OUTPUT CONTRACT - your next message has to be ONLY a question, anchored "
        "at file:line, about the most consequential decision still unagreed. Ask "
        "it and stop, waiting for the answer. Forbidden in that message: (1) a "
        "menu of options (a)/(b)/(c), or any question that asks the user to "
        "CHOOSE - that delegates the decision instead of testing their "
        "understanding; (2) analysis, a summary of what you did, or an "
        "explanation before the question; (3) offering to run the interview "
        "instead of running it. A good question has a verifiable answer and you "
        "already know the right one, like: \"in x.py:42 the gate closes on A and "
        "B; does an input with A but no B pass or block, and why?\".\n"
        "If the answer differs from what you implemented, that is a requirements "
        "bug: point it out and fix it. When the decisions run out, close with a "
        "short summary of what was agreed. Only finish without asking if your "
        "immediately previous message IS that question, still unanswered.\n"
        "EXCEPTION - if you recognise none of the files listed above as a write "
        "of yours in this turn, say exactly that in one line and finish, without "
        "asking anything. Bash detection is a regex and it does fire on a write "
        "idiom that was only quoted as data; the giveaway is one or two letter "
        "names with no extension, which are sed flags, not files."
    )
    print(json.dumps({"decision": "block", "reason": reason}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
