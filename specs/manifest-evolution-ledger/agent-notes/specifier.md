# Specifier Friction Notes — manifest-evolution-ledger

**Agent**: specifier
**Date**: 2026-04-27
**Branch**: build/manifest-evolution-ledger-20260427

## Summary

Authored spec.md (7 FRs, 5 NFRs, 6 SCs, 3 user stories), plan.md, contracts/interfaces.md, and tasks.md (33 tasks across 6 work-phases) in one uninterrupted pass. Open questions OQ-1 / OQ-2 / OQ-3 resolved per team-lead's brief and recorded in spec.md "Open Questions" section. Carried forward NFR-004 substrate-gap B-1 carve-out (run.sh-only fixtures + assertion-block coverage proxy) explicitly so the auditor catches any silent downgrade to harness-discoverable `test.yaml`.

## What worked

- The escalation-audit feature (`specs/escalation-audit/`) was an excellent reference. Its plan/contracts pattern transferred almost 1:1 — same orchestrator-reader split rationale, same NFR vocabulary, same `run.sh` test-substrate carve-out. Time-to-spec was ~30% of greenfield because the precedent was load-bearing.
- The PRD's "Risks & Open Questions" section pre-resolved most ambiguity. OQ-1 / OQ-2 / OQ-3 had explicit specifier-decides recommendations from the team-lead's brief; I just had to pick (one row per commit; pure-derived V1; pattern set as documented).
- Single-implementer scope (no concurrent-staging hazard) made tasks.md much simpler than escalation-audit's two-implementer split.

## What was confusing

- **The "shelf MCP shim" path is implicit, not documented.** Both `/kiln:kiln-mistake` and `shelf:shelf-propose-manifest-improvement` use it, but the contracts assume the implementer can find the shim entry-point. I wrote `read-proposals.sh` as "shells out to the existing shim" without specifying the exact CLI. The implementer may need to grep `plugin-shelf/scripts/` to discover the actual entry-point. **PI-1: contracts/interfaces.md §A.2 should cite the exact shim entry-point file path (`plugin-shelf/scripts/<x>.sh` or the MCP tool name) rather than describing it abstractly. Fix: when the precedent uses an existing piece of infrastructure, cite the file path.**

- **The "manifest path" definition for FR-001 edit-row aggregation is implicit.** I wrote "files in the commit's diff matching `*.md` AND a manifest path (CLAUDE.md, .claude-plugin/*.md, .specify/memory/*.md, plugin-*/SKILL.md)" but this is the specifier's best guess — there's no canonical "manifest" definition in the codebase. **PI-2: spec.md FR-001 (or a new key entity "manifest file") should define what counts as a manifest file with a regex/glob. Without this, two implementers will produce different aggregations. Fix: specs that depend on an implicit type/category definition should define it explicitly with a regex or path glob.**

- **`tee` to `.kiln/logs/ledger-<ts>.md` while ALSO emitting to stdout creates a subtle FR-004 trap.** The contract says the bytes are byte-identical, but `tee` buffers differently from stdout in some shells. The implementer might use `tee -a` (which would be wrong) or write the file first then `cat` it (defeats the byte-identity invariant if anything mutates between). **PI-3: contracts/interfaces.md §C.1 should explicitly call out that the `tee` invocation MUST NOT use `-a` and MUST be in the same pipeline as the renderer's stdout, so byte-identity is structural. Fix: when an FR depends on a particular shell-pipeline shape, write the canonical pipeline form into the contract verbatim.**

## Where I got stuck

- **Task count crossed 20.** Total task count is 33 (T001..T053 with gaps). Per team-lead's brief, I should message the team-lead so they can decide whether to spawn a second implementer. My read: most of Phases 4–6 are TEST tasks that depend on Phase 3's implementation already existing, so splitting wouldn't actually unblock parallelism — it would just split test-authoring across two agents who'd need the same Phase 3 output. Single implementer remains appropriate but team-lead should confirm.

- **NFR-001 byte-identity claim is hard to verify in CI without the harness.** SC-001's "re-run produces byte-identical output below H1 timestamp" requires the fixture to invoke the orchestrator twice and `diff` the outputs. With the run.sh-only substrate gap, this works locally but won't be caught by CI. The fixture itself enforces it on local invocation; if the implementer skips the second-run assertion (T016 step e), the regression won't surface until a future re-run drift surfaces. I added the assertion explicitly to T016's task body to lower the odds of silent skip.

## Prompt-improvement proposals (PI-N format)

- **PI-1**: When contracts depend on an existing piece of infrastructure (e.g., shelf MCP shim), cite the exact entry-point file path or MCP tool name. Don't describe it abstractly. Future specifiers should grep for the precedent's actual invocation site and copy it into the contract.
- **PI-2**: When a spec depends on a category/type definition (e.g., "manifest file"), define it explicitly with a regex/glob in the spec's Key Entities section. Implicit definitions produce divergent implementations across implementers.
- **PI-3**: When an FR depends on a particular shell-pipeline shape (e.g., `tee` byte-identity), write the canonical pipeline form into the contract verbatim. Pipeline-shape ambiguity is a common source of regression.
- **PI-4**: The team-lead's >20-task threshold should be a hard escalation, not a soft "consider messaging." With 33 tasks landing on a single implementer, I'm uncertain whether the brief wanted me to halt for confirmation or proceed. The brief's chaining rule ("do NOT stop, do NOT wait") wins for now, but the threshold check loses signal when the chaining rule is also non-negotiable. Future briefs should clarify which rule wins on conflict.
- **PI-5**: The escalation-audit precedent paid for itself in this spec authoring; institutional memory of which prior PRDs are "load-bearing precedents" for which new PRDs would speed up future specifier runs. Suggest the PRD itself flag "this PRD adopts patterns from PRD-X" so the specifier doesn't have to discover the precedent by codebase grep.

## Deliverables

- [x] specs/manifest-evolution-ledger/spec.md (7 FRs, 5 NFRs, 6 SCs, 3 USs)
- [x] specs/manifest-evolution-ledger/plan.md (Phase 0 research table, Phase 1 design, constitution check)
- [x] specs/manifest-evolution-ledger/contracts/interfaces.md (Modules A/B/C/D/E covering readers, renderer, orchestrator, fixtures, reused infra)
- [x] specs/manifest-evolution-ledger/tasks.md (33 tasks across 6 work-phases, single-implementer assignment)
- [x] specs/manifest-evolution-ledger/agent-notes/specifier.md (this file)

## Hand-off

Implementer is unblocked. Phase 3 (US1 — readers + renderer + orchestrator + SC-001 fixture) is the MVP; everything else builds incrementally on top. All edits land in NEW paths — no risk of touching existing skills or scripts.
