# easy-tiger

A Claude Code plugin that catches scope creep before it happens.

When you're building with Claude Code, it's dangerously easy to keep asking for "one more thing" until your MVP becomes a 6-month project. **easy-tiger** is a chill teammate that taps you on the shoulder and asks *"do you actually need this?"* before you over-build.

It's not a blocker. It's a friend.

## What it does

**Automatic, in the background:** easy-tiger watches every non-trivial message you send. If it looks like scope creep, it interrupts lightly in character — *"Easy, tiger. Is this on the path to shipping, or a side quest?"* — and offers to park it for later.

**On demand:** `/easy-tiger:easy-tiger` gives you a deep, honest scope review of the whole project. Reads your goal, recent git activity, and the conversation so far. Tells you what to cut.

**Goal-aware:** easy-tiger figures out what you're shipping — from an explicit `.easy-tiger/goal.md`, or a `## Goal` section in your `CLAUDE.md`, or your git branch + linked issue, or it asks you once. No upfront configuration required.

## Install

### From the Claude Code marketplace (once published)

```
/plugin install easy-tiger
```

### From GitHub

```
/plugin marketplace add olapietka/easy-tiger
/plugin install easy-tiger@olapietka/easy-tiger
```

### For local development

```bash
git clone https://github.com/olapietka/easy-tiger.git
claude --plugin-dir ./easy-tiger
```

## Usage

### Just build normally

easy-tiger is silent when you're on-track. When it thinks you're drifting, it speaks up — once, briefly, in character. You can always say "no, I need this" and it steps aside.

### Set your goal (optional but recommended)

```
/easy-tiger:goal build a CLI that lints markdown files
```

View or clear it:

```
/easy-tiger:goal view
/easy-tiger:goal clear
```

If you don't set a goal explicitly, easy-tiger falls back to:
1. A `## Goal` section in `CLAUDE.md` or `AGENTS.md`
2. Your current git branch + linked issue (`gh issue view`)
3. Recent commit history
4. General mode (still catches obvious creep, just without a specific anchor)

### Get a deep review

```
/easy-tiger:easy-tiger
```

Or target a specific area:

```
/easy-tiger:easy-tiger the new websocket stuff
```

## How it works

- **`hooks/session-start.sh`** — On every session start, injects the easy-tiger persona and the inferred goal into Claude's context. Claude carries that awareness for the rest of the session.
- **`hooks/prompt-check.js`** — On every non-trivial user message, wraps it with a short evaluation prompt. Claude itself judges whether the message is on-goal or scope creep, using the full conversation context it already has. The hook never calls an LLM — it just injects context.
- **`skills/easy-tiger/SKILL.md`** — The manual deep-review skill. Reads everything, gives an honest take.
- **`skills/goal/SKILL.md`** — Lets you set, view, or clear the current goal.
- **`lib/personality.md`** — Source of truth for the easy-tiger voice. Hooks inline it because Claude Code hooks can't import shared files.

### Fast-path bypasses

easy-tiger skips evaluation entirely for:
- Slash commands (`/...`)
- Memorize messages (`#...`)
- Explicit user bypass (`*...`)
- Trivial messages (< 30 chars, "yes", "thanks", "fix typo", etc.)

So short conversational turns cost nothing.

### Two scenarios it catches

| Scenario | Example |
|----------|---------|
| **You initiate creep** | "While we're at it, let's also add dark mode" |
| **Claude proposes, you accept** | Claude: *"I'd also suggest adding caching."* You: *"Sure."* |

Both work because Claude reviews the conversation context — including its own previous turn — on every message.

## Philosophy

The problem isn't Claude. It's you (and me, and everyone). You keep saying *"while we're at it..."* and Claude happily obliges because that's its job.

easy-tiger is the friend who says *"do you really need that?"* before you spend 3 hours on a feature nobody asked for.

Ship small. Ship fast. Add more later.

## License

MIT
