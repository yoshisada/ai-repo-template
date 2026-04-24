# Feature PRD: Wheel User-Input Primitive

## Parent Product

Parent product: **kiln** (`@yoshisada/kiln`). This feature lives in the **wheel** plugin (`plugin-wheel/`), the workflow engine that kiln and all other plugins depend on. Parent PRD at `docs/PRD.md`.

## Feature Overview

Give wheel workflows a way to pause mid-execution and wait for the user to answer a question, then resume. Today, agent steps running in main chat can ask the user questions in their text output, but the Stop hook re-fires "write your output" every turn while the step is open — so pausing for user input is noisy and unreliable.

This feature adds two minimal primitives:

1. A **step-level permission** (`allow_user_input: true`) that declares the step is permitted to pause for the user.
2. A **runtime bash command** (`wheel flag-needs-input`) that the executing agent invokes when it decides — at runtime, based on what it actually knows — that it needs the user. While the flag is set, the Stop hook stays silent instead of nagging.

The agent remains in control of the Q&A; the engine only provides the primitive to suppress the hook and the permission gate that says whether the step is allowed to use it.

## Problem / Motivation

Interactive workflows are blocked today. When `/kiln:kiln-roadmap` (once it ships) runs its adversarial interview, or when `/kiln:kiln-fix` wants to ask "did the fix work?" after the diagnose-fix-verify loop, or when `/clay:clay-idea` wants to run an interview inside a workflow, the pattern falls apart: every turn the agent asks a question and ends its turn, the Stop hook re-fires with "write your output" — the user sees noise, the agent sees a reminder to do something it can't do yet (because it doesn't have the answer), and the step never resolves cleanly.

The workarounds today are all bad:

- Run the interview OUTSIDE wheel (in the skill), then dispatch to wheel for the mechanical parts. Works but means every skill that wants an interview re-implements Q&A plumbing. No reuse.
- Run the interview in a single agent step and hope the agent ignores the re-fires until it's done. Fragile; relies on the agent correctly recognizing "I'm mid-interview, ignore the reminder." Users get noise.
- Author N steps, one per question, and pray. Same re-fire problem, N times worse.

The right fix is a small engine primitive: a way to say "this step is paused waiting on the user, don't nag." Once that exists, any workflow in any plugin can use it.

## Goals

1. A workflow step can declare, at authoring time, that it's allowed to pause for user input (`allow_user_input: true`).
2. The agent running the step can decide, at runtime, whether it actually needs to pause (based on what it has gathered and whether it still needs a human call).
3. While the step is in "awaiting user input" state, the Stop hook emits no reminder — the user sees the question once and replies when ready.
4. When the user replies and the agent writes the step output, the flag auto-clears and the workflow advances normally.
5. The primitive is usable by any plugin with zero per-plugin plumbing — authors add `allow_user_input: true`; agents invoke `wheel flag-needs-input`.
6. Non-interactive sessions (CI, headless, automation) can suppress pausing via a single env var — the step either proceeds with defaults or fails fast.

## Non-Goals

- **Pre-declared pause points** — the first design attempt put the "pause here" decision at authoring time (`interactive: true` → Stop hook auto-suppresses). Rejected because it removes the agent's ability to skip the pause when it can answer its own question from repo state. This PRD explicitly moves that decision to runtime.
- **Engine-level interview templates** — no built-in "multi-question interview" step type. Interview scripting stays in the agent prompt / step instruction; engine only provides pause/resume.
- **Automatic answer routing from user prompt to step output** — the engine does NOT parse user replies and write them to outputs. Main-chat Claude reads the reply and writes the output, same as today.
- **Cross-workflow coordination beyond a simple guard** — one interactive step active at a time across all workflows is the simple rule; no priority queues, no multiplexing.
- **UI prompts, forms, or rich input** — user input is plain text in the next chat turn. No structured forms, no widgets.
- **Rewriting existing kiln-roadmap design to use this primitive** — the roadmap PRD stays as-is (interview in the skill, mechanical pipeline in the workflow). Once this primitive ships, a follow-up can refactor roadmap to use it, but that's a separate decision.

## Target Users

- Plugin authors writing workflows that need interactive clarification steps (kiln, shelf, clay, trim).
- End users running those workflows, who today experience either broken pauses or no pause at all.

