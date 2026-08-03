# Skills For Real Engineers

My agent skills that I use every day to do real engineering — not vibe coding.

Developing real applications is hard. Approaches like GSD, BMAD, and Spec-Kit try to help by owning the process. But while doing so, they take away your control and make bugs in the process hard to resolve.

These skills are designed to be small, easy to adapt, and composable. They work with any model. They're based on decades of engineering experience. Hack around with them. Make them your own. Enjoy.

> **Credit.** This repo started as a fork of [Matt Pocock's skills](https://github.com/mattpocock/skills) (MIT licensed). Many of the engineering and productivity skills here are his original work, adapted for my own workflow. Thanks and full credit to Matt — see [`LICENSE`](./LICENSE).

## Quickstart (30-second setup)

1. Run the installer:

```bash
npx skills@latest add mauriciovieira/skills
```

2. Pick the skills you want, and which coding agents you want to install them on. **Make sure you select `/setup-mauricio-vieira-skills`**.

3. Run `/setup-mauricio-vieira-skills` in your agent. It will:
   - Ask you which issue tracker you want to use (GitHub, GitLab, local markdown, or another workflow you describe)
   - Ask you what labels you apply to tickets when you triage them
   - Ask you where you want to save any docs we create

4. Bam - you're ready to go.

## Why These Skills Exist

I built these skills as a way to fix common failure modes I see with Claude Code, Codex, and other coding agents.

### #1: The Agent Didn't Do What I Want

> "No-one knows exactly what they want"
>
> David Thomas & Andrew Hunt, [The Pragmatic Programmer](https://www.amazon.co.uk/Pragmatic-Programmer-Anniversary-Journey-Mastery/dp/B0833F1T3V)

**The Problem**. The most common failure mode in software development is misalignment. You think the dev knows what you want. Then you see what they've built - and you realize it didn't understand you at all.

This is just the same in the AI age. There is a communication gap between you and the agent. The fix for this is a **grilling session** - getting the agent to ask you detailed questions about what you're building.

**The Fix** is [`/grill-me`](./skills/productivity/grill-me/SKILL.md) - or [`/grill-with-docs`](./skills/engineering/grill-with-docs/SKILL.md), which does the same but also sharpens the project's domain docs as it goes. [`/triage`](./skills/engineering/triage/SKILL.md) grills out under-specified issues before they reach an agent, and [`/improve-codebase-architecture`](./skills/engineering/improve-codebase-architecture/SKILL.md) grills through a chosen refactor candidate before touching code.

Use them _every_ time you want to align with the agent before making a change. The same primitives, wrapped in a full spec-driven-development flow, live in [groundwork](https://github.com/mauriciovieira/groundwork).

### #2: The Agent Is Way Too Verbose

> With a ubiquitous language, conversations among developers and expressions of the code are all derived from the same domain model.
>
> Eric Evans, [Domain-Driven-Design](https://www.amazon.co.uk/Domain-Driven-Design-Tackling-Complexity-Software/dp/0321125215)

**The Problem**: At the start of a project, devs and the people they're building the software for (the domain experts) are usually speaking different languages.

I felt the same tension with my agents. Agents are usually dropped into a project and asked to figure out the jargon as they go. So they use 20 words where 1 will do.

**The Fix** for this is a shared language. It's a document that helps agents decode the jargon used in the project.

<details>
<summary>
Example
</summary>

Here's an example [`CONTEXT.md`](https://github.com/mattpocock/course-video-manager/blob/076a5a7a182db0fe1e62971dd7a68bcadf010f1c/CONTEXT.md), from Matt Pocock's `course-video-manager` repo. Which one is easier to read?

- **BEFORE**: "There's a problem when a lesson inside a section of a course is made 'real' (i.e. given a spot in the file system)"
- **AFTER**: "There's a problem with the materialization cascade"

This concision pays off session after session.

</details>

This is built into [`/domain-modeling`](./skills/engineering/domain-modeling/SKILL.md) and [`/grill-with-docs`](./skills/engineering/grill-with-docs/SKILL.md). As they walk you through a decision, they keep a project glossary sharpened with the terminology you settle on, and document hard-to-explain decisions as ADRs.

It's hard to explain how powerful this is. It might be the single coolest technique in this repo. Try it, and see.

> [!TIP]
> A shared language has many other benefits than reducing verbosity:
>
> - **Variables, functions and files are named consistently**, using the shared language
> - As a result, the **codebase is easier to navigate** for the agent
> - The agent also **spends fewer tokens on thinking**, because it has access to a more concise language

### #3: The Code Doesn't Work

> "Always take small, deliberate steps. The rate of feedback is your speed limit. Never take on a task that’s too big."
>
> David Thomas & Andrew Hunt, [The Pragmatic Programmer](https://www.amazon.co.uk/Pragmatic-Programmer-Anniversary-Journey-Mastery/dp/B0833F1T3V)

**The Problem**: Let's say that you and the agent are aligned on what to build. What happens when the agent _still_ produces crap?

It's time to look at your feedback loops. Without feedback on how the code it produces actually runs, the agent will be flying blind.

**The Fix**: You need the usual tranche of feedback loops: static types, browser access, and automated tests.

For automated tests, a red-green-refactor loop is critical. This is where the agent writes a failing test first, then fixes the test. This helps give the agent a consistent level of feedback that results in far better code.

I've built a **[`/tdd`](./skills/engineering/tdd/SKILL.md) skill** you can slot into any project. It encourages red-green-refactor and gives the agent plenty of guidance on what makes good and bad tests.

For debugging, I've also built a **[`/diagnosing-bugs`](./skills/engineering/diagnosing-bugs/SKILL.md)** skill that wraps best debugging practices into a simple loop.

### #4: We Built A Ball Of Mud

> "Invest in the design of the system _every day_."
>
> Kent Beck, [Extreme Programming Explained](https://www.amazon.co.uk/Extreme-Programming-Explained-Embrace-Change/dp/0321278658)

> "The best modules are deep. They allow a lot of functionality to be accessed through a simple interface."
>
> John Ousterhout, [A Philosophy Of Software Design](https://www.amazon.co.uk/Philosophy-Software-Design-2nd/dp/173210221X)

**The Problem**: Most apps built with agents are complex and hard to change. Because agents can radically speed up coding, they also accelerate software entropy. Codebases get more complex at an unprecedented rate.

**The Fix** for this is a radical new approach to AI-powered development: caring about the design of the code.

This is built in to every layer of these skills:

- [`/codebase-design`](./skills/engineering/codebase-design/SKILL.md) gives the agent the vocabulary for designing deep modules
- [`/zoom-out`](./skills/engineering/zoom-out/SKILL.md) tells the agent to explain code in the context of the whole system

And crucially, [`/improve-codebase-architecture`](./skills/engineering/improve-codebase-architecture/SKILL.md) helps you rescue a codebase that has become a ball of mud. I recommend running it on your codebase once every few days.

### Summary

Software engineering fundamentals matter more than ever. These skills are my best effort at condensing these fundamentals into repeatable practices, to help you ship the best apps of your career. Enjoy.

## Reference

### Engineering

Skills I use daily for code work.

- **[ansible-kamal](./skills/engineering/ansible-kamal/SKILL.md)** — Scaffold an Ansible + Kamal 2 infrastructure tree for a Rails app on an Ubuntu VPS (hardened baseline, host PostgreSQL, kamal-proxy on 80/443), with staging+production or single-domain modes.
- **[babysit-with-github-copilot](./skills/engineering/babysit-with-github-copilot/SKILL.md)** — Drive a PR from open to merged in tight 5-minute cycles around GitHub Copilot review feedback, then clean up the branch/worktree.
- **[chrome-devtools-mcp](./skills/engineering/chrome-devtools-mcp/SKILL.md)** - Scaffold a dedicated Chrome instance with an isolated login-persisting profile and a chrome-devtools-mcp (CDP) registration, to inspect authenticated network traffic and turn captured requests into reproducible probe scripts.
- **[code-review](./skills/engineering/code-review/SKILL.md)** — Two-axis review of the diff since a fixed point: **Standards** (does it follow the repo's coding standards, plus a Fowler smell baseline?) and **Spec** (does it faithfully implement the originating issue/PRD?), run as parallel sub-agents.
- **[codebase-design](./skills/engineering/codebase-design/SKILL.md)** — Shared discipline and vocabulary for designing deep modules: small interfaces, clean seams, testable through the interface.
- **[creative-constraints](./skills/engineering/creative-constraints/SKILL.md)** - Roll a machine-random set of binding design constraints before any UI/web design work, so no two sessions converge on the same generic, templated layout.
- **[diagnosing-bugs](./skills/engineering/diagnosing-bugs/SKILL.md)** — Disciplined diagnosis loop for hard bugs and performance regressions: reproduce → minimise → hypothesise → instrument → fix → regression-test.
- **[domain-modeling](./skills/engineering/domain-modeling/SKILL.md)** — Actively build and sharpen a project's domain model — challenge terms, stress-test with scenarios, update `CONTEXT.md` and ADRs inline.
- **[grill-with-docs](./skills/engineering/grill-with-docs/SKILL.md)** — Grilling session that also builds your project's domain model, sharpening terminology and updating `CONTEXT.md` and ADRs inline.
- **[implement](./skills/engineering/implement/SKILL.md)** — Build the work described by a spec or set of tickets, driving `/tdd` at pre-agreed seams and closing out with `/code-review` before committing.
- **[improve-codebase-architecture](./skills/engineering/improve-codebase-architecture/SKILL.md)** — Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
- **[prototype](./skills/engineering/prototype/SKILL.md)** — Build a throwaway prototype to flesh out a design — either a runnable terminal app for state/business-logic questions, or several radically different UI variations toggleable from one route.
- **[research](./skills/engineering/research/SKILL.md)** — Investigate a question against high-trust primary sources and capture the findings as a cited Markdown file in the repo, run as a background agent.
- **[resolving-merge-conflicts](./skills/engineering/resolving-merge-conflicts/SKILL.md)** — Work through an in-progress git merge or rebase conflict hunk by hunk, resolving by intent traced to each side's primary source, then finish the operation — never `--abort`.
- **[setup-mauricio-vieira-skills](./skills/engineering/setup-mauricio-vieira-skills/SKILL.md)** — Scaffold the per-repo config (issue tracker, triage label vocabulary, domain doc layout) that the other engineering skills consume. Run once per repo before using `diagnosing-bugs`, `tdd`, or `zoom-out`.
- **[setup-worktree](./skills/engineering/setup-worktree/SKILL.md)** — Bootstrap a linked git worktree from its main repo by symlinking language-agnostic dependency dirs (node_modules, .venv, vendor, target, deps) and copying env files.
- **[tdd](./skills/engineering/tdd/SKILL.md)** — Test-driven development with a red-green-refactor loop. Builds features or fixes bugs one vertical slice at a time.
- **[to-spec](./skills/engineering/to-spec/SKILL.md)** — Turn the current conversation into a spec and publish it to the issue tracker.
- **[to-tickets](./skills/engineering/to-tickets/SKILL.md)** — Break any plan, spec, or conversation into a set of tracer-bullet tickets, each declaring its blocking edges — text in a local file, or native blocking links on a real tracker.
- **[triage](./skills/engineering/triage/SKILL.md)** — Move issues through a state machine of triage roles.
- **[wayfinder](./skills/engineering/wayfinder/SKILL.md)** — Plan a huge chunk of work — more than one agent session can hold — as a shared map of decision tickets on the issue tracker, resolved one at a time until the way to the destination is clear.
- **[zoom-out](./skills/engineering/zoom-out/SKILL.md)** — Tell the agent to zoom out and give broader context or a higher-level perspective on an unfamiliar section of code.

### Productivity

General workflow tools, not code-specific.

- **[grill-me](./skills/productivity/grill-me/SKILL.md)** — Get relentlessly interviewed about a plan or design until every branch of the decision tree is resolved.
- **[grilling](./skills/productivity/grilling/SKILL.md)** — Interview the user relentlessly about a plan, decision, or idea until every branch of the decision tree is resolved.
- **[handoff](./skills/productivity/handoff/SKILL.md)** — Compact the current conversation into a handoff document so another agent can continue the work.
- **[teach](./skills/productivity/teach/SKILL.md)** — Teach the user a new skill or concept over multiple sessions, using the current directory as a stateful teaching workspace.
- **[writing-great-skills](./skills/productivity/writing-great-skills/SKILL.md)** — Reference for writing and editing skills well: the vocabulary and principles that make a skill predictable.

### Misc

Tools I keep around but rarely use.

- **[git-guardrails-claude-code](./skills/misc/git-guardrails-claude-code/SKILL.md)** — Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, etc.) before they execute.
- **[migrate-to-shoehorn](./skills/misc/migrate-to-shoehorn/SKILL.md)** — Migrate test files from `as` type assertions to @total-typescript/shoehorn.
- **[scaffold-exercises](./skills/misc/scaffold-exercises/SKILL.md)** — Create exercise directory structures with sections, problems, solutions, and explainers.
- **[setup-pre-commit](./skills/misc/setup-pre-commit/SKILL.md)** — Set up Husky pre-commit hooks with lint-staged, Biome, type checking, and tests.
- **[sync-dotfiles](./skills/misc/sync-dotfiles/SKILL.md)** — Sync local agent/editor config (e.g. `~/.claude/`, `~/.cursor/`) into a dotfiles git repo, show the diff, and prompt for a commit. Asks for your dotfiles dir and which sources to sync.
