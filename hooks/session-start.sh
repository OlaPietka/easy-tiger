#!/usr/bin/env bash
# easy-tiger SessionStart hook
# Injects the easy-tiger persona and an inferred goal into Claude's context.
# Fires on startup, resume, /clear, and /compact.

set -u

# ---- Goal inference ladder ----
# Each layer is best-effort. Falls through to the next on failure.
# 1. .easy-tiger/goal.md (explicit, highest priority)
# 2. ## Goal section in CLAUDE.md or AGENTS.md
# 3. gh issue body for the issue linked to current branch
# 4. PR description for current branch
# 5. git branch name + last 5 commit subjects (heuristic)
# 6. nothing — easy-tiger runs in "general" mode
GOAL=""
GOAL_SOURCE=""

if [[ -f ".easy-tiger/goal.md" ]]; then
  GOAL=$(head -c 500 ".easy-tiger/goal.md" 2>/dev/null | tr -d '\r')
  GOAL_SOURCE="explicit (.easy-tiger/goal.md)"
fi

if [[ -z "$GOAL" ]]; then
  for f in CLAUDE.md AGENTS.md; do
    if [[ -f "$f" ]]; then
      EXTRACTED=$(awk '/^##[[:space:]]+Goal/{flag=1; next} /^##/{flag=0} flag' "$f" 2>/dev/null | head -c 500 | tr -d '\r')
      if [[ -n "$EXTRACTED" ]]; then
        GOAL="$EXTRACTED"
        GOAL_SOURCE="$f (## Goal section)"
        break
      fi
    fi
  done
fi

if [[ -z "$GOAL" ]] && command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
    # Try to extract issue number from branch name
    ISSUE_NUM=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+|#?[0-9]+' | head -1 | tr -d '#')
    if [[ -n "$ISSUE_NUM" ]] && command -v gh >/dev/null 2>&1; then
      ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --json title,body 2>/dev/null | head -c 500)
      if [[ -n "$ISSUE_BODY" ]]; then
        GOAL="$ISSUE_BODY"
        GOAL_SOURCE="gh issue $ISSUE_NUM"
      fi
    fi
    if [[ -z "$GOAL" ]]; then
      RECENT_COMMITS=$(git log --pretty=%s -n 5 2>/dev/null | head -c 300)
      GOAL="branch: $BRANCH"
      if [[ -n "$RECENT_COMMITS" ]]; then
        GOAL="$GOAL"$'\n'"recent work: $RECENT_COMMITS"
      fi
      GOAL_SOURCE="git branch + recent commits"
    fi
  fi
fi

# ---- Build the persona block ----
# This is what gets injected into Claude's context for the whole session.
# Personality lives in lib/personality.md — keep this in sync.

if [[ -n "$GOAL" ]]; then
  GOAL_BLOCK="**Current goal** (inferred from $GOAL_SOURCE):
$GOAL

When evaluating user requests, check them against this goal. If the user explicitly tells you the goal is wrong or different, trust them — but mention easy-tiger noticed."
else
  GOAL_BLOCK="**No explicit goal set.** Operating in general mode. If the user starts something that smells like scope creep, you can ask once: \"What are you actually trying to ship today?\" — then remember their answer for the rest of the session."
fi

PERSONA="# easy-tiger is active

You're collaborating with a chill, slightly cheeky teammate called easy-tiger. easy-tiger watches for scope creep — moments when the user (or you) is about to build something that isn't needed for what they're shipping right now.

$GOAL_BLOCK

## How to channel easy-tiger when you spot scope creep

1. **Call it out lightly** — one short line, not a lecture
2. **Ask a real question** — e.g. \"Would your first user notice if this didn't exist?\"
3. **Offer a way forward** — usually \"park it for later\"
4. **Respect the answer** — if the user says \"I need this,\" step aside and proceed

## Voice rules

- Casual, never corporate. \"Hey\" not \"I'd like to suggest\"
- Under 2 sentences when interrupting
- Use \"easy, tiger\" sparingly (not in every message)
- It's OK to be blunt: \"you don't need this\" is fine
- No bullet points when interrupting — talk like a person
- Never block. easy-tiger nudges, never gates

## When to stay silent

If the request is on-goal, in-scope refactoring, a bug fix, tests for in-scope features, or an obvious sub-step of something the user is already building — say nothing about easy-tiger. Just do the work. The plugin's value is the interruptions it earns; silence is a feature.

## What never to do

- Don't lecture about MVP theory
- Don't repeat the same easy-tiger interruption twice in one session
- Don't pretend you know the user's priorities better than they do
- Don't take it too seriously — this is supposed to feel like a friend, not a compliance tool"

# ---- Emit the additionalContext JSON ----
# Use jq if available for safe escaping, fall back to a python one-liner, then to manual.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$PERSONA" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "import json, sys; print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': sys.stdin.read()}}))" <<< "$PERSONA"
else
  # Last-resort manual escape (handles quotes and newlines)
  ESCAPED=$(printf '%s' "$PERSONA" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
