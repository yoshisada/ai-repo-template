# Implementation Plan: Pipeline Input Completeness

**Spec**: [spec.md](./spec.md)
**Branch**: `build/pipeline-input-completeness-20260423`
**Date**: 2026-04-23

## Overview

Two surgical bug fixes:

1. **Step 4b bug fix** — extend the existing bash loop in `plugin-kiln/skills/kiln-build-prd/SKILL.md` to also scan `.kiln/feedback/`, normalize paths, emit a diagnostic line, and write to `.kiln/logs/`. Net change: ~30 lines of bash inside the existing Step 4b heading.
2. **`shelf-write-issue-note` config-awareness** — replace the loose `cat .shelf-config` parse in step `read-shelf-config` with the defensive `key = value` parser, and add a `path_source` field to the agent's result-JSON contract. Net change: ~15 lines of bash + ~10 lines added to the `obsidian-write` agent instruction.

No new files of substance besides the spec artifacts and the `SMOKE.md` fixture document. No new dependencies.

## Locked Decisions

### Decision 1 — Step 4b execution layer: TEAM-LEAD MAIN-CHAT CONTEXT

**Read**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` lines 590–631 (heading `## Step 4b: Issue Lifecycle Completion`).

**Conclusion**: Step 4b is currently a bash block in the team lead's main-chat context. The skill body says "After the audit-pr agent creates the PR, and before spawning the retrospective, **the team lead** completes the issue lifecycle for this build" and follows with bare bash blocks. There is no `Agent` spawn, no `TaskCreate`, no `qa-engineer`-style sub-agent for Step 4b. The retrospective is the next thing spawned after.

**Decision**: KEEP the team-lead main-chat layer. Do NOT factor Step 4b out into a dedicated agent for this PRD. The fix is ~30 lines of bash; agentizing it would (a) require a new agent definition + task wiring, (b) cost a fresh-context spawn for what should be a deterministic shell loop, and (c) add a coordination point with no benefit. The PRD's risks section explicitly recommends "team lead; plan phase confirms" — confirmed.

**Implication for tasks.md**: All Phase A + Phase B tasks edit `plugin-kiln/skills/kiln-build-prd/SKILL.md` directly. No new agent files are created.

### Decision 2 — FR-008 shelf-skill sweep: ZERO additional skills in scope

**Read**: `plugin-shelf/skills/{shelf-update,shelf-release,shelf-create,shelf-status,shelf-feedback,shelf-repair}/SKILL.md` and `plugin-shelf/workflows/{shelf-create,shelf-sync,shelf-write-issue-note}.json`.

**Sweep findings**:

| Skill / workflow | Reads `.shelf-config`? | Composes path from `base_path + slug`? | Discovery anti-pattern? | Verdict |
|---|---|---|---|---|
| `shelf-update` | Yes — explicit "Priority order: explicit argument > `.shelf-config` > git remote defaults" | Yes — `{base_path}/{slug}/progress/{YYYY-MM}.md` | No | **OK — no change** |
| `shelf-release` | Yes — same priority chain | Yes — `{base_path}/{slug}/releases/v{version}.md` | No | **OK — no change** |
| `shelf-create` (workflow) | Yes — `read-shelf-config` step | Verifies/creates base_path via `list_files` (legitimate first-time scaffold; not a per-write discovery cost) | No (intentional) | **OK — no change** |
| `shelf-status` | Yes — same priority chain | Yes — uses `{base_path}/{slug}/{slug}.md` | One `list_files({base_path}/{slug}/progress)` for progress enumeration — that's content listing, not path discovery | **OK — no change** |
| `shelf-feedback` | Yes — same priority chain | Yes | No | **OK — no change** |
| `shelf-repair` | Yes — STOPs if `.shelf-config` missing | Yes | No | **OK — no change** |
| `shelf-sync` (workflow) | Yes (transitive via compute-work-list) | Yes | The agent step has a guarded ONE manifest-scope `list_files` for `@inbox/open/` reconciliation — explicitly documented as the only listing call permitted. Not a discovery anti-pattern. | **OK — no change** |
| `shelf-write-issue-note` (workflow) | Yes (loose parse) but no `path_source` instrumentation; vulnerable to malformed `.shelf-config` quietly degrading to fallback derivation | Yes when parse succeeds | Bug — instrumentation gap + parser is `cat`-based not defensive | **IN SCOPE — Phase C** |

