# Implementation Plan: Merge-PR Skill + Spec-Template SC-Grep Guidance

**Branch**: `build/merge-pr-and-sc-grep-guidance-20260427` | **Date**: 2026-04-27 | **Spec**: [spec.md](./spec.md)
**PRD**: [docs/features/2026-04-27-merge-pr-and-sc-grep-guidance/PRD.md](../../docs/features/2026-04-27-merge-pr-and-sc-grep-guidance/PRD.md)

## Summary

Three themes converge on closing rediscovery cycles in the build-prd substrate:

- **Theme A** (FR-001..FR-011) — Ship `/kiln:kiln-merge-pr <pr>` as the maintainer's atomic merge+flip surface, extract Step 4b.5's inline auto-flip block into `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` for re-use, refactor Step 4b.5 to call the helper, and extend `/kiln:kiln-roadmap --check` with a `--fix` confirm-never-silent mode that calls the same helper. One implementation, three call sites.
- **Theme B** (FR-012..FR-013) — Add an authoring note + recipe to `plugin-kiln/templates/spec-template.md`'s Success Criteria section so future PRDs adopt the date-bound formulation by default.
- **Theme C** (FR-014..FR-016) — Document the `${WHEEL_PLUGIN_<name>}` / `${WORKFLOW_PLUGIN_DIR}` documentary-reference gotcha in `plugin-wheel/lib/preprocess.sh` (module-level comment + extended tripwire error text) and `plugin-wheel/README.md` (Writing agent instructions section).

File ownership is split per NFR-005:

