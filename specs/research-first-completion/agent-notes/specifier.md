# Specifier Notes — research-first-completion

**Branch**: `build/research-first-completion-20260425`
**Date**: 2026-04-25
**Specifier**: pipeline specifier

## Decisions on PRD ambiguities

The PRD body left five Open Questions. Resolved as follows in spec.md §"Resolution of PRD Open Questions":

1. **OQ-1 (Distill conflict prompt cap at N sources?)** — Resolved NO cap in v1. Conflicts grouped by metric, one block per metric, all `(source, direction)` pairs visible. NFR-004 verbatim contract preserved. Encoded in FR-006 / NFR-004 / contracts §6.
2. **OQ-2 (Classifier high-signal-only config flag?)** — Resolved NOT in v1. The PRD's `.kiln/classifier-config.yaml::research_inference: high-signal-only` flag is deferred. Ship the broad signal set; revisit after first 10 real captures. NFR-006 covers the only currently-blocking concern (false-positive recovery is structural absence).
3. **OQ-3 (Classifier learns from rejected proposals?)** — Deferred to post-phase. Signal-word matching is stateless by design.
4. **OQ-4 (`fixture_corpus_path:` absolute vs repo-relative?)** — Resolved repo-relative only. Encoded explicitly in FR-003 with `Bail out! fixture-corpus-path-must-be-relative: <path>` enforcement. Validator-level loud-failure.
5. **OQ-5 (Auto-emit GitHub issue on gate-fail?)** — Deferred to post-phase. V1 surfaces per-axis report on stdout + halted PR creation.

I added two NEW open questions during clarification (deferred to first-real-use):

- **OQ-6** — should the build-prd Phase 2.5 stanza emit a "research-first-skipped" log line on the skip path? Resolved NO in v1 to preserve NFR-002 byte-identity. Re-open if maintainers want skip-path observability.
- **OQ-7** — does the classifier propose research for `kiln-fix` invocations? Resolved NO in v1; classifier extension is scoped to capture surfaces only.

Nine clarification Q&A pairs are recorded in spec.md §"Clarifications" Session 2026-04-25. The most consequential:

- **Where exactly does build-prd READ `needs_research`?** — At the SKILL.md instruction level (NOT at the workflow JSON dispatch level). The skill calls `parse-prd-frontmatter.sh` (extended in this PR with `needs_research` projection), branches on the projected value, and dispatches the variant pipeline inline. NO new wheel workflow JSON. (Drives Decision 2 in plan.md.)
- **How does build-prd "auto-route" — different pipeline or branch within the existing one?** — Branches within the existing pipeline. After `/tasks`, the SKILL.md inserts a new "Phase 2.5: research-first variant" stanza that runs ONLY when `needs_research: true`. Skip path is structurally a no-op (NFR-002 byte-identity). (Drives Decision 7 in plan.md.)
- **Distill propagation: emit or copy the research block?** — COPY verbatim. PRD frontmatter contains the post-union-merge / post-conflict-resolution research-block keys character-for-character matching the source declarations. (Drives §5 jq expression as the single source of truth for axis ordering.)
- **E2E regression scenario: separate fixture or flag?** — Separate sub-paths within ONE `run.sh` invocation. `--scenario=happy` and `--scenario=regression` flags; default invocation runs both sequentially with temp-dir reset. (Drives Decision 10 + §9 CLI surface.)

## Step 1.5 baseline rationale (BASELINE CHECKPOINT SKIPPED)

Per the team-lead's launch directive: "The PRD's NFR-002 / NFR-003 / NFR-005 are byte-identity assertions, not numeric perf budgets. They assert that the implementation MUST produce byte-identical output to pre-research-first behavior on the no-research-block path. No baseline-measurement is needed — the existing distill output IS the baseline by construction. Document this in your friction note ('baseline-checkpoint skipped: byte-identity NFRs do not require numeric baseline; reference is current pre-PR distill output')."

**Documented per directive**: baseline-checkpoint skipped: byte-identity NFRs do not require numeric baseline; reference is current pre-PR distill output.

I verified the directive against the PRD body before skipping — every NFR (NFR-001 through NFR-006) is a byte-identity or structural assertion. NO PRD requirement implies a latency target. The implementation hints in the PRD body do not introduce numeric perf budgets either (they describe behavior shape, not timing).

