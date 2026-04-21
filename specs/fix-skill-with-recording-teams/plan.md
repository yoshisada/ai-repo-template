# Implementation Plan: Fix Skill with Recording Teams

**Branch**: `build/fix-skill-with-recording-teams-20260420` | **Date**: 2026-04-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/fix-skill-with-recording-teams/spec.md`

## Summary

Extend `plugin-kiln/skills/fix/SKILL.md` with a terminal "Step 7: Record the fix" stage that (a) composes a complete fix envelope in main chat, (b) writes a local record at `.kiln/fixes/<YYYY-MM-DD>-<slug>.md` inline in the skill, and (c) spawns two parallel short-lived agent teams (`fix-record`, `fix-reflect`) whose briefs are the envelope plus static instructions. The debug loop (Steps 2b–5) is unchanged — the recording stage runs only after the commit lands or the 9-attempt escalation exhausts. Also authors a new manifest type at `@manifest/types/fix.md` modeled on `mistake.md`, and adds `.kiln/fixes/` to `.gitignore`. No new dependencies, no wheel workflow, no bats/vitest; tests are pure bash `.sh` scripts.

## Technical Context

**Language/Version**: Bash 5.x (inline shell blocks in SKILL.md + new `.sh` helper scripts + `.sh` test scripts); Markdown (skill definition, manifest type file, team-brief prompts embedded in skill).
**Primary Dependencies**: No new deps. Uses existing: `jq` (JSON shaping + validation — already used by shelf scripts), `grep -F` (verbatim match — already used), `git` CLI (commit hash, repo-root basename), `gh` CLI (optional — only if `/fix` was invoked with an issue ref; already used in Step 1 of current skill), Claude Code agent-teams primitives (`TeamCreate`, `TaskCreate`, `SendMessage`, `TeamDelete`), Obsidian MCP symbol `mcp__claude_ai_obsidian-manifest__create_file`.
**Storage**:
  - `.kiln/fixes/<YYYY-MM-DD>-<slug>.md` — gitignored, mirrors the Obsidian note.
  - `.kiln/fixes/.envelope-<timestamp>.json` — gitignored transient scratch; persists the envelope during team runs and is referenced by path from each team brief.
  - `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` — Obsidian vault, MCP-written.
  - `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` — Obsidian vault, MCP-written (only when reflect approves).
  - `@manifest/types/fix.md` — Obsidian vault, authored once as part of this feature (written by implementer either via MCP or as a spec artifact the implementer hands to the maintainer — see research.md Decision R3).
**Testing**: Pure bash `.sh` scripts under `plugin-kiln/scripts/__tests__/fix-recording/`. Each test is a self-contained executable that sets up a temp repo, invokes one helper or fixture, and `exit 1`s on any assertion failure. No bats (FR-024), no vitest, no pytest.
**Target Platform**: macOS/Linux dev shells (consumer + source repos). Bash 5.x assumed (CLAUDE.md confirms).
**Project Type**: Plugin-internal skill + shared helper scripts. No src/, no app. Lives under `plugin-kiln/`.
**Performance Goals**: Main-chat team traffic ≤3k tokens per `/fix` invocation (SC-004). Team spawn + MCP write adds small but bounded wall-clock; no hard latency SLA.
**Constraints**:
  - FR-020: No `TeamCreate` / `TaskCreate` / wheel-activate before the commit step. Hard constraint — violates the feature's reason for existing.
  - FR-023: No wheel workflow added.
  - FR-022: No new runtime deps.
  - FR-025: Consumer-repo portability — scripts resolve via a plugin-dir-aware path variable, not `plugin-shelf/scripts/...` literals.
  - FR-026: `.kiln/qa/.env.test` content must never leak into envelope fields.
**Scale/Scope**:
  - Two new agent teams per `/fix` run (short-lived, deleted on terminal state).
  - One new manifest type file (`fix.md`).
  - One `.gitignore` line added.
  - ~6 helper shell functions (envelope compose, slug, collision handle, credential strip, team-brief render, local write).
  - ~8 bash test scripts covering FR-030 cases.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Spec-First Development | **Pass** | spec.md committed before any code; FR comments will reference spec FR-IDs in helper functions and test scripts. |
| II. 80% Test Coverage | **Pass with caveat** | Coverage is measured for bash helpers via per-function test scripts — test plan targets every branch of the new helpers (see FR-030). SKILL.md prose is not testable code, and team agent prompts are tested via fixture briefs + gate scripts. Constitution's "line/branch coverage" is interpreted for bash as "every branch of every new helper has a test that asserts the expected stdout + exit code." |
| III. PRD as Source of Truth | **Pass** | Spec mirrors PRD FR-1..FR-20 and PRD success metrics M1..M5 (SC-001..SC-010 map back). Where this plan's FR-021..FR-030 extend PRD, they are operational derivations of PRD Absolute Musts #1, #7, #8 — no contradictions. |
| IV. Hooks Enforce Rules | **Pass** | Spec, plan, tasks artifacts are being committed before any `src/`-equivalent change. The 4-gate hook does not apply to plugin files under `plugin-kiln/`, but we respect the intent by committing all three artifacts first. |
| V. E2E Testing Required | **Pass with caveat** | True "E2E" for this feature would require a real Claude Code team-spawn in CI, which this plugin's test infra does not provide. We compensate with: (a) a `/fix` smoke test invoked manually (`quickstart.md`), (b) unit tests over every helper script, (c) team-brief fixture tests that verify the brief's static text + envelope-parameter substitution. The reviewer validates end-to-end by running `/fix` on a seeded bug in a scratch branch. |
| VI. Small, Focused Changes | **Pass** | Every new `.sh` helper stays under 120 lines. `@manifest/types/fix.md` is one file. The skill edit adds one Step 7 section plus two team-brief templates to `SKILL.md`; if SKILL.md crosses 500 lines after the edit, we split the team-brief templates into sibling files per Principle VI. |
| VII. Interface Contracts Before Implementation | **Pass** | `contracts/interfaces.md` authored by /plan (this phase), covering envelope JSON schema, helper function signatures, and team-brief input contracts. Implementation MUST match. |
| VIII. Incremental Task Completion | **Pass** | tasks.md (next phase) will break Step 7 into ~15 ordered tasks; implementer marks `[X]` and commits per phase. |

No Complexity-Tracking violations — every item is forced by the PRD or is a test-infra compensation documented above.

## Project Structure

### Documentation (this feature)

```text
specs/fix-skill-with-recording-teams/
├── plan.md                 # This file
├── spec.md                 # Feature spec (already written)
├── research.md             # Phase 0 output (written in this phase)
├── data-model.md           # Phase 1 output (written in this phase)
├── quickstart.md           # Phase 1 output (written in this phase)
├── contracts/
│   └── interfaces.md       # Phase 1 output (written in this phase)
├── checklists/
│   └── requirements.md     # Already written
├── agent-notes/
│   └── specifier.md        # Will be written at end of this specifier task
└── tasks.md                # Phase 2 output (next skill invocation)
```

### Source Code (repository root)

```text
plugin-kiln/
├── skills/
│   └── fix/
│       ├── SKILL.md                        # EDIT — add Step 7: Record the fix
│       └── team-briefs/                    # NEW — per-team static prompt templates (if SKILL.md would exceed 500 lines)
│           ├── fix-record.md               # NEW — fix-record team brief template
│           └── fix-reflect.md              # NEW — fix-reflect team brief template
├── scripts/
│   └── fix-recording/                      # NEW — helper scripts for Step 7
│       ├── compose-envelope.sh             # NEW — builds the envelope JSON on stdout
│       ├── strip-credentials.sh            # NEW — FR-026 filter applied to envelope
│       ├── write-local-record.sh           # NEW — writes .kiln/fixes/<date>-<slug>.md
│       ├── resolve-project-name.sh         # NEW — FR-013 fallback chain
│       ├── unique-filename.sh              # NEW — FR-015 collision disambiguation
│       ├── render-team-brief.sh            # NEW — substitutes envelope-path, scripts-dir, slug, date into a brief template
│       └── __tests__/                      # NEW — pure-bash unit tests
│           ├── test-compose-envelope.sh
│           ├── test-compose-envelope-escalated.sh
│           ├── test-strip-credentials.sh
│           ├── test-write-local-record.sh
│           ├── test-slug-via-shelf.sh
│           ├── test-unique-filename.sh
│           ├── test-render-team-brief-fix-record.sh
│           ├── test-render-team-brief-fix-reflect.sh
│           ├── test-resolve-project-name.sh
│           └── run-all.sh                   # entry point — exits 1 if any test fails

