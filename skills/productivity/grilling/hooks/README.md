# grill-stop - the Stop hook behind `/grilling`

`/grilling` only runs when you ask for it. `grill-stop.py` is the deterministic
half: a Stop hook that blocks the end of any turn that wrote code and makes the
agent interview you about the domain decisions it just took on its own.

It is **opt-in twice over**. It is inert unless the sentinel file exists, and it
goes quiet for one turn when your message says "stop the grill" (or
"pare com o grill"), re-arming on the next message that does not.

```sh
touch ~/.claude/.grill-active    # arm it
rm ~/.claude/.grill-active       # disarm it
```

## Install

**As a plugin** - nothing to do. `hooks/hooks.json` at the plugin root registers
the Stop hook when the plugin is enabled.

**As a linked or copied skill** (`npx skills add`, `scripts/link-skills.sh`) -
add one entry to `~/.claude/settings.json`, pointing at the installed copy:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/skills/grilling/hooks/grill-stop.py"
          }
        ]
      }
    ]
  }
}
```

Only one of the two. Registering both makes every blocked turn print the same
reason twice.

## Test

```sh
bash skills/productivity/grilling/test/run.sh    # or: ./control drive grilling
```

34 assertions over synthetic transcripts, no framework and no network. The
sentinel it uses lives in a temp dir, so running it never touches your real one.
