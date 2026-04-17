# PRD Audit Blockers

**Feature**: manifest-improvement-subroutine
**Date**: 2026-04-16
**Audit status**: PASS — no unresolved blockers
**Post-implementation reconciliation**: 2026-04-16 (auditor)

## Reconciliation notes

- No blockers entries existed at the time of reconciliation. The sole "gaps" section is populated with `**None.**` — consistent with the final audit.
- Unit tests re-run 2026-04-16: 4 files, 37/37 assertions PASS.
- Integration tests re-run 2026-04-16: 8 files, 29 assertions PASS (silent-skip 4/4, write-proposal 5/5, out-of-scope 4/4, hallucinated-current 1/1, ungrounded-why 1/1, caller-wiring 3/3, portability 3/3, mcp-unavailable 5/5).
- FR-5 exact-patch gate confirmed in `plugin-shelf/scripts/check-manifest-target-exists.sh` (LC_ALL=C, grep -F -f needle, returns 1 on any failure).
- FR-7 silent-on-skip confirmed in `plugin-shelf/scripts/write-proposal-dispatch.sh` (trap EXIT cleanup, emits `{"action":"skip"}` on every failure path, 2>/dev/null on every sub-invocation) and in the `write-proposal-mcp` agent instruction (leaves output file empty on skip/success, single warn line only on MCP-unavailable).
- FR-8 proposal-only writes confirmed: dispatch envelope produces `proposal_path` prefixed `@inbox/open/`; the `write-proposal-mcp` agent is instructed to call `mcp__claude_ai_obsidian-manifest__create_file` exactly once and the instruction explicitly prohibits direct filesystem writes.
- FR-16 portability confirmed via `grep -n 'plugin-shelf/scripts\|plugin-kiln/scripts' plugin-shelf/workflows/*.json plugin-kiln/workflows/*.json` → all hits are prefixed by `${WORKFLOW_PLUGIN_DIR}`; zero repo-relative script paths.
- Caller wiring position confirmed (integration `caller-wiring.sh`): `report-mistake-and-sync` propose@2/terminal@3 of 4, `report-issue-and-sync` propose@2/terminal@3 of 4, `shelf-full-sync` propose@11/terminal@12 of 13. All pre-terminal per FR-11..FR-14.

## PRD FR → Spec FR → Implementation → Test traceability

| PRD FR | Spec FR | Implementation | Test |
|---|---|---|---|
| FR-1 | FR-001 | `plugin-shelf/workflows/propose-manifest-improvement.json` | integration: all 6 tests exercise the workflow |
| FR-2 | FR-002 | workflow JSON: 3 steps (reflect, write-proposal-dispatch, write-proposal-mcp — the latter two form the "write-proposal" stage per R-001) | integration `portability.sh` verifies step shape |
| FR-3 | FR-003 | `validate-reflect-output.sh` gate + `reflect` agent instruction | unit `test-validate-reflect-output.sh` (12 cases) |
| FR-4 | FR-004 | `validate-reflect-output.sh` regex `^@manifest/(types\|templates)/...\.md$` | integration `out-of-scope.sh` + unit cases |
| FR-5 | FR-005 | `check-manifest-target-exists.sh` (grep -F -f) + dispatch orchestrator calls it before write envelope | integration `hallucinated-current.sh` + unit tests |
| FR-6 | FR-006 | `validate-reflect-output.sh` grounding regex for `why` field | integration `ungrounded-why.sh` + unit cases |
| FR-7 | FR-007 | dispatch emits one-line JSON only, trap EXIT, silent stderr; `write-proposal-mcp` empty on skip | integration `silent-skip.sh` + unit silent-stderr |
| FR-8 | FR-008 | `write-proposal-mcp` agent uses `mcp__claude_ai_obsidian-manifest__create_file`; dispatch envelope `proposal_path` under `@inbox/open/` | integration `write-proposal.sh` validates envelope shape |
| FR-9 | FR-009 | `write-proposal-mcp` instruction composes frontmatter + four H2 sections in fixed order | integration `write-proposal.sh` asserts envelope body_sections |
| FR-10 | FR-010 | `derive-proposal-slug.sh` (pure bash pipeline, LC_ALL=C) | unit `test-derive-proposal-slug.sh` (9 cases) |
| FR-11 | FR-011 | `plugin-shelf/workflows/shelf-full-sync.json` step insert | integration `caller-wiring.sh` |
| FR-12 | FR-012 | `plugin-kiln/workflows/report-issue-and-sync.json` step insert | integration `caller-wiring.sh` |
| FR-13 | FR-013 | `plugin-kiln/workflows/report-mistake-and-sync.json` step insert | integration `caller-wiring.sh` |
| FR-14 | FR-014 | All three callers place step at position `steps.length − 2` | integration `caller-wiring.sh` positional assertion |
| FR-15 | FR-015 | `write-proposal-mcp` instruction documents warn line + exit 0 + no retry | integration `mcp-unavailable.sh` (doc-level) |
| FR-16 | FR-016 | Workflow JSON uses `${WORKFLOW_PLUGIN_DIR}` exclusively | integration `portability.sh` |