plugin-shelf/
└── scripts/                                # READ-ONLY — reused as-is
    ├── derive-proposal-slug.sh             # FR-014 — invoked by compose-envelope.sh and unique-filename.sh
    ├── check-manifest-target-exists.sh     # FR-008 — invoked by fix-reflect team brief
    └── validate-reflect-output.sh          # FR-008 — invoked by fix-reflect team brief

# Obsidian vault (authored once, separate commit or MCP write):
# @manifest/types/fix.md                    # NEW — manifest type, modeled on mistake.md

# Repo root:
.gitignore                                  # EDIT — add ".kiln/fixes/"
```

**Structure Decision**: Plugin-internal feature scoped entirely under `plugin-kiln/`. Helper scripts live under `plugin-kiln/scripts/fix-recording/` (not `plugin-shelf/scripts/`) because they are kiln-specific logic — envelope composition, local record shape, team-brief rendering. The three reused shelf scripts stay where they are and are invoked via a plugin-portable path variable. Team-brief templates live either inline in SKILL.md (preferred for review-ability) or as sibling `.md` files under `plugin-kiln/skills/fix/team-briefs/` if SKILL.md would exceed the 500-line principle-VI ceiling — research.md Decision R4 picks.

## Phase 0 — Outline & Research

Research is consolidated inline here (generated by the specifier pass as part of this plan). A sibling `research.md` carries the same decisions verbatim for downstream readers.

### Decision R1 — How to discover the plugin scripts path in a consumer repo

**Decision**: Export a `SHELF_SCRIPTS_DIR` variable from the skill before team spawn, resolved via a three-step fallback that the skill runs inline:

```bash
SHELF_SCRIPTS_DIR="${WORKFLOW_PLUGIN_DIR:-}"
if [ -n "${SHELF_SCRIPTS_DIR}" ] && [ -d "${SHELF_SCRIPTS_DIR}/../plugin-shelf/scripts" ]; then
  SHELF_SCRIPTS_DIR="${SHELF_SCRIPTS_DIR}/../plugin-shelf/scripts"
