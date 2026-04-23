# Friction notes — impl-claude-audit (Task #2)

**Agent**: impl-claude-audit
**Branch**: build/kiln-self-maintenance-20260423
**Date**: 2026-04-23
**Scope delivered**: T001..T012, T018..T020 (Phases R, S, T, V). 15 tasks.

## What went well

- The specifier's contract file (`contracts/interfaces.md`) was exhaustive enough that I didn't have to ask a single question to start. Every rule's schema, every output file shape, every override-parse rule was already locked. This is the pattern I want every pipeline to have.
- The "audit proposes, never applies" separation (FR-004) kept the skill body simple. The skill is a pure markdown instruction set with no `Edit`/`Write` calls against CLAUDE.md — the only place edits happen is Phase V, explicitly under maintainer review. This removed a whole class of "what if the auto-apply gets it wrong" failure modes.
- Phase R rubric + Phase T scaffold in parallel dependency graph means I could mentally sketch the scaffold rewrite while the rubric was still drying. Made Phase T a 10-minute task instead of 30.

## Friction points encountered

1. **The 60-day default for `migration_notice_max_age_days` was too loose** — the in-repo migration notice was only 23 days old and would not have fired, failing SC-002's (a) category. The task description explicitly authorized "fix the rubric before marking Phase V complete" for rubric-coverage gaps, so this was smooth to resolve, but the initial choice came from PRD phrasing ("the rename is months old") that was factually inaccurate. Lesson for the specifier in the next pipeline: grep git history before locking freshness thresholds.

2. **Recent Changes had only 2 bullets at audit time** — below the threshold of 5. SC-002's category (b) couldn't be demonstrated on this pass. It's a "latent" verification (the rule is correctly configured; it just has nothing to catch). I documented this in phase-v-first-pass.md and verified the rule logic by tracing it against a hypothetical >5-bullet input. Mildly annoying that I couldn't produce a concrete example in the audit log, but not a blocker.

3. **Skill-as-markdown makes "run the skill twice" hard to prove** for idempotence (NFR-002). There's no shell harness — the skill is Claude instructions. I verified idempotence via static trace of Step 4 (deterministic ordering rules locked in the skill body) rather than by executing. The plugin needs an executable test harness eventually; until then, this pattern is "best we can do" and was flagged in phase-s-idempotency.md. Candidate backlog item: a `/kiln:kiln-test-skill` scaffold that replays a skill against a fixture.

4. **Version bump hook collided with my commit** — the `version-increment.sh` hook staged `VERSION` and all plugin `package.json` / `.claude-plugin/plugin.json` files after every edit. I had to explicitly include them in each phase commit to avoid orphan changes. Not a bug, but worth noting: when you see unexpected `M VERSION` etc. in `git status`, it's the hook doing its job. First-time agents might find this confusing.

5. **`Edit` matched-string drift after sequential edits** — after I removed the Migration Notice block, a subsequent `Edit` that included overlapping context failed because line numbers shifted. Had to `Read` again to get fresh context. Not a tool bug (it's the intended guardrail), but worth flagging as "sequential Edits in a single file need fresh reads between them."

## Handoff to auditor / retrospective

- All 15 assigned tasks marked `[X]` in tasks.md. Phase ordering respected (R before S before V; T parallel with S).
- Four commits in phase order: Phase R, Phase S, Phase T, Phase V. Each checkpoint per tasks.md.
- Baseline audit log at `.kiln/logs/claude-md-audit-2026-04-23-141531.md` — kept per task T020.
- Rubric threshold tweak documented with rationale in phase-v-first-pass.md (60 → 14 days for migration notice).
- One deferred signal (Mandatory Workflow duplication) left in the audit log — partial restatement is a tolerated false-positive shape per the rubric prose. Maintainer judgement call for a later pass.

## Suggestions for future "self-maintenance" passes

- After a couple more `/kiln:kiln-claude-audit` runs against real projects, consider whether `stale-section` (editorial) generates enough value to justify its LLM cost. Current pass returned 0 findings — might be over-rubricked.
- The rubric's `cached: false` reserved field should become `true` once content-hash caching lands. Track that as an enhancement.
- The `load-bearing-section` rule's false-positive filter (skip filename-glob hits like `*CLAUDE.md|*README.md`) is currently expressed as prose in the rubric. Consider promoting it to a structured filter list in the rubric YAML-ish block so implementations don't have to re-derive it.
