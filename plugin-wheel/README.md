# Wheel

Hook-based workflow engine for Claude Code agent pipelines.

Wheel replaces LLM-as-router orchestration with a deterministic state machine. Workflows are JSON files; step sequencing is driven entirely by Claude Code hooks. The LLM executes step instructions but never decides what to do next.

## Install

```bash
npx @yoshisada/wheel init
```

This creates:
- `.wheel/` -- runtime state directory (gitignored)
- `workflows/` -- workflow definition directory
- `.claude/settings.json` -- hook configuration (merged, not overwritten)

## Workflow Format

Workflows are JSON files in `workflows/`. Each file defines an ordered list of steps:

```json
{
  "name": "my-workflow",
  "version": "1.0.0",
  "steps": [
    {
      "id": "step-1",
      "type": "command",
      "command": "echo hello"
    },
    {
      "id": "step-2",
      "type": "agent",
      "instruction": "Analyze the output from step 1 and write a summary.",
      "context_from": ["step-1"]
    }
  ]
}
```

### Step Types

| Type | Description |
|------|-------------|
| `agent` | LLM executes the instruction. Engine injects it via Stop hook. |
| `command` | Shell command executed directly in the hook. No LLM involvement. |
| `parallel` | Fan-out: multiple agents run concurrently. Fan-in when all complete. |
| `approval` | Blocks until human approves. |
| `branch` | Evaluate a shell condition, jump to a target step ID. |
| `loop` | Repeat a substep until condition met or max iterations reached. |

### Step Fields

| Field | Types | Description |
|-------|-------|-------------|
| `id` | all | Unique step identifier (required) |
| `type` | all | Step type (required) |
| `instruction` | agent | What the agent should do |
| `command` | command | Shell command to execute |
| `agents` | parallel | Array of agent_type strings |
| `agent_instructions` | parallel | Map of agent_type to instruction |
| `condition` | branch, loop | Shell expression to evaluate |
| `if_zero` | branch | Step ID to jump to if condition exits 0 |
| `if_nonzero` | branch | Step ID to jump to if condition exits non-0 |
| `max_iterations` | loop | Maximum loop iterations |
| `on_exhaustion` | loop | `fail` or `continue` (default: `fail`) |
| `substep` | loop | Nested step definition (agent or command) |
| `context_from` | agent | Array of step IDs whose output to inject |
| `output` | all | Path or key for step output capture |
| `message` | approval | Message to display at approval gate |
| `allow_user_input` | agent, loop, branch | If `true`, the step may pause at runtime for user input via `wheel flag-needs-input`. Default `false`. Rejected by validator on `type: command`. |

## User Input (pause for the user mid-workflow)

Two primitives let an agent step stall for the user without the Stop hook spamming reminders:

1. **Authoring-time permission** — set `allow_user_input: true` on the step. This is a declaration that pausing is allowed; it does NOT force a pause.
2. **Runtime decision** — inside the agent's turn, run `wheel flag-needs-input "<short reason>"` (or the absolute-path form `plugin-wheel/bin/wheel-flag-needs-input "<short reason>"`). The CLI writes `awaiting_user_input: true` on the current step; the Stop hook stays silent until the agent writes the step's output file. When the output file is written, the flag auto-clears and the workflow advances.

Denials (all exit 1, state untouched):

- Step is missing `allow_user_input: true` → `step '<id>' does not permit user input — finish with the context you have`
- `WHEEL_NONINTERACTIVE=1` in env → `non-interactive mode: user input disabled`
- Another workflow is already awaiting input → `another workflow is waiting on user input: <name> / <step>`

### Example

```json
{
  "name": "my-workflow",
  "steps": [
    {
      "id": "clarify",
      "type": "agent",
      "allow_user_input": true,
      "output": ".wheel/outputs/clarify.json",
      "instruction": "Resolve the 4 open questions. For any that can't be inferred from repo state, ask the user: output the question, then run `wheel flag-needs-input \"clarifications needed\"`. Once the user replies, write their answers to .wheel/outputs/clarify.json."
    }
  ]
}
```

### Related commands

- `/wheel:wheel-skip` — abandon a stalled interactive step. Writes a cancel sentinel (`{"cancelled": true, "reason": "user-skipped"}`) and clears the flag.
- `/wheel:wheel-status` — shows any `[awaiting input]` rows with reason + elapsed time.

## State

Runtime state is stored in `.wheel/state.json`. It tracks:
- Current step cursor
- Per-step status (pending, working, done, failed)
- Per-agent status within parallel steps
- Step outputs and command logs

State survives crashes. On session resume, the engine reads state.json and continues from the last completed step.

## Hooks

Wheel uses 6 Claude Code hooks:

| Hook | Purpose |
|------|---------|
| `Stop` | Inject next step instruction; block stop if workflow incomplete |
| `TeammateIdle` | Gate agents with step-specific tasks |
| `SubagentStart` | Inject context from previous steps |
| `SubagentStop` | Mark agents done; advance on parallel fan-in |
| `SessionStart(resume)` | Reload state and resume from last step |
| `PostToolUse(Bash)` | Log commands to audit trail |

## Per-step model selection

Agent steps support an optional `model:` field that selects the model the spawned agent will run on.

```json
{
  "id": "classify-tags",
  "type": "agent",
  "model": "haiku",
  "instruction": "Classify these entries into one of four buckets..."
}
```

Accepted values:

| Value | Resolves to |
|-------|-------------|
| `"haiku"` | project-default haiku id (`plugin-wheel/scripts/dispatch/model-defaults.json`) |
| `"sonnet"` | project-default sonnet id |
| `"opus"` | project-default opus id |
| `"claude-..."` | explicit model id — passed through if it matches `^claude-[a-z0-9-]+$` |

Rules of thumb:

- **haiku** for classification / pattern-match / routing steps — cheap and fast.
- **sonnet** for synthesis, drafting, and most multi-file work — the default balance.
- **opus** only for hard reasoning (architecture decisions, thorny debugging, long-context synthesis where the cost is justified).

Guarantees:

- The `model:` field is **optional**. Absent → harness default behavior, byte-identical to pre-`model:` workflows (NFR-5).
- Mismatches **fail loudly**. Unrecognized tiers or malformed ids surface as an activation error with the identifiable prefix `wheel: model resolve failed` (and a step-context wrapper `wheel: model resolution failed for step '<name>': ...`). There is **no silent fallback** to a default model (FR-B2).
- Explicit-id validation is regex-only. If the harness later rejects the id, that rejection also surfaces loudly at dispatch time.

## Requirements

- Bash 3.2+ (macOS default)
- `jq` (JSON processing)
- Node.js 18+ (init script only)