elif [ -d "$(pwd)/plugin-shelf/scripts" ]; then
  SHELF_SCRIPTS_DIR="$(pwd)/plugin-shelf/scripts"
else
  # Fall back to the Claude plugin cache structure. Matches CLAUDE.md.
  SHELF_SCRIPTS_DIR="$(find "${HOME}/.claude/plugins/cache" -maxdepth 6 -type d -name 'scripts' -path '*/plugin-shelf/*' 2>/dev/null | head -1)"
fi
export SHELF_SCRIPTS_DIR
```

**Rationale**: CLAUDE.md mandates plugin portability via `${WORKFLOW_PLUGIN_DIR}`, but that variable is exported by the wheel dispatch layer and we are explicitly not a wheel workflow (FR-023). We therefore replicate the discovery responsibility in the skill. The fallback ladder (WORKFLOW_PLUGIN_DIR → local `plugin-shelf/` → cache search) keeps source-repo runs working while also supporting the consumer-repo case.

**Alternatives considered**:
- Hardcoding `plugin-shelf/scripts/...` — rejected (the exact portability bug CLAUDE.md calls out).
- Copying the three shelf scripts into `plugin-kiln/scripts/` — rejected; duplicates the slug/gate logic, violates "reuse existing scripts" per PRD Absolute Must #7.
- Shelling to a kiln CLI that resolves the path — rejected; no such CLI exists and adding one exceeds scope.

### Decision R2 — How to run two teams "in parallel"

**Decision**: Issue both `TeamCreate` + `TaskCreate` pairs in the same skill step (same main-chat tool-call batch), then proceed to collect terminal-state signals via task list polling without blocking on the first before creating the second. "Parallel" here means "both spawned before either completes," not "forked via shell job control" — Claude Code teams run their own agents concurrently once created.

**Rationale**: The skill is not shell-parallel code — it is a prompt issuing tool calls. The ability to issue two tool-calls per message is the parallelism primitive. This matches the pattern used by `shelf:propose-manifest-improvement` and build-prd.

**Alternatives considered**:
- Serial spawn (fix-record then fix-reflect) — rejected; doubles wall-clock when both teams take non-trivial time. PRD Non-Goal: we want parallel.
- Shell `&` + `wait` — inapplicable; we are not in a shell loop, we are in a skill prompt.

### Decision R3 — How and when to write `@manifest/types/fix.md`

**Decision**: The implementer authors the content of `@manifest/types/fix.md` as a markdown artifact committed to `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md` (a staging location in this feature's spec dir) AND writes it to the vault via `mcp__claude_ai_obsidian-manifest__create_file` during the implementation pass. The staging copy is the version-controlled, review-able source of truth; the vault copy is the one agents/maintainers actually consume.

**Rationale**: Obsidian vault files are outside the git tree, so a pure-MCP write leaves no PR-reviewable artifact. A staged copy inside the feature's spec dir gives reviewers something to read + critique, and future iterations can diff against it. Writing to both locations at once avoids drift.

**Alternatives considered**:
- MCP-only write — rejected; nothing for PR reviewers to read.
- Commit-only (no MCP write) — rejected; `fix-record` team has nothing to validate against at runtime until someone manually syncs.
- Include `fix.md` in a wheel sync — rejected; adds wheel dependency (FR-023 forbids).

### Decision R4 — Team-brief template placement: inline vs sibling files

**Decision**: Start with inline templates in SKILL.md. If the edited SKILL.md exceeds 500 lines total, factor the two briefs into `plugin-kiln/skills/fix/team-briefs/fix-record.md` and `fix-reflect.md` and reference them from SKILL.md via a single "Read and substitute" block.

**Rationale**: Inline keeps the entire skill readable in one pass — reviewers can see the exact prompts sent to each team without hopping files. Factoring only at 500 lines respects Principle VI without forcing a premature abstraction.

**Alternatives considered**:
- Always inline — rejected preemptively in case the briefs get long.
- Always sibling files — rejected; adds a read indirection when the templates are short.

### Decision R5 — How to persist the envelope for team consumption

**Decision**: Write the envelope JSON to `.kiln/fixes/.envelope-<timestamp>.json` before team spawn. Team briefs reference it by path. Delete the file at `TeamDelete` time (skill cleanup step).

**Rationale**: Keeps team brief text small (under a kilobyte) — the brief says "read <path>" rather than embedding a potentially multi-KB envelope inline, which would bloat main-chat traffic and reduce SC-004 headroom. Directory is already gitignored by FR-021, so the scratch file does not pollute diffs.

**Alternatives considered**:
- Inline envelope in brief — rejected; for envelopes with long `fix_summary` or many `files_changed`, this breaks SC-004.
- Write to `.wheel/outputs/` — rejected; we are not a wheel workflow (FR-023).
- Pass envelope fields as individual `TaskCreate` parameters — rejected; Claude Code's team-create API does not have structured params, only a text brief.

### Decision R6 — Tests for team-agent behavior

**Decision**: Unit-test the static parts (envelope compose, slug, local writer, brief renderer) with pure bash `.sh` scripts. For team-agent behavior (actual MCP call, actual reflect reasoning), rely on the `quickstart.md` manual smoke test — one scripted invocation on a seeded bug in a scratch branch — because the plugin's CI does not have Claude Code team-spawn primitives available.

**Rationale**: Mocking `TeamCreate` / `mcp__...` in bash is out of scope — we would be writing a parallel agent-teams emulator. The helper scripts that compose the envelope and render briefs are deterministic bash and can be fully covered. Agent-side behavior reduces to "does the rendered brief clearly instruct the right tool calls" — verified by reading the brief.

**Alternatives considered**:
- Write a mock-MCP harness — rejected; too much surface area, outside feature scope.
- Skip manual smoke — rejected; we would not know if the skill works end-to-end.

### Decision R7 — Escalation-path detection

**Decision**: The skill determines "did the debug loop escalate?" by checking whether the commit step produced a new commit on the current branch since the start of the invocation. If no new commit was created and 9 attempts were exhausted per `/kiln:debug-fix`, status = `escalated`. Source of truth: comparing `git rev-parse HEAD` at skill start vs now.

**Rationale**: Avoids introducing new state. `/kiln:debug-fix` already maintains an attempt count; the absence of a commit after the loop is the cleanest "escalated" signal.

**Alternatives considered**:
- New state file tracking attempts — rejected; duplicates debug-fix's bookkeeping.
- Parse `debug-log.md` — rejected; it is free-form and not meant to be machine-read.

## Phase 1 — Design & Contracts

### Data Model

See `data-model.md` (written in this phase). Summary:

- **Fix Envelope (JSON)**: nine required top-level fields. Persisted to a transient file under `.kiln/fixes/`.
- **Local Fix Record (Markdown)**: frontmatter + five H2 sections, mirrors Obsidian note.
- **Obsidian Fix Note (Markdown)**: frontmatter per FR-006 + five H2 sections, conforms to `@manifest/types/fix.md`.
- **Manifest Type `fix.md`**: defines required frontmatter fields and section order.
- **Reflect Output (JSON)**: same shape as `shelf:propose-manifest-improvement`'s reflect output — reused `validate-reflect-output.sh`.

### Interface Contracts

See `contracts/interfaces.md` (written in this phase). Covers:

1. Envelope JSON schema (field list, types, nullability).
2. Six new helper-script contracts (name, args, stdin, stdout, exit codes).
3. Two team-brief input contracts (what keys from the envelope each team reads, what tools each team calls).
4. Constraints on reused shelf scripts (what the skill guarantees for their inputs).

### Quickstart (smoke test)

See `quickstart.md` (written in this phase). Walks the reviewer through:
1. Seed a reproducible test failure on a scratch branch.
2. Run `/kiln:fix`.
3. Verify local record at `.kiln/fixes/<date>-<slug>.md`.
4. Verify Obsidian note at `@projects/<project>/fixes/<date>-<slug>.md`.
5. Verify no `@inbox/open/` file on a non-gap bug; verify one for a seeded gap bug.
6. Verify `TeamDelete` cleanup via a post-run active-teams list.

### Agent Context Update

The specifier runs `.specify/scripts/bash/update-agent-context.sh claude` (or equivalent) as the final step of the plan phase to record the new technologies flagged in this plan. For this feature the "new" surface is zero (bash, markdown, agent teams, Obsidian MCP all already recorded in CLAUDE.md), so the update will be a no-op. We still run it for consistency.

## Complexity Tracking

> No Constitution violations. Any "caveats" in the Constitution Check table (test coverage interpretation for bash, E2E supplied by quickstart) are operational translations — not violations needing justification.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_ | | |