**Decision**: FR-008 is satisfied trivially by fixing `shelf-write-issue-note` alone. NO additional shelf skills are added to scope. NO follow-on issues need to be filed (the sweep found no additional gaps).

**Implication for tasks.md**: Phase D is **dropped** — no tasks needed. The 6-phase plan compresses to 5 phases (A, B, C, E, F).

### Decision 3 — Diagnostic log retention: ACCEPT DEFAULT (`keep_last: 10`)

**Read**: PRD §risks recommendation, CLAUDE.md `.kiln/logs/` retention policy.

**Decision**: Accept the default `keep_last: 10` retention for `.kiln/logs/build-prd-step4b-<date>.md` files. Rationale:
- The hygiene audit's `merged-prd-not-archived` rule is the durable safety net (PR #144). Even if a diagnostic log rolls out, the underlying PRD merge state is recoverable.
- One pipeline ≈ one log line per day (Step 4b runs once per pipeline); even at 10 pipelines/week the date-bucketed file holds all of one day's runs and `keep_last: 10` retains ~10 days of distinct date files. Plenty for diagnosing recent regressions.
- A separate retention category would add a kiln-manifest entry + extra cleanup logic for marginal gain.

**Implication for tasks.md**: No special log-rotation work. The existing `.kiln/logs/` cleanup that `kiln-cleanup` already handles applies.

## Architecture & Tech Stack

Inherited — no additions:

- **Language**: Bash 5.x (Step 4b loop + shelf-config parser), Markdown (skill body), JSON (workflow definitions).
- **Tools**: `grep`, `sed`, `awk`, `tr`, `mv`, `mkdir`, `find`, `git`, `date`. All POSIX. `jq` already present for the existing `finalize-result` step.
- **MCP**: `mcp__claude_ai_obsidian-projects__create_file`, `mcp__claude_ai_obsidian-projects__patch_file` (existing).
- **No new agents.** Step 4b stays in team-lead main-chat per Decision 1. The `obsidian-write` agent in `shelf-write-issue-note` gets an instruction tweak — same agent.

## File Touch List

### Modified

| File | Change | Phase |
|---|---|---|
| `plugin-kiln/skills/kiln-build-prd/SKILL.md` | Replace Step 4b body (lines 590–631) with the new pseudocode in `contracts/interfaces.md` §1 | A, B |
| `plugin-shelf/workflows/shelf-write-issue-note.json` | Replace `read-shelf-config` step's command with defensive parser; extend `obsidian-write` agent instruction with `path_source` field; extend result-JSON contract | C |
| `.specify/memory/constitution.md` | No change |

### Created

| File | Purpose | Phase |
|---|---|---|
| `specs/pipeline-input-completeness/spec.md` | This spec | (specifier) |
| `specs/pipeline-input-completeness/plan.md` | This plan | (specifier) |
| `specs/pipeline-input-completeness/tasks.md` | Task breakdown | (specifier) |
| `specs/pipeline-input-completeness/contracts/interfaces.md` | Bash pseudocode + JSON schemas + parse routine | (specifier) |
| `specs/pipeline-input-completeness/SMOKE.md` | Fixture + assertion document (SC-008) | E |
| `specs/pipeline-input-completeness/agent-notes/<agent>.md` | Friction notes | (per agent) |

### Deleted

None.

## Phase Plan

### Phase A — Step 4b: feedback scan + matching loop (FR-001, FR-002)

