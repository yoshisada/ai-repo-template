# Friction Note — impl-schema-migration

**Track**: impl-schema-migration (TaskList #4)
**Branch**: `build/wheel-step-input-output-schema-20260425`
**Spec**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md) | **Tasks**: [tasks.md](../tasks.md)
**Author**: impl-schema-migration

## Status — Complete

All assigned tasks (T001/T002/T003 setup, T030–T034 Phase 2.B, T060–T068 Phase 4) marked [X] in tasks.md. Two commits land my scope: `e478971` (Phase 2.B — validator + docs) and the Phase 4 atomic-migration commit (kiln-report-issue.json + fixtures + CI guard). Phase 3 dispatch wiring (impl-resolver-hydration commit `87d780a`) and my Phase 4 commit together satisfy NFR-G-6 atomic-migration via the squash-merge target (per plan §3.E + the agreed Path B coordination).

## Verdict reports (NFR-G-1 substrate carveout)

**Substrate gap acknowledgment**: per impl-resolver-hydration's friction note + plan §2 carveout, pure-shell `run.sh`-style tests under `plugin-wheel/tests/<name>/` and the runtime-internal verification fixtures under `plugin-kiln/tests/<name>/` are **NOT** invocable via `/kiln:kiln-test` — that harness is plugin-skill-only (it spawns `claude --print --plugin-dir ...` and requires `inputs/initial-message.txt` + `assertions.sh`, not `run.sh`). The bash run.sh log is the contract-equivalent verdict report per the NFR-G-1 carveout. Same gap impl-resolver-hydration's grammar/allowlist/tripwire/perf fixtures hit.

| Fixture | Substrate | Verdict report path | Result |
|---|---|---|---|
| `plugin-wheel/tests/back-compat-no-inputs/` (T065 — NFR-G-3) | pure-shell run.sh | `.kiln/logs/wheel-test-back-compat-no-inputs-2026-04-25T07-56-56Z.log` | **9/9 PASS** |
| `plugin-kiln/tests/kiln-report-issue-inputs-resolved/` (T066 — FR-G4 / US1 / US5) | pure-shell run.sh (structural verification — see below) | `.kiln/logs/kiln-test-kiln-report-issue-inputs-resolved-2026-04-25T07-56-56Z.log` | **21/21 PASS** |