No end-user–facing command additions except `/wheel:wheel-skip <step-id>` for abandoning a stalled interactive step.

## Core User Stories

1. **Agent opts into pausing when needed** — A workflow step has `allow_user_input: true`. The agent reads repo state, determines it can resolve 3 of 4 questions on its own, and only needs the user for the 4th. It outputs the remaining question and runs `wheel flag-needs-input "phase assignment needed"`. The Stop hook stays silent, the user replies, the agent writes the output, the workflow advances.

2. **Agent does NOT pause when it doesn't need to** — Same step, same `allow_user_input: true`, but this time the agent can infer everything from `.shelf-config`, vision.md, and existing items. It writes the output immediately without calling `flag-needs-input`. No user prompt, no wait. This is the payoff of runtime-vs-authoring-time.

3. **Unauthorized pause attempt fails cleanly** — A step has `allow_user_input: false` (default). The agent tries to run `wheel flag-needs-input`. The command exits 1 with message "this step does not permit user input — finish with the context you have." The agent sees the error and proceeds.

4. **User abandons a stalled step** — A workflow is waiting on the user, who changes their mind. They run `/wheel:wheel-skip`. The step is marked cancelled with a sentinel output. If the workflow defines `on_cancel`, it hops; otherwise the step is treated as failed.

5. **Non-interactive execution** — A CI run sets `WHEEL_NONINTERACTIVE=1`. Any `wheel flag-needs-input` call exits 1 unconditionally. Agents proceed with defaults or fail.

6. **Workflow author audits pause points** — An author greps the workflow JSON for `allow_user_input: true` to see every place the workflow might stall for human input. The set is explicit and reviewable — no hidden pauses.

## Functional Requirements

### Schema changes

- **FR-001** — Workflow JSON schema gains an optional field `allow_user_input: boolean` on step definitions of `type: agent` (and optionally `type: loop` and `type: branch`, if those dispatch agents). Default is `false`. `type: command` steps are explicitly NOT allowed to pause — commands are deterministic bash, they never wait for humans.
- **FR-002** — Validation: `plugin-wheel/lib/workflow.sh` rejects workflows that set `allow_user_input: true` on disallowed step types with a clear error.

### State changes

- **FR-003** — Per-step state gains `awaiting_user_input: boolean` (default false) and `awaiting_user_input_since: <ISO-8601 timestamp>` (nullable). Both live in `.wheel/state_*.json` under the step entry.
- **FR-004** — State helpers: `state_set_awaiting_user_input <state-file> <step-index> <reason>` sets the flag and timestamp; `state_clear_awaiting_user_input <state-file> <step-index>` clears them. Called by the CLI command in FR-006 and by the output-write advance logic in FR-008.

### Runtime command

- **FR-005** — New executable: `plugin-wheel/bin/wheel-flag-needs-input.sh` (callable as `wheel flag-needs-input [reason]` once wired into the wheel CLI entry, or invocable directly by path from workflow command steps).
- **FR-006** — Command behavior:
  1. Locate the active workflow state file. If none, exit 1 with "no active workflow."
  2. Read the current step index and its JSON definition.
  3. If the step does not have `allow_user_input: true`, exit 1 with "step <id> does not permit user input."
  4. If `WHEEL_NONINTERACTIVE=1` is set, exit 1 with "non-interactive mode: user input disabled."
  5. If any other workflow already has `awaiting_user_input: true`, exit 1 with "another workflow is waiting on user input: <workflow-name> / <step-id>." (Cross-workflow guard — FR-010.)
  6. Otherwise, set `awaiting_user_input: true` with the reason and current timestamp, print a short confirmation, exit 0.

### Stop hook changes

- **FR-007** — `plugin-wheel/hooks/stop.sh` at start of its "what do I tell main chat" logic:
  - If the current active step has `awaiting_user_input: true` → emit nothing (silent). Return normally.
  - Otherwise → existing behavior (emit step instruction / "write your output" reminder).
- **FR-008** — When the Stop hook detects that a step's output file has appeared AND `awaiting_user_input: true`, it clears the flag as part of its normal advance bookkeeping. No separate "resume" command needed.

### Step instruction injection

