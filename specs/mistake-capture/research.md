# Research — Mistake Capture

**Date**: 2026-04-16
**Input**: PRD (`docs/features/2026-04-16-mistake-capture/PRD.md`), spec (`specs/mistake-capture/spec.md`).

All PRD decisions are load-bearing and were adopted verbatim in the spec. The research below covers only the open questions the spec deliberately left to `/plan`.

## R1. Factor the `check-existing-mistakes` step into a script vs inline it

**Decision**: Factor it into `plugin-kiln/scripts/check-existing-mistakes.sh`, invoked via `${WORKFLOW_PLUGIN_DIR}/scripts/check-existing-mistakes.sh`.

**Rationale**:
- The step lists two directories (`.kiln/mistakes/` + `@manifest/recent-session-mistakes/`) with structured headers that the agent step reads via `context_from`. Inlining the whole thing as a shell one-liner in the workflow JSON bloats the JSON and makes the behavior hard to test and read.
- Shelf factors its command steps the same way (`read-sync-manifest.sh`, `compute-work-list.sh`, `update-sync-manifest.sh`, `generate-sync-summary.sh`). Consistency.
- A separate script file is cheap to lint with `bash -n`, cheap to unit-test manually, and cheap to audit for the `${WORKFLOW_PLUGIN_DIR}` portability rule.

**Alternatives considered**:
- **Inline shell in JSON** (what `report-issue-and-sync.json` does for its Step 1). Rejected — the existing one-liner is a trivial `ls`. Ours has formatted headers and handles two source paths. Different complexity class.
- **Inline in the workflow JSON but multi-line**. Rejected — JSON-string-escaped multi-line shell is unreadable and review-hostile.

## R2. MCP scope for `@inbox/open/` writes

**Decision**: Assume `mcp__obsidian-projects__*` has write access across the entire vault including `@inbox/`. Verify at implementation time. Fallback to `mcp__claude_ai_obsidian-manifest__*` if the projects scope is read-only outside `@second-brain/projects/`.

**Rationale**:
- The current `shelf-full-sync` workflow's `obsidian-apply` agent step uses `mcp__obsidian-projects__create_file` for paths like `projects/<slug>/issues/<slug>.md`. No explicit evidence in the codebase restricts the MCP scope to the `projects/` subtree, but also no positive evidence it can write `@inbox/`.
- The test is cheap — try `create_file` on `@inbox/open/test.md` once during implementation. If it fails, branch the proposal-write path to the manifest MCP.
- Keeping the assumption-until-verified approach avoids premature branching in the workflow for a scope limit that may not exist.

**Alternatives considered**:
- **Branch upfront with both MCP scopes**. Rejected — adds implementation complexity for a verification step that will take 60 seconds at runtime.
- **Write a local file in `.kiln/mistakes/proposals-pending/` as universal fallback**. Rejected — defeats the purpose of shelf automation. Only consider if MCP is genuinely unwritable.

## R3. Proposal filename in `@inbox/open/`

**Decision**: `@inbox/open/YYYY-MM-DD-mistake-<assumption-slug>.md`.

**Rationale**:
- The `mistake-` infix disambiguates mistake proposals from other proposal types that may share `@inbox/open/` in the future (per `@manifest/systems/projects.md`, the `@inbox/open/` folder hosts all proposal kinds). Scanning the inbox by filename is more useful with the infix than without.
- Date-first prefix matches the existing convention for `.kiln/mistakes/` artifacts — consistency of chronology ordering across source and proposal.
- Slug re-used from the source artifact — no re-derivation risk.

**Alternatives considered**:
- **Use the source filename verbatim**: `@inbox/open/YYYY-MM-DD-<slug>.md`. Rejected — collides with other proposal kinds that may share the slug (e.g., a decision note proposal and a mistake proposal about the same topic).
- **Omit the date**: `@inbox/open/mistake-<slug>.md`. Rejected — loses chronology, complicates duplicate-slug-different-day cases.

## R4. Tracking "filed" state to prevent resurrection (FR-014)

**Decision**: Extend the existing sync manifest with a `mistakes[]` array carrying `{path, filename_slug, date, source_hash, proposal_path, proposal_state, last_synced}`. `proposal_state` is a two-state machine: `open` (initial) → `filed` (detected when the proposal file leaves `@inbox/open/`). Once `filed`, never re-propose.

**Rationale**:
- The sync manifest is the existing cross-sync state artifact shelf owns. Adding a parallel array to `issues[]` and `docs[]` keeps the invariant "one sync-state file" that `compute-work-list.sh` and `update-sync-manifest.sh` already depend on.
- `filename_slug` is retained for debuggability/log lines even though `path` is the primary key.
- `proposal_path` stored so reconciliation (does the proposal still exist in `@inbox/open/`?) doesn't need to re-derive the path.
- A single `list_files` call on `@inbox/open/` per sync is enough to reconcile all `mistakes[]` entries — O(1) MCP reads regardless of mistake count.

**Alternatives considered**:
- **Frontmatter marker on the source `.kiln/mistakes/` file** (e.g., `filed: true` added to the artifact itself). Rejected — mutates the source artifact after creation, which complicates hash-based change detection and clashes with the manifest spec's expectation that mistake notes are immutable records of the moment.
- **Sibling state file `.kiln/mistakes/.sync-state.json`** scoped to mistakes only. Rejected — fragments sync state across two files; `compute-work-list.sh` and `update-sync-manifest.sh` would need to read/write both.
- **Don't track filed state; rely on content-hash skip alone**. Rejected — the content hash doesn't change when a user moves the proposal out of `@inbox/open/`, so on a fresh sync shelf would happily re-propose.

