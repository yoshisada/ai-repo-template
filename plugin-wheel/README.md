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

## Requirements

- Bash 3.2+ (macOS default)
- `jq` (JSON processing)
- Node.js 18+ (init script only)