- `impl-roadmap-and-merge` owns Theme A → all `plugin-kiln/skills/kiln-merge-pr/`, `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`, `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 4b.5 refactor), `plugin-kiln/skills/kiln-roadmap/SKILL.md` (`--check --fix`), and `plugin-kiln/tests/auto-flip-on-merge-fixture/`. **`plugin-kiln/.claude-plugin/plugin.json` is NOT touched** — kiln plugin uses filesystem auto-discovery; the manifest has no `skills` array.
- `impl-docs` owns Themes B + C → `plugin-kiln/templates/spec-template.md`, `plugin-wheel/lib/preprocess.sh`, `plugin-wheel/README.md`.

The two implementers run in parallel; their file sets are disjoint. No file is touched by both.

## Technical Context

**Language/Version**: Bash 5.x (skill bodies + helper script); markdown for skill SKILL.md, template, and README; no new runtime languages.
**Primary Dependencies**: `gh` CLI (PR-state queries, merge), `jq` (JSON parsing), `awk` (frontmatter rewrites), `git` (working-tree state checks), Claude Code skill substrate. No new runtime deps.
**Storage**: Plain markdown + YAML files under `.kiln/roadmap/items/`. Helper writes via tempfile + `mv` (atomicity invariant inherited from Step 4b.5).
**Testing**: `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` shell harness (existing kiln-test convention). One new fixture covering FR-008, FR-009, NFR-002 (golden-file byte-equality). FR-010/FR-011 verified by inspection + spec-citation since `--check --fix` requires user input simulation that the in-session test harness already handles per kiln-roadmap conventions.
**Target Platform**: macOS + Linux (existing kiln dev surfaces). The helper relies only on POSIX-compatible tooling already used by `update-item-state.sh`.
**Project Type**: Plugin — `plugin-kiln/` + `plugin-wheel/`. Edits to skill markdown bodies, scripts, templates, README; no consumer-side `src/` work.
**Performance Goals**: Inherited from Step 4b.5 — ≤ 5 s for ≤ 10 items via one cached `gh pr view` + ≤ 10 atomic awk rewrites. The skill adds the `gh pr merge` round-trip (typically 2–10 s); no new latency budget required.
**Constraints**: Workflow portability (CLAUDE.md §"Plugin workflow portability"); senior-engineer-merge bar; constitution Articles VII (Interface Contracts) and VIII (Incremental Task Completion); concurrent-staging hazard (NFR-005, retro #187 PI-1).
**Scale/Scope**: Roadmap is ~84 items today; typical PRD bundles 1–10 derived_from items. `--check --fix` operates on the full drift list (typically ≤ 10 items at any moment).

## Constitution Check

*GATE: passes before Phase 0.*

- **I. Spec-First** — spec.md is committed before any implementation; every script function will carry an `FR-NNN` comment; the regression fixture cites SC-002.
- **II. 80% Coverage** — Bash helper is tested via `run.sh` fixture against golden files (NFR-002); `--check --fix` confirm-never-silent flow is covered by spec-citation tests + grep assertions on the rendered SKILL.md body. Helper's idempotency branch + missing-entry branch + `gh-unavailable` branch each have a fixture case.
- **III. PRD as Source of Truth** — every spec FR cites its source FR in the PRD by number. No divergence from the PRD's scope or non-goals.
- **IV. Hooks Enforce Rules** — this PRD's edits land in `plugin-kiln/skills/`, `plugin-kiln/scripts/`, `plugin-kiln/tests/`, `plugin-kiln/templates/`, `plugin-wheel/lib/`, `plugin-wheel/README.md`. The `require-spec.sh` hook gates only on consumer-`src/` edits, so plugin-author edits are unaffected (existing convention).
- **V. E2E Required** — the `auto-flip-on-merge-fixture/run.sh` exercises the real shell helper against real frontmatter. The live-fire SC-001 / SC-007 closes the loop on the PR for THIS PRD itself.
- **VI. Small, Focused Changes** — each task touches one bounded area; no file exceeds 500 lines after edits except `kiln-build-prd/SKILL.md` (existing 1502 lines; this PRD strictly DECREASES that count via FR-009 extraction). The new `kiln-merge-pr/SKILL.md` is expected to land at ~120 lines; `auto-flip-on-merge.sh` at ~80 lines.
- **VII. Interface Contracts** — `contracts/interfaces.md` defines the helper signature, `/kiln:kiln-merge-pr` flag/arg surface, the canonical diagnostic line shape (byte-identical to Step 4b.5), the `--check --fix` confirm-never-silent contract, and the spec-template/preprocess-comment/README-section authoring shapes.
- **VIII. Incremental Tasks** — tasks.md is structured into phases per implementer; `[X]` after each task; commit after each phase.

No violations. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/merge-pr-and-sc-grep-guidance/
├── plan.md                          # This file
├── spec.md                          # Feature specification (committed first)
├── contracts/
│   └── interfaces.md                # Helper + skill + authoring-shape contracts
├── tasks.md                         # Task breakdown (/tasks output)
├── agent-notes/                     # Per-agent friction notes
│   └── specifier.md                 # This agent's notes (REQUIRED)
└── blockers.md                      # Created on demand by audit-prd if needed
```

### Source Code (plugin edits)

```text
# Theme A — impl-roadmap-and-merge
plugin-kiln/skills/kiln-merge-pr/SKILL.md             # NEW skill
plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh     # NEW shared helper
plugin-kiln/skills/kiln-build-prd/SKILL.md            # Step 4b.5 refactor (inline → helper call)
plugin-kiln/skills/kiln-roadmap/SKILL.md              # +--fix mode (extends existing --check Check 5)
plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh   # NEW regression fixture
plugin-kiln/tests/auto-flip-on-merge-fixture/golden/  # Snapshot pre/post commit 22a91b10
                                                       # NOTE: plugin-kiln/.claude-plugin/plugin.json is NOT edited.
                                                       # Kiln uses filesystem auto-discovery; manifest has no skills array.

# Theme B — impl-docs
plugin-kiln/templates/spec-template.md                # +SC-grep date-bound authoring note + recipe

# Theme C — impl-docs
plugin-wheel/lib/preprocess.sh                        # +module-level documentary-references comment;
                                                       # +extended FR-F4-5 tripwire error text
plugin-wheel/README.md                                # +"Writing agent instructions" section
```

## Phase 0 — Outline & Research

