# Implementation Plan: Manifest-Evolution Ledger — V1 Pure-History View

**Branch**: `build/manifest-evolution-ledger-20260427` | **Date**: 2026-04-27 | **Spec**: [spec.md](./spec.md)
**PRD**: [docs/features/2026-04-27-manifest-evolution-ledger/PRD.md](../../docs/features/2026-04-27-manifest-evolution-ledger/PRD.md)

## Summary

Ship a single new `/kiln:kiln-ledger` skill plus four shell scripts under `plugin-kiln/scripts/ledger/` that stitch three already-populated capture substrates into one chronological markdown table:

- **Orchestrator** (skill body) — parses `--since / --type / --substrate` flags, dispatches the three readers in parallel, aggregates NDJSON, pipes to the renderer, tees output to stdout + `.kiln/logs/ledger-<timestamp>.md`.
- **Three readers** — `read-mistakes.sh`, `read-proposals.sh`, `read-edits.sh` — each emits NDJSON one-row-per-event from its substrate.
- **One renderer** — `render-timeline.sh` — sorts the unified NDJSON by `(date DESC, source ASC)` under `LC_ALL=C` and emits the markdown report with banner / events table / Notes section.

Single-implementer scope: one owner (`implementer`) walks Phases 1 → 6 sequentially. No concurrent-staging hazard; all edits land in NEW paths (no existing skills/scripts modified — NFR-005 enforces this via SC-004).

## Technical Context