## R5. Location of the honesty lint and tag lint

**Decision**: Both lints live inside the `create-mistake` agent step's natural-language `instruction:` field. NOT in a shell script.

**Rationale**:
- The lint is applied to free-form user-supplied prose (`assumption:`, `correction:`, tag list). The agent is the one collecting the input and re-prompting for corrections — running a shell script and returning to the agent on reject would require state-machine round-tripping the wheel engine does not natively support within one step.
- The set of rejected strings is short (8 hedge words + 3 first-person prefixes + 3 tag-axis checks). Encoding the rule in the agent's instruction is the normal cost. The PRD explicitly describes this as the architecture.
- The lint is enforced once per step invocation per failing field. Natural-language enforcement is the exact UX pattern the feature needs (re-prompt with a one-line explanation).

**Alternatives considered**:
- **Bash script that echoes VALID/INVALID to stdout**: requires the agent to run a subprocess for every field and parse its output. Adds latency, adds a shell script, adds nothing.
- **Two-step workflow: collect-fields (agent) → validate-fields (command) → loop**. Rejected — the wheel engine does not support step-level loops natively. Would require a separate loop-style workflow. Scope explosion for a v1 feature.

## R6. Model ID detection for `made_by`

**Decision**: Agent-side inference from the agent's own runtime knowledge of its model ID. Confirm with user. No programmatic `env`-based detection.

**Rationale**:
- The Claude model running the workflow's agent step knows its own model ID directly (e.g., "I am Claude Opus 4.7, kebab-cased as `claude-opus-4-7`"). This is the natural source of truth.
- Programmatic detection via shell environment variables is unreliable — Claude Code does not consistently export a model identifier to subprocesses, and doing so is not documented/load-bearing for the broader CLI.
- Confirming with the user closes the gap when an agent is wrong about its own ID (rare but possible during provider switches).

**Alternatives considered**:
- **Read from a known env var (e.g., `CLAUDE_MODEL`)**: not a documented Claude Code interface. Rejected.
- **Hardcode a single default**: defeats the point of the field (tracking which model made a given mistake is literally the purpose of `made_by`).

## R7. Step count — stay at three

**Decision**: Keep the workflow at exactly three steps (`check-existing-mistakes` command → `create-mistake` agent → `full-sync` workflow-terminal). Do not add a separate "write-artifact" step.

**Rationale**:
- PRD FR-4 pins the shape at three steps for parity with `report-issue-and-sync`.
- The `create-mistake` agent step already writes the file; splitting the agent's write into a command-step would require the agent to emit a structured payload that a script then deserializes and writes. More plumbing, zero benefit.
- Absolute Must #1 (wheel-framework parity with `/report-issue`) is explicit.

**Alternatives considered**:
- **Four-step with a separate validation step**: Rejected — see R5.
- **Two-step by collapsing duplicate-check into the agent step**: Rejected — the duplicate-check output is valuable to the agent as `context_from` (no reason to pay tokens to re-derive it).

## R8. Local-override path for the workflow

**Decision**: No new discovery logic. The existing wheel override mechanism (consumer repo's `workflows/<name>.json` takes precedence over `plugin-kiln/workflows/<name>.json`) applies to this feature without modification.

**Rationale**: The shelf skill set already relies on this; it's a stable wheel-engine feature. Just write the source-of-truth file at `plugin-kiln/workflows/report-mistake-and-sync.json` and let wheel handle override resolution.

---

## Dependencies / Prerequisites

- **Wheel `WORKFLOW_PLUGIN_DIR` export** (commit `005e259`): hard prerequisite. Verified present on `main`. Without it, command-step scripts cannot resolve portably.
- **Obsidian MCP server availability**: assumed at `mcp__obsidian-projects__*`. Verified to be the same scope `shelf-full-sync` already uses.
- **`@manifest/types/mistake.md`**: assumed stable (last_updated 2026-04-16 per the PRD). Any change during implementation triggers a spec update.
- **`@manifest/templates/mistake.md`**: read-only reference for body structure. Implementation strips the template-metadata block but preserves the section layout.

## Open Questions — Resolved

All five PRD "Open Questions" were resolved during specification:

1. `made_by` auto-prefill? → Yes, agent-inferred with user confirmation (R6).
2. `.kiln/mistakes/` in `CLAUDE.md` conventions? → Yes; separate sub-directory in `.kiln/` alongside `issues/`, `logs/`, `qa/`. Not part of this feature's delivery; a trivial CLAUDE.md update task in tasks.md.
3. `--from-transcript` flag? → Out of scope for v1 per PRD Non-Goals. No placeholder in v1.
4. Severity guidance inline vs linked? → Linked in SKILL.md (reference `@manifest/types/mistake.md § Severity`). Inlining bloats the skill file.
5. `mistake/*` tag picker — multiple-choice vs free-text? → Free-text with post-validation. Matches the spec's "no bypass flag" stance on honesty lint — multiple-choice forecloses on rare cross-class cases (FR-008 explicitly permits two `mistake/*` tags on confirmation).

No unresolved `[NEEDS CLARIFICATION]` markers remain.