No new research needed. The Step 4b.5 block is shipped, fixture-tested, and live in `kiln-build-prd/SKILL.md` lines ~1019–1110 of commit `1c55419d` (current HEAD on this branch). Frontmatter mutation invariants, idempotency rules, and diagnostic line shape are pinned in [specs/escalation-audit/contracts/interfaces.md §A.2](../escalation-audit/contracts/interfaces.md). The extraction is mechanical.

For Theme B, the recipe form is already pinned in the PRD's FR-012:

```bash
git log --name-only --pretty='' --since='YYYY-MM-DD' -- '<glob>' | sort -u | xargs -I{} git grep -lE '<pattern>' -- {}
```

For Theme C, the failure-mode prose is pinned in the PRD's FR-014/FR-015/FR-016. No exploration needed.

## Phase 1 — Design Artifacts

The contracts artifact at `specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md` is the canonical reference for:

- `auto-flip-on-merge.sh <pr-number> <prd-path>` signature, arg semantics, output contract, exit codes (Module A).
- `/kiln:kiln-merge-pr <pr> [--squash|--merge|--rebase] [--no-flip]` flag surface and end-to-end stage contract (Module B).
- `/kiln:kiln-roadmap --check --fix` confirm-never-silent prompt + per-item fix invocation contract (Module C).
- Spec-template authoring-note shape (Module D).
- Preprocess module-level comment + tripwire-error-extension shape (Module E).
- Wheel README "Writing agent instructions" section shape (Module F).
- The `auto-flip-on-merge-fixture/run.sh` golden-file fixture contract (Module G).

## Phase 2 — Implementation Strategy

Implementation is split into two parallel implementer streams. Each implementer works ONLY on its file set per NFR-005.

### Stream A — `impl-roadmap-and-merge` (Theme A, sequential within stream)

1. **Phase A1 — Extract helper (FR-008, FR-009, NFR-002)**: Create `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` with the verbatim Step 4b.5 logic, accepting `<pr-number> <prd-path>` as positional args. Write the regression fixture under `plugin-kiln/tests/auto-flip-on-merge-fixture/` with golden files captured from commit `22a91b10`. Run the fixture, assert PASS.
2. **Phase A2 — Refactor Step 4b.5 (FR-009, SC-003)**: Replace the inline Bash block in `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b.5 with a single-line `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh "$PR_NUMBER" "$PRD_PATH"` invocation. Preserve the surrounding markdown (purpose, when-this-runs, invariants). Re-run the fixture against the refactored skill body extraction (or re-run the existing `build-prd-auto-flip-on-merge` fixture if its extract pattern still parses); assert PASS.
3. **Phase A3 — Ship `/kiln:kiln-merge-pr` (FR-001..FR-007, NFR-001, NFR-005)**: Author `plugin-kiln/skills/kiln-merge-pr/SKILL.md`. Stages: pre-flight gate → working-tree clean check → conditional `gh pr merge` → wait for `MERGED` → locate PRD via `gh pr view --json files` → invoke helper → commit by exact path with canonical message → push. Surface every diagnostic line per spec.
4. **Phase A4 — Skill registration (CONFIRMED no-op per team-lead)**: Kiln plugin uses filesystem auto-discovery from `skills/`. The manifest at `plugin-kiln/.claude-plugin/plugin.json` has only `workflows` + `agent_bindings` arrays — no `skills` array. Creating `plugin-kiln/skills/kiln-merge-pr/SKILL.md` is sufficient registration. **Do NOT edit `plugin.json`.** This phase is removed from the implementer's worklist; impl-roadmap-and-merge MUST NOT touch the manifest.
5. **Phase A5 — Extend `/kiln:kiln-roadmap --check --fix` (FR-010, FR-011, NFR-004)**: In `plugin-kiln/skills/kiln-roadmap/SKILL.md` §C, after the existing Check 5 output, add a `--fix` mode block that parses Check 5's `[drift]` rows, prompts confirm-never-silent (`[fix all / pick / skip]`), resolves the PR via `gh pr list --state merged --search "head:<branch>"`, and invokes the shared helper for accepted entries. Document ambiguity-skip behavior. Backward-compat (`--check` without `--fix`) is byte-identical.
6. **Phase A6 — Commit + handoff**: After all phases pass, commit each phase by exact path; after the final phase, message audit-traceability + audit-tests with paths and SC mapping.

### Stream B — `impl-docs` (Themes B + C, parallel within stream)

1. **Phase B1 — Spec-template (FR-012, FR-013, SC-005)**: In `plugin-kiln/templates/spec-template.md`, locate the `## Success Criteria *(mandatory)*` section. Append the authoring note + recipe code-fence per contracts §D. Verify via `grep -F 'date-bound qualifier' ...` and recipe-fence string assertion.
2. **Phase B2 — Preprocess module-level comment + extended tripwire error (FR-014, FR-016, SC-006)**: In `plugin-wheel/lib/preprocess.sh`, append a module-level comment block per contracts §E (after the existing module header, near the FR-F4-5 tripwire). Extend the existing `printf` tripwire error string to include the FR-016 explanation line. Verify the rendered tripwire output by tracing a small synthetic input.
3. **Phase B3 — Wheel README authoring section (FR-015, SC-006)**: In `plugin-wheel/README.md`, add a top-level heading `## Writing agent instructions` (or extend an existing workflow-authoring section if one exists; specifier observed only `## Workflow Format` at line ~17). Include the documentary-references rule in author-facing language. Verify via `grep -F 'documentary' plugin-wheel/README.md`.
4. **Phase B4 — Commit + handoff**: After all phases pass, commit each phase by exact path; after the final phase, message audit-traceability + audit-tests with paths and SC mapping.