Edit `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b body. Replace the single-dir `for issue_file in .kiln/issues/*.md` loop with a two-dir loop (`for f in .kiln/issues/*.md .kiln/feedback/*.md`). Update the `mv` target to preserve the originating directory (`$(dirname "$f")/completed/`).

**Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`
**Tasks**: 2 (T01-1 scan loop; T01-2 archive logic with originating-dir preservation)

### Phase B — Step 4b: normalization + diagnostic + log marker (FR-003, FR-004, FR-005)

Add the path-normalization helper (strip `./`, trailing `/`, whitespace; reject absolute), the per-file `skipped` counter, the single diagnostic line, and the `.kiln/logs/build-prd-step4b-<date>.md` append. Adjust the commit step to include the log file even on a zero-match run.

**Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`
**Tasks**: 3 (T02-1 normalizer; T02-2 diagnostic emit; T02-3 log file + commit-on-zero-match)

### Phase C — `shelf-write-issue-note`: defensive parse + `path_source` (FR-006, FR-007)

Replace the `read-shelf-config` step's command with the defensive `key = value` parser (mirrors `shelf-counter.sh`'s `_read_key()`). The parser extracts `slug`, `base_path`, `dashboard_path` and emits them on stdout in a known shape that the `obsidian-write` agent can parse unambiguously. Update the `obsidian-write` agent instruction to:
- Recognize the new structured input.
- Emit `path_source` in result JSON (one of the two literal strings in spec.md FR-006/FR-007).
- Use the FR-007 fallback unchanged when parse signals incomplete config.

Update the `finalize-result` step's fallback JSON to include `path_source: "unknown"` when the agent's result is malformed.

**Files**: `plugin-shelf/workflows/shelf-write-issue-note.json`
**Tasks**: 3 (T03-1 read-shelf-config defensive parser; T03-2 obsidian-write agent contract update; T03-3 finalize-result fallback)

### ~~Phase D — Other shelf skills sweep~~ (DROPPED per Decision 2)

Sweep performed in plan phase. Result: zero additional skills in scope. No tasks.

### Phase E — Smoke fixtures + SMOKE.md (SC-008)

Create `specs/pipeline-input-completeness/SMOKE.md` with two fixture sections:

1. **Step 4b two-source fixture** — bash setup (creates 2 fixture files in `.kiln/issues/` and `.kiln/feedback/`), the exact `Step 4b` invocation, and the post-run `find`/`grep` assertions.
2. **`shelf-write-issue-note` shelf-config-present/absent fixture** — bash setup (saves and restores `.shelf-config`), runs the workflow against a synthetic issue file, and inspects `.wheel/outputs/shelf-write-issue-note-result.json` for `path_source`.

Each fixture section ends with copy-pasteable bash that prints `OK` or `FAIL`.

**Files**: `specs/pipeline-input-completeness/SMOKE.md`
**Tasks**: 2 (T04-1 Step 4b fixture; T04-2 shelf-write-issue-note fixture)

### Phase F — Backwards-compat verification (NFR-002, SC-005, SC-007)

Run the SC-005 fixture (rename `.shelf-config` → re-run → restore) end-to-end. Run the SC-007 reverse check (toggle Step 4b off, confirm hygiene audit still flags drift). Document the verification results inline in `specs/pipeline-input-completeness/agent-notes/implementer.md` (the implementer's own friction note).

**Files**: `specs/pipeline-input-completeness/agent-notes/implementer.md` (verification log)
**Tasks**: 1 (T05-1 backwards-compat verify)

## Risks (implementation-side)

| Risk | Mitigation |
|---|---|
| Editing Step 4b in SKILL.md breaks the markdown structure (heading anchors, line counts) | Replace ONLY the bash blocks under `## Step 4b`; preserve all surrounding prose verbatim |
| The `obsidian-write` agent's existing instruction is one giant string in JSON — easy to break the JSON | Use `jq` to validate the workflow JSON after every edit (`jq . plugin-shelf/workflows/shelf-write-issue-note.json > /dev/null`) |
| `read-shelf-config` step output format change might break the existing `obsidian-write` parsing | Keep the legacy `cat`-output structure as a SUPERSET — emit `slug = ...` and `base_path = ...` lines exactly as before, prepended by a `## SHELF_CONFIG_PARSED` header that the agent can rely on. Backwards-compatible with any cached prompts. |
| `mv` race conditions if Step 4b is invoked twice concurrently | Out of scope — Step 4b runs once per pipeline serially; not concurrency-critical |
| Diagnostic-line literal format drift between what FR-003 says and what the implementer writes | Pin the literal template in `contracts/interfaces.md` §2 — the implementer copies it verbatim |
| `path_source` literal string drift | Pin both literal strings in `contracts/interfaces.md` §4 — the agent emits one of two exact strings |

## Verification Gates

Before merging, the implementer MUST:
1. Run the SMOKE.md Step 4b fixture; assertion script prints `OK`.
2. Run the SMOKE.md shelf-write-issue-note both-modes fixture; both assertion scripts print `OK`.
3. `jq . plugin-shelf/workflows/shelf-write-issue-note.json > /dev/null` exits 0.
4. `git status --short` after each phase shows only the files this plan lists as "Modified" + the spec artifacts.

The auditor MUST verify all 8 SCs against the final state. No partial credit.