**T066 substrate decision**: my `kiln-report-issue-inputs-resolved` fixture is structurally a `run.sh` rather than a true `/kiln:kiln-test` plugin-skill substrate test (which would have to invoke `/wheel:wheel-run kiln-report-issue` end-to-end against real `gh` + Obsidian MCP — those have side effects and run-cost that don't fit fixture sandboxing). The run.sh exercises the hook-time hydration pipeline against a synthetic state (`write-issue-note` already done, `.shelf-config` seeded, registry seeded) and asserts the **structural migration outcome** — 5 inputs resolve, resolved-inputs block emits, `{{VAR}}` substitutes, zero residuals, zero in-step disk-fetches, version bump. The **live-smoke gate (NFR-G-4)** is the auditor's T081-T082 job (live `/kiln:kiln-report-issue` against post-PRD code) — that's where end-to-end is gated, not at this fixture.

## What was confusing

1. **`plugin-skill` substrate scope** (highest-friction item). The team-lead prompt + spec User Stories said "kiln-test fixture" without distinguishing the v1 plugin-skill substrate (real `claude --print` subprocess) from generic run.sh-style verification. impl-resolver-hydration hit this first and documented it; I inherited the carveout. Spec mentioned User Story 1 fixture as `/kiln:kiln-test plugin-kiln kiln-report-issue-inputs-resolved` — which is technically valid harness invocation syntax — but the actual harness rejects/skips run.sh-style fixtures (the substrate driver only reads `inputs/` + `assertions.sh`). Recommendation for `/kiln:kiln-test` follow-on: add a `pure-shell-runner` substrate that invokes a fixture's `run.sh` directly and ingests its `PASS:` / `FAIL:` lines into TAP. This would close the gap for runtime-internal tests (resolve_inputs, workflow_validate, hydration logic) that don't need an LLM in the loop.

2. **`set -u` in `workflow_validate_workflow_refs`'s sub-shell**. My first cut of the back-compat fixture sourced workflow.sh under `set -u` without exporting `WHEEL_LIB_DIR` first. Workflow.sh line 366's `bash -c "source '${WHEEL_LIB_DIR}/...'"` triggers an unbound-variable error under strict mode when the validator descends into sub-workflow refs (kiln-mistake.json has `shelf:shelf-propose-manifest-improvement`). Caught by my T6 corpus check; fixed by exporting WHEEL_LIB_DIR before sourcing. Suggestion: workflow.sh line 366 should use `${WHEEL_LIB_DIR:-$(self-discover)}` defensively (mirrors the engine.sh sourcing pattern at lines 31-35). I did NOT fix this in workflow.sh because the fix is out-of-scope for this PRD — flagging for follow-on.

3. **Sub-workflow filename aliasing was a real surprise**. The PRD/spec referenced "the upstream step's output" but didn't fully spell out that `type: workflow` steps write outputs under the **sub-workflow's name** (e.g., `shelf-write-issue-note-result.json`), not the wrapping wheel-step's id. researcher-baseline caught this in their §Job 2 inventory walk; impl-resolver-hydration handled it transparently in `_read_upstream_output`'s fallback path; I had to verify my T066 fixture's expectations matched. Suggestion: spec should call out the aliasing in the FR-G2-1 / FR-G4-1 contracts directly, not bury it in research.md §Methodology.

4. **The "5 disk fetches" PRD framing was pre-FR-E**. researcher-baseline already flagged this calibration issue. The PRD line 36 + SC-G-1 say "≥3 fewer Bash/Read tool calls" but the FR-E batched baseline is already at command_log=1. I migrated the spirit (zero in-step disk fetches) and the auditor will re-anchor SC-G-1 framing if needed. Not blocking — informational.

## Where I got stuck

- **None blocking**. Two minor issues caught by my own smoke tests (T1 footer-content assertion expected file content but only the file path appears; T6 `set -u` interaction with workflow.sh's sub-shell). Both fixed in <5 minutes by re-reading the actual function output / exporting WHEEL_LIB_DIR.
- **The /kiln:kiln-test substrate gap** could have blocked NFR-G-1 satisfaction had I not had impl-resolver-hydration's friction note as precedent. The carveout pattern (bash log == verdict report analog) needs to be codified somewhere more discoverable than the friction-note layer.

## Suggestions for `/kiln:kiln-build-prd` / specify / plan / tasks

1. **Codify the run.sh-vs-plugin-skill substrate distinction in `/specify` or `/plan`**. When a PRD's User Story includes "kiln-test fixture" wording, the planner should either (a) assert the substrate the fixture will use AND check it's available, OR (b) emit a tasks.md note when a runtime-internal test will need the substrate carveout. This would have surfaced the gap during planning rather than during implementation.

2. **Cross-track DEP markers in tasks.md worked beautifully.** The `[DEP impl-resolver-hydration T021]` annotation on T030 + `[DEP impl-resolver-hydration T054]` on T060 made the coordination ordering obvious without team-lead intervention. Recommend continuing this pattern.

3. **Atomic-commit Path B coordination (NFR-G-6) was clean** but required team-mate-mediated agreement on whether to interpret "atomic" as single-commit vs single-PR. Plan §3.E's CI guard wording (`git log -1 --name-only HEAD`) implied single-commit; auditor T084 wording (`git show <feature-branch> --name-only`) implied single-PR. The latter is the actual spec intent (squash-merge target). Recommend the spec template / NFR template default to single-PR phrasing for atomic-migration invariants — single-commit is over-strict given Constitution Article VIII's commit-per-phase rule.

4. **The 12-case smoke-test pattern I used for the validator was fast feedback** — synthesize one workflow JSON per validation rule, run workflow_load, assert the documented error string. This caught both my expected validations AND a backward-compat regression in <30 seconds before authoring the formal fixture. Recommend `/plan` template emit a "first-pass smoke test loop" guidance section for runtime-validator tasks.

5. **`workflow.sh` defensive sourcing** (point #2 above) is an out-of-scope fix that should land as a follow-up. Filing as a roadmap item once this PRD lands.

## Cross-references

- impl-resolver-hydration friction note: `specs/wheel-step-input-output-schema/agent-notes/impl-resolver-hydration.md` (substrate-gap pattern, jq-cold-start trap, JSONPath-vs-jq syntax rule).
- researcher-baseline friction note: `specs/wheel-step-input-output-schema/agent-notes/researcher-baseline.md` (baseline methodology + sub-workflow filename quirk).
- SC-G-1 calibration analysis: `specs/wheel-step-input-output-schema/research.md` §baseline.
- Path B coordination thread: SendMessage history between impl-schema-migration and impl-resolver-hydration (commits `e478971` Phase 2.B → `87d780a` Phase 3 → Phase 4 atomic).