**Language/Version**: Bash 5.x (shell-only V1 — NFR-003); markdown for skill body; YAML frontmatter for the SKILL.md metadata block.
**Primary Dependencies**: `bash`, `jq` (NDJSON aggregation + parse), `git` (log filter + commit body inspection), `LC_ALL=C` for cross-platform byte-identical sort. Obsidian MCP shim (existing — same one `/kiln:kiln-mistake` and `shelf:shelf-propose-manifest-improvement` use) for `read-proposals.sh`. NO new runtime deps.
**Storage**: Plain markdown reports under `.kiln/logs/`. NO `.kiln/ledger/*.md` artifact — V1 is derived (OQ-3 resolution).
**Testing**: `plugin-kiln/tests/<fixture>/run.sh` shell-harness pattern (existing kiln-test convention; substrate gap B-1 means harness can't discover but local invocation works). Six new fixtures (one per SC).
**Target Platform**: macOS + Linux (existing kiln dev surfaces). `LC_ALL=C` invariant ensures cross-platform byte-identity (NFR-001).
**Project Type**: Plugin — `plugin-kiln/`. New skill + new scripts + new tests; no consumer-side `src/` work.
**Performance Goals**: V1 has no hard latency budget (PRD OQ-3 says "if V1 takes 30+ seconds to render, V2 revisits"). Implementer should record the observed wall-clock against this repo's actual corpus in `agent-notes/implementer.md` for future reference.
**Constraints**: Workflow portability (CLAUDE.md §"Plugin workflow portability" — N/A here since the skill is invoked directly, not via wheel); senior-engineer-merge bar; constitution Articles VII (Interface Contracts) and VIII (Incremental Task Completion); architectural rule that the MANIFEST_EDIT_PATTERNS constant lives in ONE place (FR-007).
**Scale/Scope**: This repo has ~12 mistake captures, ~5 inbox proposals, ~80 manifest-edit commits since 2026-01-01. V1 must render this corpus without timing out (no hard budget — see Performance Goals).

## Constitution Check

*GATE: passes before Phase 0.*

- **I. Spec-First** — spec.md is committed before any implementation; every script function carries an `FR-NNN` comment; every test cites its acceptance scenario or SC.
- **II. 80% Coverage** — six `run.sh` fixtures exercise each FR/SC; the assertion-block-count proxy is documented in NFR-004 (substrate gap B-1 carve-out). Each fixture contains ≥4 distinct `assert_*` invocations.
- **III. PRD as Source of Truth** — every spec FR cites its source FR number in the PRD. No divergence from the PRD's scope or non-goals (notably: V1 is observation-only, no recurrence detection).
- **IV. Hooks Enforce Rules** — edits land entirely under `plugin-kiln/skills/`, `plugin-kiln/scripts/`, `plugin-kiln/tests/`. The `require-spec.sh` hook gates only on consumer-`src/` edits, so plugin-author edits are unaffected (existing convention).
- **V. E2E Required** — six `run.sh` fixtures exercise the real shell scripts and skill orchestrator end-to-end against fixture corpora.
- **VI. Small, Focused Changes** — each task touches one bounded area; no file exceeds 500 lines after edits. Largest expected file: `kiln-ledger/SKILL.md` body at ~250 lines.
- **VII. Interface Contracts** — `contracts/interfaces.md` defines (a) each reader's stdin/argv inputs + NDJSON row schema + exit codes, (b) `render-timeline.sh`'s stdin format + stdout markdown shape + sort key + LC_ALL=C invariant, (c) the orchestrator's flag-parsing behavior + output-file path + degradation banner.
- **VIII. Incremental Tasks** — tasks.md is structured into phases; `[X]` after each task; commit after each phase.

No violations. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/manifest-evolution-ledger/
├── plan.md                          # This file
├── spec.md                          # Feature specification (committed first)
├── contracts/
│   └── interfaces.md                # Reader/renderer/orchestrator signatures
├── tasks.md                         # Task breakdown (/tasks output)
└── agent-notes/                     # Per-agent friction notes
    └── specifier.md                 # This agent's notes (FR-009)
```

### Source Code (plugin-kiln edits — all NEW paths; SC-004 enforces additivity)

```text
# Skill (new directory)
plugin-kiln/skills/kiln-ledger/SKILL.md           # NEW — orchestrator skill body

# Scripts (new directory under plugin-kiln/scripts/ledger/)
plugin-kiln/scripts/ledger/read-mistakes.sh       # NEW — reader for .kiln/mistakes/
plugin-kiln/scripts/ledger/read-proposals.sh      # NEW — reader for shelf @inbox/ via MCP
plugin-kiln/scripts/ledger/read-edits.sh          # NEW — reader for git log + MANIFEST_EDIT_PATTERNS
plugin-kiln/scripts/ledger/render-timeline.sh     # NEW — sort + render markdown table

# Tests (one fixture per SC)
plugin-kiln/tests/ledger-chronological-emission/run.sh        # SC-001
plugin-kiln/tests/ledger-filter-shape/run.sh                  # SC-002
plugin-kiln/tests/ledger-degraded-substrate/run.sh            # SC-003
plugin-kiln/tests/ledger-back-compat/run.sh                   # SC-004
plugin-kiln/tests/ledger-proposal-edit-linking/run.sh         # SC-005
plugin-kiln/tests/ledger-orchestrator-reader-split/run.sh     # SC-006
```

**Structure Decision**: Plugin-source edits only, ALL into NEW paths. No edits to existing skills, scripts, or tests anywhere in the repo (NFR-005 / SC-004). The fixture set uses the `run.sh` shape (substrate gap B-1 carve-out per NFR-004).

## Phase 0 — Research

(All decisions inherited from the PRD, the spec's "Open Questions" resolved section, and the existing PR #193 Theme D precedent.)

| ID | Question | Decision | Source |
|----|----------|----------|--------|
| R-1 | Where does the orchestrator live — single SKILL.md body, or a wrapper script? | SKILL.md body (Bash blocks invoked by Claude Code skill harness). Matches `/kiln:kiln-escalation-audit` precedent. Avoids the orchestration-vs-skill-instructions split. | PRD FR-006, escalation-audit precedent |
| R-2 | NDJSON aggregation — concatenated streams or `jq -s`? | Concatenated streams piped to the renderer. Each reader writes one JSON object per line; `render-timeline.sh` reads stdin line-by-line, parses with `jq -c`, sorts via `sort -k1,1r -k3,3` (LC_ALL=C). Avoids loading the entire timeline into memory unnecessarily. | NFR-001, NFR-003 |
| R-3 | How does `read-proposals.sh` invoke shelf MCP? | Same shim path that `/kiln:kiln-mistake` already exercises. The reader shells out to `claude mcp call obsidian-projects.list_inbox_open` (or whatever the existing shim entry-point is). When the shim exits non-zero or `MCP_SHELF_DISABLED=1` is set, the reader exits non-zero — orchestrator catches and applies degraded-substrate banner. | spec FR-005, NFR-002, R-2 |
| R-4 | Sort tiebreak — what's the second sort key? | `source` path (alphabetical, LC_ALL=C). Stable, deterministic, no clock dependency. Matches NFR-001 byte-identity invariant. | spec NFR-001 |
| R-5 | Where does `--since` default get computed? | Inside the orchestrator, before reader dispatch: `DEFAULT_SINCE="$(date -u -v-30d +%Y-%m-%d 2>/dev/null \|\| date -u -d '30 days ago' +%Y-%m-%d)"`. Cross-platform fallback (macOS BSD date / Linux GNU date). | spec FR-003 |
| R-6 | How is the proposal-edit back-link parsed? | `read-edits.sh` greps the commit body (via `git log --format=%B`) for `applies inbox/(open\|applied)/[^[:space:]]+\.md` per commit. First match wins; emit empty resolution if no match. The Notes section's missing-link aggregate is computed by the renderer counting empty-resolution `edit` rows. | spec edge case, R-1, SC-005 |
| R-7 | What's the minimal MANIFEST_EDIT_PATTERNS git-log query? | `git log --since="$SINCE" --grep="^chore(claude-md):" --grep="^pi-apply:" --grep="^chore(roadmap):" --grep="^chore: apply manifest improvement"` — multiple `--grep` flags are OR-combined by git. Pattern array translates to multiple `--grep=` argv entries assembled in shell. | spec FR-007, OQ-1 |

No outstanding NEEDS CLARIFICATION items. Phase 0 complete.

## Phase 1 — Design & Contracts

### Data shapes

- **Reader NDJSON row** (common schema across all three readers):
  ```json
  {"date":"YYYY-MM-DD","type":"mistake|proposal-open|proposal-applied|edit","source":"<path-or-hash>","summary":"<≤120ch>","resolution":"<commit-hash|proposal-path|>"}
  ```
- **Orchestrator → renderer pipe**: concatenated NDJSON on stdin, one row per line, no trailing newline before EOF.
- **Renderer output (`render-timeline.sh` → stdout)**:
  ```markdown
  # Manifest-Evolution Ledger — <ISO-8601-timestamp>

  Substrates included: <csv> — (<reason>)        # only if degraded (NFR-002)

  ## Events

  | Date | Type | Source | Summary | Resolution |
  |------|------|--------|---------|------------|
  | YYYY-MM-DD | mistake | [.kiln/mistakes/<file>] | <summary> | — |
  | ... | ... | ... | ... | ... |

  ## Notes

  - <K> edits found, <J> lacked proposal back-references            # only if any edit lacks back-ref
  - note: proposal <id> used file-mtime fallback (no date frontmatter)  # one per fallback
  - No events found in the requested window.                        # only if 0 events total
  ```
- **Audit-log file**: byte-identical to stdout, written via `tee` to `.kiln/logs/ledger-<YYYY-MM-DD-HHMMSS>.md`.
- **Diagnostic line on degraded substrate** (emitted to stderr, not the report): `degraded: substrate=proposals reason=shelf-unavailable exit=<N>`.

See `contracts/interfaces.md` for full signatures.

### Constitution re-check (post-design)

Still passing — the data shapes above introduce no new violations.

## Phase 2 — Tasks (handed off to `/tasks`)

`tasks.md` is generated by the `/tasks` step from this plan + spec. Tasks are organized by user story to allow independent verification. Implementer assignment:

- **`implementer`** owns Phases 1 (setup), 3 (US1 — chronological view + readers + renderer), 4 (US2 — filter shape), 5 (US3 — degraded substrate), 6 (cross-cutting — back-compat + linking + reader-add-extensibility), 7 (polish).
- Single owner — no concurrent-staging hazard since all edits land in NEW paths.

## Complexity Tracking

(No constitution violations to justify.)

## Risks & Mitigations (carry-forward)

- **R-1 (proposal-edit linkage)** — edit commits often lack `applies inbox/...` references. Mitigation: render `—` in resolution column AND surface the missing-link aggregate in Notes (FR-002, SC-005).
- **R-2 (shelf MCP brittleness)** — MCP can be down in CI/headless. Mitigation: `--substrate mistakes,edits` flag opt-out; auto-degrade detects reader exit-non-zero and applies banner (FR-005, NFR-002, SC-003).
- **R-3 (V2 recurrence-detection design)** — explicitly out of scope. Mitigation: V1 ships observation-only; V2 PRD revisits after 30 days.
- **R-4 / B-1 (kiln-test harness can't discover run.sh)** — accepted carve-out per NFR-004; assertion-block count is the coverage proxy. Implementer MUST NOT silently downgrade fixture format.
- **NFR-001 byte-identity across platforms** — risk that macOS BSD `sort` produces different output than GNU `sort` on UTF-8 content. Mitigation: `LC_ALL=C sort` invariant declared in `render-timeline.sh` contract.
- **`--since` cross-platform date math** — macOS BSD `date -v-30d` vs GNU `date -d '30 days ago'`. Mitigation: orchestrator uses `||` fallback (R-5).