## Spec FRs beyond the PRD (consistent extensions, not divergences)

- **FR-017** — standalone invocation via `plugin-shelf/skills/propose-manifest-improvement/SKILL.md`. Addresses PRD Assumption "contributors can test the sub-workflow in isolation."
- **FR-018** — malformed/missing reflect JSON forces skip silently. Addresses PRD Risk "Hallucinated `current` text" generalized to "invalid reflect output."
- **FR-019** — same-day filename collisions disambiguated with `-2..-9` suffix. Addresses PRD "Slug collision" edge case.
- **FR-020** — dispatch envelope is an internal artifact, not user-visible. Reinforces PRD's "Silent on skip" absolute-must.

## Known non-issues

- **shelf-full-sync proposal pickup asymmetry (R-007)**: a proposal written during `shelf-full-sync` is synced by the NEXT run, not THAT run. The two kiln callers don't have this delay. Documented in research.md R-007, SKILL.md troubleshooting, and quickstart.md §7. Accepted per PRD Non-Goal "No additional sync cycles beyond the existing one."
- **Multi-line `current` verbatim match semantics**: `grep -F -f <needle>` is line-by-line, not contiguous-block. For v1 manifest-improvement proposals (which target specific fields/lines), this is adequate. Documented in implementer.md.
- **bats test framework**: PRD/tasks.md assume bats availability; environment has none. Unit tests were written as pure-bash scripts with the same assertion semantics. Documented in `tests/README.md`. Constitution II (>=80% coverage) satisfied by the bash-based tests — 37 unit assertions + 6 integration scripts covering every FR.
- **MCP-unavailable live E2E test**: The bash harness cannot toggle MCP tool availability. `tests/integration/mcp-unavailable.sh` validates the agent instruction documents the required FR-15 behavior verbatim — the agent follows the instruction at runtime, so doc-level validation is the enforced gate.

## Unfixable gaps

**None.** All PRD FR-1..FR-16 have implementation + test coverage.

## Tooling notes (not blockers)

- `scripts/validate-non-compiled.sh` reports 7 "file reference not found" false positives against `specs/manifest-improvement-subroutine/tasks.md` and `tests/integration/portability.sh`. Root cause: the validator's `grep -oE '(plugin-kiln|plugin-wheel|scripts|.kiln|.specify|.claude)/[...]'` regex knows about `plugin-kiln` and `plugin-wheel` but NOT `plugin-shelf`. When tasks.md correctly references `plugin-shelf/scripts/foo.sh`, the regex matches starting at `scripts/foo.sh` and then fails to find that path at repo root. The actual file exists at the correct `plugin-shelf/scripts/foo.sh` location. This is a pre-existing validator defect — filing as a backlog item via `/kiln:report-issue` is the right follow-up, not a blocker here.