If a baseline measurement HAD been needed, I would have run a probe similar to the plan-time-agents `research.md §baseline` (probe ladder: in-process scan, shell grep, python3 cold-start, jq cold-start) and reconciled the NFRs against the live measurement. None of that was warranted here.

## Single-implementer rationale (Decision 1 in plan.md)

Per the team-lead's launch directive, Task #2 has ONE implementer. The four themes share several edit points:

- **Schema validators (Theme 1)** are used by Themes 2, 3, 4. Splitting Theme 1 across two implementers risks file conflicts on `validate-item-frontmatter.sh` and the shared helper at `plugin-kiln/scripts/research/validate-research-block.sh`.
- **PRD parser extension** is shared between Theme 2 (distill writes the PRD) and Theme 3 (build-prd reads the PRD). Splitting risks merge conflicts on `parse-prd-frontmatter.sh`.
- **SKILL.md files** (Themes 2, 3) live in the same plugin tree (`plugin-kiln/skills/{kiln-distill,kiln-build-prd,kiln-roadmap,kiln-report-issue,kiln-feedback}/SKILL.md`). Concurrent edits across two implementers risk merge conflicts on every file.

Sequential single-implementer execution avoids these structural conflicts by construction. Phases A → B/C → D are the dependency-respecting order:

- Phase A (schema validators) is foundation for B, C, D.
- Phase B (distill propagation + build-prd routing) and Phase C (classifier inference + coached-capture) share NO file edit points and can interleave; tasks.md sequences them after A but allows B/C interleaving in practice. The single-implementer constraint means there's no actual parallelism, but the dependency graph allows reordering within the implementer's preference.
- Phase D (E2E fixture) depends on A+B+C.
- Phase E (friction notes + smoke pass) depends on D.

## Handoff notes for implementer

### Critical paths to read first

1. **CLAUDE.md "Architectural Rules — Agent Spawning + Prompt Composition"** — Rules 1, 2, 3, 4, 5, 6 apply. This PR does NOT spawn new agents in production code (the variant pipeline reuses `/implement` agent flow), but Rule 6 (SendMessage relay) applies to the team-mode coordination.
2. **`specs/research-first-foundation/contracts/interfaces.md`** + `specs/research-first-axis-enrichment/contracts/interfaces.md` + `specs/research-first-plan-time-agents/contracts/interfaces.md` — these three contracts are the foundation. Read §3 of axis-enrichment carefully (this PR extends `parse-prd-frontmatter.sh` additively per FR-004 / contracts §3 of THIS PR).
3. **`coach-driven-capture-ergonomics`** FR-004 §5.0 + §5.0a — the coached-capture template + response parser. Phase C's interview hooks consume this UNCHANGED. Do NOT add a new template; do NOT fork the parser.
4. **`workflow-governance`** — the un-promoted gate at `/kiln:kiln-distill` Step 0.5 is OUT OF SCOPE for this PR. Do NOT alter it.

### Files NOT to touch

Per spec NFR-009 / plan §"Foundation invariants preserved":

- `plugin-wheel/scripts/harness/research-runner.sh`
- `plugin-wheel/scripts/harness/parse-token-usage.sh`
- `plugin-wheel/scripts/harness/render-research-report.sh`
- `plugin-wheel/scripts/harness/evaluate-direction.sh`
- `plugin-wheel/scripts/harness/evaluate-output-quality.sh`
- `plugin-wheel/scripts/harness/compute-cost-usd.sh`
- `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh`
- `plugin-kiln/lib/research-rigor.json`
- `plugin-kiln/lib/pricing.json`
- `plugin-kiln/agents/fixture-synthesizer.md`
- `plugin-kiln/agents/output-quality-judge.md`
- All foundation `wheel-test-runner.sh` + 12 sibling helpers.

The ONE shared file extended additively in `plugin-wheel/` is `parse-prd-frontmatter.sh` — three more field projections, NO shape change to existing projections, NO new exit codes for pre-research-first PRDs. Verify with the existing `plugin-kiln/tests/back-compat-no-requires/` and similar fixtures post-extension.

### Decision 3 follow-up (issue + feedback validators)

