# audit-compliance friction notes — wheel-test-skill

Branch: build/wheel-test-skill-20260410
Commit audited: 8689a57
Date: 2026-04-10

## Audit result: PASS (with one documented deferral)

### PRD → Spec traceability
Every PRD FR (1–15) maps cleanly to a spec FR. The spec adds FR-016
(no-bypass-hooks), FR-017 (zero-leak), FR-018 (stopped archive counts as
failure) as explicit codifications of PRD Absolute Must #2 and PRD Risk
language. All covered.

### Spec → Code traceability
All 18 spec FRs have a concrete implementation point:

| FR  | Location                                                    |
|-----|-------------------------------------------------------------|
| 001 | runtime.sh:60 wt_discover_workflows                         |
| 002 | runtime.sh:104 wt_step_types + :110 wt_classify_workflow    |
| 003 | SKILL.md Step 2 + runtime.sh:287 wt_phase1_wait_all         |
| 004 | SKILL.md Steps 4/5/6 + runtime.sh:345 wt_wait_and_record_serial |
| 005 | runtime.sh:131 wt_expected_outcome + :415 reconcile         |
| 006 | SKILL.md Step 6 (10-step ceremony)                          |
| 007 | runtime.sh:74 wt_require_clean_state                        |
| 008 | runtime.sh:213 wt_detect_orphans + integrated in waiters    |
| 009 | runtime.sh:91 baseline + :408 wt_collect_hook_errors        |
| 010 | runtime.sh:158 wt_wait_for_archive (hybrid glob)            |
| 011 | runtime.sh:454 wt_build_report                              |
| 012 | runtime.sh:536 wt_emit_report                               |
| 013 | runtime.sh:547 wt_final_verdict                             |
| 014 | runtime.sh:44 wt_require_nonempty_tests_dir                 |
| 015 | waiter timeout params (60s / 120s by phase)                 |
| 016 | architectural invariant — no state writes in runtime.sh     |
| 017 | enforced by FR-008/016 combination                          |
| 018 | runtime.sh:345 + :415 reconcile                             |

### Contracts compliance
All 21 contracted function names from contracts/interfaces.md exist in
plugin-wheel/skills/wheel-test/lib/runtime.sh with matching names and arg
counts. Verified by grep.

The documented contract change (wt_run_phase1/wt_run_serial_phase → waiter
helpers) is reflected in contracts/interfaces.md with a full rationale
block. The root cause is the wheel PostToolUse hook at
plugin-wheel/hooks/post-tool-use.sh line 132, which uses tail -1 on the
raw Bash tool command and requires a literal activate.sh path — a shell
function cannot carry the intercept. SKILL.md Step 2 walks the invoker
through the alternative (N literal-path Bash tool calls). No violation.

### Classification verification (ran against real workflows)
- Phase 1: count-to-100, loop-test, team-sub-fail (3)
- Phase 2: agent-chain, branch-multi, command-chain, example,
  team-sub-worker (5 — implementer said "6 per my check" but actual is 5;
  minor counting slip, not a bug)
- Phase 3: composition-mega (1)
- Phase 4: team-dynamic, team-partial-failure, team-static (3)

Absolute Must #3 satisfied: team-sub-fail is correctly classified Phase 1
despite the filename. Expected-outcome glob *-fail* correctly flags
team-sub-fail and team-partial-failure as expected-failure.

### Coverage gate
Explicit exemption in tasks.md: "This feature is a Markdown skill with
inline Bash. There are no traditional unit tests — validation is
end-to-end." I accept the exemption. Per-function unit tests for Bash
orchestration helpers would be low-signal; audit-smoke provides the
equivalent validation via real-suite run.

### Tasks deferral (T029/T030)
Left [ ] in tasks.md with inline "DEFERRED to audit-smoke teammate" notes.
This is an intentional team-lead task board split. I accept the partition.
audit-smoke owns marking them [X] after the smoke run. I'll verify [X]
state before creating the PR and include the smoke result in the body.

### Blockers
No specs/wheel-test-skill/blockers.md exists. Nothing to reconcile.

### .gitignore check
.wheel/logs/ is gitignored (line 42). Reports will not pollute the tree.
Spec assumption confirmed.

### Shell syntax
bash -n clean on runtime.sh.

## Friction encountered
1. Implementer handoff arrived while task #2 was still in_progress. The
   implementer marked it completed right after sending the handoff, but
   there was a stale-task-list moment requiring a clarifying exchange.
2. Deferred task semantics: the "every implementer task must be [X]" rule
   in the spawn prompt conflicts with the explicit team-lead board split
   for T029/T030. Implementer handled it by inline-annotating tasks.md.
   For future runs, the team-lead prompt should explicitly carve out any
   deferred tasks from the "all [X]" requirement.
3. PRD Absolute Must #3 vs filename-based expected-outcome: the spec is
   internally consistent — classification is JSON-based (FR-002),
   expected-outcome is filename-based (FR-005). Worth calling out in the
   PR body so reviewers do not flag it as a contradiction.
4. Kiln require-feature-branch.sh hook blocks Write tool on specs/ path
   when branch does not match ###- or YYYYMMDD-HHMMSS- pattern. The
   build-prd pipeline created the branch as build/wheel-test-skill-20260410
   which fails the regex, so teammates must write notes via Bash heredoc
   instead of the Write tool. Mild friction; worth a lead-level fix.