### Concurrency

- Stream A and Stream B start in parallel (their file sets are disjoint).
- Within Stream A, phases A1 → A2 → A3 are sequential because A2 depends on A1's helper existing, and A3 calls the same helper. A5 runs after A1 (helper extant) and is independent of A2/A3/A4.
- Within Stream B, phases B1, B2, B3 are independent and may run in parallel within `impl-docs`.

## Phase 3 — Audit & PR

Standard build-prd Step 4 audit pipeline applies:

1. `audit-traceability` walks PRD → spec FR → code → test, reports compliance % + uncovered FRs. Owner: agent. Outputs `specs/merge-pr-and-sc-grep-guidance/audit-traceability.md` (or comparable).
2. `audit-tests` reads the new fixture + grep assertions, verifies real assertions (no stub-only tests), reports test quality. Owner: agent.
3. `audit-pr` reconciles any blockers, creates the PR with the `build-prd` label and the canonical body, runs Step 4b lifecycle. Owner: agent.

The Acceptance Test (live-fire) closes the loop: the maintainer merges THIS PRD's PR via `/kiln:kiln-merge-pr <its-pr>` and observes `step4b-auto-flip: ... items=3 patched=3` against the three derived_from items. SC-001 + SC-007 are validated in one shot.

## Open Items

- **OQ-2 propagation**: if FR-016's added error text exceeds any consumer's truncation budget, condense to a one-line `see plugin-wheel/README.md §Writing agent instructions` pointer. Decision deferred to impl-docs at edit time; revert by inspection during audit-traceability.
- **plugin.json registration**: RESOLVED by team-lead correction — kiln uses filesystem auto-discovery; manifest is NOT edited. Removed from impl-roadmap-and-merge's worklist.
- **SC-002 fixture date-stability**: golden post-snapshot files embed a literal `<TODAY>` placeholder for the `shipped_date:` field; the fixture's `run.sh` substitutes it at test time via `date -u +%Y-%m-%d` before the byte-for-byte diff. Preserves NFR-002 zero-behavior-change while keeping the fixture stable across days.
- **R-3 (FR-006 git-state preflight)**: skill exits non-zero on dirty working tree. PRD §"Risks & Open Questions" closes this with "NO `--stash-and-restore` for V1 — surface the WIP, exit, let the user handle it." Implementer follows the spec; no follow-on work in this PRD.