- **FR-009** — When the Stop hook emits the step instruction for a step with `allow_user_input: true`, it appends a short block to the instruction:
  > "This step permits user input. If you cannot resolve this step from repo state alone, you MAY output your question to the user and then run `wheel flag-needs-input "<short reason>"` before ending your turn. The Stop hook will stay silent until you write the output. If the question is unnecessary, skip it and write the output directly."
  This is the only way agents reliably learn the primitive exists — telling them inline at the moment it matters.

### Cross-workflow guard

- **FR-010** — Only one workflow may have `awaiting_user_input: true` active at a time (across all workflows). The `wheel flag-needs-input` command enforces this (FR-006 step 5). Rationale: the user has one chat at a time; if two workflows both asked questions, answers would ambiguously route.

### Abandonment

- **FR-011** — New skill: `/wheel:wheel-skip [step-id]`. Writes a sentinel output (`{cancelled: true, reason: "user-skipped"}`) to `.wheel/outputs/<step>.json` and clears `awaiting_user_input`. Workflow advance logic proceeds per existing behavior (step treated as completed with cancel sentinel; downstream steps check output shape).
- **FR-012** — Optional step-level `on_cancel: <step-id>` field. When set, cancellation hops to the named step instead of advancing linearly. Out of scope for v1 — can be added later without breaking existing workflows.

### Non-interactive mode

- **FR-013** — Environment variable `WHEEL_NONINTERACTIVE=1` disables user-input pausing globally. `wheel flag-needs-input` exits 1 immediately when this is set (FR-006 step 4).
- **FR-014** — Optional step-level `default_on_noninteractive: <string>` field. If set AND `WHEEL_NONINTERACTIVE=1`, the agent can read this default from its step instruction and use it in place of asking. Out of scope for v1 — agents handle non-interactive fallback via their own prompt logic for now.

### Observability

- **FR-015** — `/wheel:wheel-status` output includes pending user-input state: if any active workflow has `awaiting_user_input: true`, show the reason and elapsed time (from `awaiting_user_input_since`). Lets the user see at-a-glance "I've been waited on for 4 minutes for reason X."

## Absolute Musts

1. **Agent decides at runtime, not author at design time** — `allow_user_input` is a *permission*; the decision to actually pause is made by the agent reading `flag-needs-input` out of its step instruction. This is the load-bearing design choice; reverting to "declare all pause points in workflow JSON" loses the ability for agents to skip unnecessary pauses.
2. **Engine stays dumb** — wheel provides the flag / quiet-hook / permission gate. No parsing user replies, no forming questions, no interview templates. All semantics live in agent prompts.
3. **Stop hook silence must be ironclad** — if a step is `awaiting_user_input`, the hook emits nothing. Not a shortened reminder, not a "still waiting" ping — nothing. The user sees the question once; subsequent turns (including the user's reply turn and Claude's write-output turn) produce zero Stop-hook noise until the step is done.
4. **Cross-workflow guard is enforced** — one interactive step active at a time, period. Workflows competing for user attention produces confusion that's not worth the complexity to multiplex.
5. **Tech stack match** — Bash 5.x, `jq`, existing wheel engine libs. No new runtime deps.

## Tech Stack

Inherited from parent kiln / wheel plugins — no additions:
- Bash 5.x (hook scripts, CLI bin)
- `jq` (state JSON manipulation)
- Existing wheel engine libs: `state.sh`, `workflow.sh`, `dispatch.sh`, `engine.sh`, `context.sh`, `lock.sh`, `guard.sh`

## Impact on Existing Features

- **`plugin-wheel/hooks/stop.sh`** — adds one conditional branch at the start. Existing behavior unchanged for steps without `awaiting_user_input: true`.
- **`plugin-wheel/lib/workflow.sh`** — adds validation for `allow_user_input` on disallowed step types.
- **`plugin-wheel/lib/state.sh`** — adds `state_set_awaiting_user_input` and `state_clear_awaiting_user_input` helpers.
- **`plugin-wheel/bin/`** — new `wheel-flag-needs-input.sh` executable.
- **`/wheel:wheel-status`** — surfaces pending user-input state (small update).
- **`/wheel:wheel-skip`** — new skill (FR-011).
- **Existing workflows** — unaffected; they default to `allow_user_input: false` and behave exactly as today.
- **Downstream plugins (kiln, shelf, clay, trim)** — can now opt into interactive steps by setting `allow_user_input: true` on any agent step. No forced migration; existing workflows continue to work.

