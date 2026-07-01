---
name: chrome-devtools-mcp
description: Scaffolds a dedicated Chrome instance with an isolated, persistent profile plus a chrome-devtools-mcp (CDP) server registration, so Claude can inspect authenticated network traffic in a web app - list open tabs, navigate, and read real requests (method, URL, sensitive headers, body, response shape) to reverse-engineer an API. Use when the user wants to inspect authenticated traffic in a browser, capture real headers/cookies for an integration, reverse-engineer a web app's undocumented API, or asks to set up chrome-devtools-mcp / CDP debugging.
---

# chrome-devtools-mcp

Scaffolds the setup needed to inspect authenticated network traffic through
`chrome-devtools-mcp` (Google's official CDP MCP server - not Playwright). Generates:

- `scripts/launch-chrome.sh` - opens a dedicated Chrome instance with `--remote-debugging-port`
  and an isolated `--user-data-dir` profile that persists login state across runs.
- `docs/chrome-mcp-setup.md` - the usage flow: launch, log in once, register the MCP server,
  capture requests, turn them into probe scripts.
- `scripts/probe/` - dir (with a `.gitkeep`) where each captured request later becomes a
  minimal `fetch`-based reproduction script.

## When to use

- Reverse-engineering an app's API by watching what the browser actually sends when logged in.
- Capturing real `Authorization`/`Cookie`/CSRF headers to wire up an integration or MCP tool.
- Any task that needs `list_pages`, `navigate_page`, `get_network_requests`, or
  `evaluate_script` against an authenticated session.

**Do NOT use** when the target API is already documented, or when an existing
`scripts/launch-chrome.sh` / `docs/chrome-mcp-setup.md` is present for this project - diff
manually instead, this skill refuses to overwrite unless `FORCE=1`.

## Inputs to ask the user (in this order)

1. **Project slug (kebab-case)** - names the isolated profile dir (`~/.chrome-<slug>-profile`)
   and titles the doc.
2. **CDP port** - e.g. `9222`. Ask if another project's Chrome is already using it; each
   project should get its own port so instances don't collide.
3. **Start URL** - the app URL to open on launch (login page or the target feature).
4. **Target dir** - project root to scaffold into (default `.`).

## How to scaffold

Run the scaffold script from the **target project root**:

```bash
PROJECT=myapp PORT=9222 START_URL=https://app.example.com/login \
  TARGET_DIR=. ~/.claude/skills/chrome-devtools-mcp/scripts/scaffold.sh
```

The script:

1. Renders `templates/scripts/launch-chrome.sh.tmpl` to `scripts/launch-chrome.sh` (executable).
2. Renders `templates/docs/chrome-mcp-setup.md.tmpl` to `docs/chrome-mcp-setup.md`.
3. Creates `scripts/probe/` for later per-request reproduction scripts.
4. Refuses to overwrite existing files unless `FORCE=1`.

## Register the MCP server

Edit (or create) `.mcp.json` at the project root directly - merge into any existing
`mcpServers`, don't overwrite other entries:

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--browserUrl", "http://127.0.0.1:9222"]
    }
  }
}
```

Then tell the user to restart Claude Code so the tools (`list_pages`, `navigate_page`,
`get_network_requests`, `evaluate_script`, etc) appear.

## After scaffold

Tell the user, in order:

1. `./scripts/launch-chrome.sh` - opens the dedicated Chrome instance.
2. Log in manually (user/password/2FA) once in that window; the isolated profile keeps it
   logged in on later launches.
3. Restart Claude Code to pick up the new MCP server.
4. Use `list_pages` to confirm the right tab, then `get_network_requests` filtered by the
   target domain while exercising the feature.
5. For each interesting request, write a `scripts/probe/<name>.mjs` using plain `fetch`
   with the same headers, to validate reproducibility outside the browser before wrapping
   it as an MCP tool under `src/`.

Full walkthrough lives in the generated `docs/chrome-mcp-setup.md`.

## Known constraints baked in

- CDP is Chrome's own protocol - the MCP server talks straight to it, no Playwright layer.
- The isolated profile is the whole point: it is what makes login persist between runs
  without re-authenticating on every session.
- One port and one profile per project, so multiple projects' dedicated Chrome instances
  don't collide.

## Security notes

- The CDP port has no authentication of its own - it is only safe because it binds to
  localhost. Never expose it through a tunnel or a public interface.
- The profile dir (`~/.chrome-<project>-profile`) holds real session cookies. It lives
  outside the repo; never commit it, never let it sync through Dropbox/iCloud/etc.
- No token, cookie, or captured response body may enter the repo - not in probe scripts,
  not in commit messages, not in the generated doc.

## Common mistakes

| Mistake | Fix |
|--------|-----|
| Reusing one port/profile across projects | Give each project its own `PORT` and `PROJECT` slug; instances collide otherwise. |
| Overwriting another `.mcp.json` server entry | Merge the `chrome-devtools` key in, don't replace the whole file. |
| Committing a probe script with a real captured token | Read secrets from env vars or a gitignored local file, never hardcode them. |
| Forgetting to restart Claude Code after editing `.mcp.json` | New MCP tools only appear after a restart. |
