#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Smoke test for the grill-stop Stop hook. Run: python3 test_grill_stop.py

No framework, on purpose - just asserts. Covers every gate and the accumulator.
The sentinel lives in a temp dir (GRILL_SENTINEL), so running this never touches
the real ~/.claude/.grill-active.
"""
import json
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "..", "hooks", "grill-stop.py")
SENT = os.path.join(tempfile.mkdtemp(), ".grill-active")
open(SENT, "w").close()
ABSENT = SENT + "-absent"
MARKER = "[grill-stop:v1]"


def tr(lines):
    f = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8")
    for l in lines:
        f.write(json.dumps(l) + "\n")
    f.close()
    return f.name


def run(path, active=True, stop_active=False):
    env = dict(os.environ, GRILL_SENTINEL=SENT if active else ABSENT)
    return subprocess.run(
        ["python3", HOOK],
        input=json.dumps({"transcript_path": path, "stop_hook_active": stop_active}),
        capture_output=True, text=True, env=env,
    ).stdout.strip()


user = lambda t: {"type": "user", "message": {"content": t}}
typed = lambda t: {"type": "user", "promptSource": "typed", "message": {"content": t}}
notif = lambda tid: {"type": "user", "promptSource": "system", "message": {"content":
    "<task-notification>\n<task-id>" + tid + "</task-id>\n</task-notification>"}}
cross = lambda t: {"type": "user", "promptSource": "system", "isMeta": True, "message": {"content":
    "Another Claude session sent a message:\n<cross-session-message from=\"uds:/tmp/x.sock\">\n"
    + t + "\n</cross-session-message>"}}
meta = lambda t: {"type": "user", "isMeta": True, "message": {"content": t}}
feedback = user("Stop hook feedback:\n" + MARKER + " This turn wrote code (x.py). ...")
tool_res = {"type": "user", "message": {"content": [{"type": "tool_result", "content": "ok"}]}}
edit = lambda p: {"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}}
read = {"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": "Read", "input": {"file_path": "/x/z.py"}}]}}
bash = lambda cmd: {"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}
says = lambda t: {"type": "assistant", "message": {"content": [{"type": "text", "text": t}]}}


def blocked(out):
    return json.loads(out)["reason"] if out else None


def files_in(reason):
    """Only the file list in the header - the body of the reason mentions
    [subagent] as an instruction, so asserting over the whole reason would give a
    false positive."""
    return reason.split("wrote code (", 1)[1].split(")", 1)[0]


# --- gates ---------------------------------------------------------------
r = blocked(run(tr([user("do X"), edit("/x/auth.py"), tool_res])))
assert r and "auth.py" in r, r                                   # 1 edited -> blocks
r = blocked(run(tr([user("do X"), edit("/x/auth.py"), tool_res, read, tool_res])))
assert r and "auth.py" in r, r                                   # 2 tool_result does not clear
assert run(tr([user("what does Y do?"), read, tool_res])) == ""  # 3 read only
assert run(tr([user("do X"), edit("/x/a.py"), tool_res,
               user("and now?"), read])) == ""                   # 4 edit from a previous turn
assert run(tr([user("do X"), edit("/x/a.py")]), active=False) == ""       # 5 no sentinel
assert run(tr([user("do X"), edit("/x/a.py")]), stop_active=True) == ""   # 6 loop guard
assert run("/does/not/exist.jsonl") == ""                        # 7 fail open

# --- the hook's own feedback vs a real turn --------------------------------
r = blocked(run(tr([user("do X"), edit("/x/a.py"), feedback,
                    says("question?"), user("yes"), edit("/x/b.py")])))
assert r and "b.py" in r and "a.py" not in r, r      # 8 a real turn clears the accumulator
r = blocked(run(tr([user("do X"), edit("/x/a.py"), feedback, edit("/x/b.py")])))
assert r and "a.py" in r and "b.py" in r, r          # 9 feedback does NOT clear it
r = blocked(run(tr([user("do X"), edit("/x/a.py"),
                    user("explain this " + MARKER), edit("/x/b.py")])))
assert r and "b.py" in r and "a.py" not in r, r      # 10 mentioning the hook is a real turn

# --- no ceiling: N previous blocks do not silence the hook ----------------
seq = [user("do X")]
for _ in range(6):
    seq += [edit("/x/a.py"), feedback]
seq += [user("again"), edit("/x/c.py")]
r = blocked(run(tr(seq)))
assert r and "c.py" in r, r                          # 11 still blocking

# --- escape valve: "stop the grill" / "pare com o grill" ------------------
assert run(tr([user("do X, and pare com o grill"), edit("/x/a.py")])) == ""  # 12 silences
assert run(tr([user("do X\nPare  com\no  grill"), edit("/x/a.py")])) == ""   # 13 case and breaks
assert run(tr([user("do X, stop the grill"), edit("/x/a.py")])) == ""        # 14 English phrase
r = blocked(run(tr([user("do X, stop the grill"), edit("/x/a.py"),
                    user("carry on"), edit("/x/b.py")])))
assert r and "b.py" in r, r                          # 15 re-arms on the next turn
r = blocked(run(tr([user("como faço pra parar com o grill?"), edit("/x/a.py")])))
assert r and "a.py" in r, r                          # 16 the pt infinitive does not silence

# --- writing via Bash (auto mode writes with sed/heredoc/redirect) --------
r = blocked(run(tr([user("do X"), bash("sed -i '' s/a/b/ ~/.claude/hooks/g.py")])))
assert r and "g.py" in r, r                          # 17 sed -i fires
r = blocked(run(tr([user("do X"), bash("cat > /x/new.md <<'EOF'\nhi\nEOF")])))
assert r and "new.md" in r, r                        # 18 heredoc with redirect fires
r = blocked(run(tr([user("do X"), bash("echo hi | tee -a ./notes.txt")])))
assert r and "notes.txt" in r, r                     # 19 tee fires
assert run(tr([user("commit it"), bash(
    "git commit -m \"$(cat <<'EOF'\nfix: x\nEOF\n)\"")])) == ""   # 20 commit heredoc does not
assert run(tr([user("status"), bash("git status && ls -la")])) == ""      # 21 reading does not
assert run(tr([user("run it"), bash("make test > /dev/null 2>&1")])) == ""  # 22 /dev/null does not
assert run(tr([user("run it"), bash(
    "python3 -c 'print(1 if x > 5 else 0)'")])) == ""                      # 23 comparison does not
assert run(tr([user("scan for secrets"), bash(
    r"git show HEAD:$f | sed -E 's/(ghp_)[A-Za-z0-9_]+/\1<REDACTED>/g'")])) == ""
#                                                      24 <PLACEHOLDER>/ is not a redirect

# --- synthetic type=user entries do not clear the accumulator -------------
r = blocked(run(tr([user("do X"), edit("/x/a.py"), notif("abc"), edit("/x/b.py")])))
assert r and "a.py" in r and "b.py" in r, r          # 25 task-notification does not clear
r = blocked(run(tr([user("do X"), edit("/x/a.py"),
                    meta("Base directory for this skill: /y"), edit("/x/b.py")])))
assert r and "a.py" in r and "b.py" in r, r          # 26 skill injection does not clear
r = blocked(run(tr([user("do X"), edit("/x/a.py"),
                    typed("now something else"), edit("/x/b.py")])))
assert r and "b.py" in r and "a.py" not in r, r      # 27 promptSource=typed clears
assert run(tr([typed("do X, stop the grill"), edit("/x/a.py")])) == ""  # 28 mute on a typed turn

# --- cross-session messages ----------------------------------------------
assert run(tr([typed("do X"), edit("/x/a.py"), feedback, says("question?"),
               cross("carry on")])) == ""            # 29 a grilled list clears on a peer message
r = blocked(run(tr([typed("do X"), edit("/x/a.py"),
                    cross("also do Y"), edit("/x/b.py")])))
assert r and "a.py" in r and "b.py" in r, r          # 30 mid-turn peer message keeps both
r = blocked(run(tr([typed("do X"), edit("/x/a.py"),
                    cross("pare com o grill"), edit("/x/b.py")])))
assert r and "a.py" in r, r                          # 31 a peer cannot use the escape valve

# --- subagent writes (own transcript, invisible to the parent) ------------
import shutil
base = tempfile.mkdtemp()
parent = os.path.join(base, "sess.jsonl")
subdir = os.path.join(base, "sess", "subagents")
os.makedirs(subdir)
with open(os.path.join(subdir, "agent-abc.jsonl"), "w") as fh:
    fh.write(json.dumps(edit("/w/prd.md")) + "\n")


def write(path, lines):
    with open(path, "w") as fh:
        for l in lines:
            fh.write(json.dumps(l) + "\n")


write(parent, [typed("do X"), {"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": "Agent", "input": {}}]}}, notif("abc")])
r = blocked(run(parent))
assert r and "prd.md [subagent]" in files_in(r), r   # 32 the subagent's write counts

write(parent, [typed("do X"), notif("abc"), typed("something else")])
assert run(parent) == ""                             # 33 a notif before a real turn does not count

write(parent, [typed("do X"), edit("/x/a.py"), notif("missing")])
r = blocked(run(parent))
assert r and files_in(r) == "a.py", files_in(r)      # 34 a missing file does not break it
shutil.rmtree(base)

print("34/34 OK")