## Success Metrics

1. **Interview-style workflows become authorable** — at least one plugin (likely kiln roadmap or kiln-fix) has an interactive step using this primitive within one cycle of shipping; the step has zero Stop-hook re-fires visible to the user while awaiting input.
2. **Runtime optionality is used** — measured by inspection of agent traces: at least one instance where an agent with `allow_user_input: true` chose NOT to pause (resolved from repo state alone). Proves the runtime decision isn't being skipped.
3. **No cross-workflow collisions** — across real usage, the guard in FR-010 is hit ≥1 time (not zero, since that would mean no one is using the primitive; not broken, since that would mean the guard doesn't work).
4. **Observability delivers** — `/wheel:wheel-status` shows pending user-input reason + elapsed time on at least one real stall.

## Risks / Unknowns

- **Agents forget to call `flag-needs-input`** — if an agent asks a question in its text output but doesn't run the command, the Stop hook nags. Mitigation: the step instruction explicitly tells the agent to use the primitive (FR-009). Repeated instruction at the moment it matters is the strongest available nudge; anything beyond that is Claude-side judgment.
- **Agents pause when they shouldn't** — if agents over-use the primitive (pausing when they could have inferred), the workflow stalls needlessly. Mitigation: the step instruction frames pausing as last-resort ("only if you cannot resolve from repo state"). Can be tightened in prompts later if we see over-use.
- **Race between `flag-needs-input` and hook fires** — the command sets state, then the agent ends its turn, then the hook fires. If the hook fires before the command's state write lands, it nags. Mitigation: `flag-needs-input` is synchronous and blocks until state is written (bash script with `jq` + atomic write). Additionally: the Stop hook already uses the state file as its source of truth, so this is a well-understood ordering.
- **User's reply isn't the answer** — the user might ask something unrelated or interrupt. No engine handling needed; the agent uses judgment and continues. If the agent writes the output, the step advances; if not, the flag stays set and the hook stays silent.
- **State file is per-workflow; cross-workflow guard needs to inspect multiple state files** — FR-010 requires the command to scan all active `.wheel/state_*.json` files. Mitigation: this is a small `ls | jq` scan and is already the pattern used by other wheel primitives.

## Assumptions

- Main-chat Claude is competent enough to use the primitive when instructed — i.e., to output a question, run `wheel flag-needs-input`, end turn; and to write the output after receiving a reply. This is consistent with how Claude handles other workflow step patterns today.
- `.wheel/state_*.json` is the authoritative source for step state; no competing store.
- Users answer questions in the next message, not several messages later. If they go dormant, the timestamp in `/wheel:wheel-status` reveals it.
- `WHEEL_NONINTERACTIVE=1` is the right knob for CI; no more granular mode needed in v1.

## Open Questions

1. Should `/wheel:wheel-skip` require confirmation, or skip immediately? v1 proposal: skip immediately. Interactive steps are already annoying; adding friction to skip them is worse.
2. Should the reason passed to `flag-needs-input` be displayed back to the user (e.g., as a pre-question header "(waiting on you for: phase assignment)")? v1 proposal: no — the agent already asked its question in text. The reason is for `/wheel:wheel-status` observability only.
3. Do we need a timeout that auto-cancels stalled interactive steps? v1 proposal: no automatic timeout. `/wheel:wheel-skip` is the escape hatch. Automatic cancellation risks losing the user's in-progress thinking.
4. Should `on_cancel` (FR-012) ship in v1 or later? v1 proposal: later. The common case is "cancel = fail the step"; fancy hop routing can wait until someone needs it.

## Sequencing

- **Depends on**: none. This feature only modifies wheel internals and is self-contained.
- **Blocks / enables**: any plugin workflow that wants interactive steps. Specifically: after this ships, the kiln-roadmap workflow (from `docs/features/2026-04-23-structured-roadmap/PRD.md`) can optionally be refactored to use `allow_user_input: true` steps for its interview phase instead of doing the interview in the skill wrapper. That refactor is a separate PRD; the roadmap PRD stays unchanged and ships with interview-in-skill.