T003 in tasks.md commits to discovering whether `.kiln/issues/*.md` and `.kiln/feedback/*.md` have existing write-time validators. Search via `find plugin-kiln/scripts -name "*validate*" -o -name "*frontmatter*"` early in Phase A. Three outcomes:

- (a) Validators exist → extend each to call the shared helper from T001.
- (b) No validators → create ONE new validator at `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` that handles both surfaces.
- (c) Creating brand-new validators is judged out-of-scope (e.g., capture surfaces don't have a write-time hook) → document gap in `specs/research-first-completion/blockers.md` AND ship the shared helper for use by item + PRD validators only.

PREFER (a) → (b) → (c) in that order. Document the choice in plan.md Decision 6 follow-up notes (or in a new entry in plan.md if Decision 6 is silent on this) AND in T003's commit message.

### Decision 4 follow-up (worktree mechanism)

`git worktree add` is the preferred isolation mechanism. If it fails (e.g., locked working tree, filesystem quirk), the variant pipeline bails LOUD with `Bail out! research-first-worktree-failed: <error>`. NO silent fallback to `cp -R`. NFR-007 loud-failure invariant.

If during Phase B implementation you discover `git worktree add` is incompatible with the test harness (e.g., the E2E fixture's `mktemp -d` test repo isn't a git repo), use `cp -R` for the E2E fixture's mock variant pipeline ONLY — the production SKILL.md uses git worktree. Document the divergence in blockers.md.

### E2E fixture is load-bearing for phase-complete declaration

T017 (E2E fixture) is the load-bearing assertion for SC-005 and the phase-complete declaration. Both happy AND regression sub-paths must pass. The regression case is the proof that the gate actually catches regressions; the happy case alone proves only the no-op path. If the regression sub-path is silently dropped or skipped, the phase has NOT closed.

Mock the LLM-spawning steps via shell scripts that write predetermined outputs. The gate's deterministic logic is what's tested, not LLM behavior. NFR-008 forbids live `claude` CLI calls; CLAUDE.md Rule 5 forbids live agent spawn for newly-shipped agents (and this PR's variant pipeline IS newly-shipped).

### PI-2 from issue #181 (smoke-pass before final commit)

Per the team-lead's launch directive, T025 in tasks.md requires running `bash plugin-kiln/tests/research-first-e2e/run.sh` standalone before final commit. Capture stdout to `specs/research-first-completion/agent-notes/e2e-smoke-output.txt` for auditor evidence.

### Backward compatibility smoke check

Before committing Phase A, run the existing test fixtures that exercise the validators:

```bash
for f in plugin-kiln/tests/back-compat-no-requires \
         plugin-kiln/tests/distill-gate-grandfathered-prd \
         plugin-kiln/tests/distill-gate-accepts-promoted; do
  bash "$f/run.sh"
done
```

ALL must pass. If any regress, the additive extension to `validate-item-frontmatter.sh` or `parse-prd-frontmatter.sh` has broken backward compat — fix before commit.

### Schema-drift mitigation

Spec R-004 documents the schema-drift risk across four intake surfaces. Decision 3 commits to a shared validation helper at `plugin-kiln/scripts/research/validate-research-block.sh` as the single source of truth. ALL FOUR validation surfaces (item, issue, feedback, PRD frontmatter) MUST call this helper. If you find yourself duplicating validation logic across two surfaces, STOP and refactor to call the helper.

### Suggested reading order for implementer

1. `CLAUDE.md` — full read, especially "Architectural Rules" section.
2. `specs/research-first-completion/spec.md` — full read.
3. `specs/research-first-completion/plan.md` — full read.
4. `specs/research-first-completion/contracts/interfaces.md` — full read; refer back during implementation.
5. `specs/research-first-completion/tasks.md` — full read; mark `[X]` task-by-task as you go.
6. `specs/research-first-axis-enrichment/contracts/interfaces.md §3` — `parse-prd-frontmatter.sh` existing contract.
7. `specs/research-first-plan-time-agents/contracts/interfaces.md` — `evaluate-output-quality.sh` contract you'll be wiring into the gate step.
8. `coach-driven-capture-ergonomics` FR-004 §5.0 + §5.0a — coached-capture interview pattern you'll hook into.

Begin with Phase A (T001..T005). Commit at each phase boundary. Run the smoke-pass at T025 before final commit.

Good luck.
