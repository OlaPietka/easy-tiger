#!/usr/bin/env node

// easy-tiger UserPromptSubmit hook
// Wraps the user's prompt with a brief evaluation block, delegating the actual
// scope-creep judgment to Claude (which already has the conversation context).
//
// Pattern borrowed from claude-code-prompt-improver: the hook never decides
// anything itself — it just injects context. Zero LLM calls, zero latency cost
// beyond a tiny stdin read.
//
// Fast-path bypasses skip the wrapping entirely for trivial prompts.

const fs = require("fs");
const path = require("path");

// Always exit 0. Hooks must NEVER crash the session.
process.on("uncaughtException", () => {
  try { console.log(JSON.stringify({})); } catch {}
  process.exit(0);
});

function emit(obj) {
  try { console.log(JSON.stringify(obj)); } catch {}
  process.exit(0);
}

function passthrough() {
  // Empty output = no modification, prompt flows unchanged
  emit({});
}

function inject(additionalContext) {
  emit({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext,
    },
  });
}

// ---- Read input ----
let input;
try {
  input = JSON.parse(fs.readFileSync("/dev/stdin", "utf8"));
} catch {
  passthrough();
}

const prompt = (input.prompt || "").trim();
if (!prompt) passthrough();

// ---- Fast-path bypasses ----
// Skip the evaluation entirely for these — they're either system commands,
// user-explicit bypasses, or too short to be meaningful scope decisions.

// 1. Slash commands (incl. /easy-tiger:* itself)
if (prompt.startsWith("/")) passthrough();

// 2. Memorize feature
if (prompt.startsWith("#")) passthrough();

// 3. Explicit bypass: user prefixes with `*`
if (prompt.startsWith("*")) passthrough();

// 4. Trivial messages (acknowledgments, single words, short corrections)
if (prompt.length < 30) passthrough();

// 5. Obviously not a feature request — common conversational patterns
const TRIVIAL_PATTERNS = [
  /^(yes|no|yeah|nope|sure|ok|okay|thanks|thank you|cool|got it|nice|perfect|great)\b/i,
  /^(fix|correct) (the|this|that) typo/i,
  /^(why|what|how|where|when) (does|did|do|is|are|will)/i, // questions, usually conversational
  /^(can you (explain|show|tell)|please explain)/i,
  /^(continue|keep going|proceed|go on)\b/i,
];
if (TRIVIAL_PATTERNS.some((re) => re.test(prompt))) passthrough();

// ---- Check the "asked goal" flag (don't ask twice per session) ----
// State lives in CLAUDE_PLUGIN_DATA if available, scoped per session.
let alreadyAskedGoal = false;
try {
  const dataDir = process.env.CLAUDE_PLUGIN_DATA;
  const sessionId = input.session_id || "default";
  if (dataDir) {
    const flagPath = path.join(dataDir, `asked-${sessionId}.flag`);
    alreadyAskedGoal = fs.existsSync(flagPath);
  }
} catch {
  // ignore — worst case we ask twice
}

// ---- Build the evaluation wrapper ----
// This text gets prepended to Claude's view of the user's prompt as additionalContext.
// The persona instructions were already injected at SessionStart, so we don't repeat
// them here — we just give Claude a small focused nudge for THIS prompt.

const wrapper = `[easy-tiger scope check]

The user's next message is below. Before acting on it, briefly think:

1. Is this on-goal, a small detour, or a side quest?
   - On-goal or obvious sub-step: just do the work, don't mention easy-tiger
   - Small detour the user clearly needs: do it, but flag it lightly ("ok, slight detour from the goal — doing it")
   - Side quest / scope creep: respond in your easy-tiger voice — one short interruption, ask if they really need this for shipping, offer to park it

2. Has easy-tiger already interrupted in this session? If yes, don't repeat the same interruption — pick a different angle or just do the work.

${alreadyAskedGoal ? "" : "3. If no goal is set in this session and this message looks like real feature work, you may ask once: \"Quick check — what are you actually trying to ship today?\" Then remember the answer."}

Remember: silence is a feature. Most messages should pass through with no easy-tiger commentary at all. Only interrupt when you're genuinely catching scope creep.

---

User message:
${prompt}`;

inject(wrapper);
