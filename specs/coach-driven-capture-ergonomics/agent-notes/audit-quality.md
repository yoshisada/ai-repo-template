---
agent: audit-quality
feature: coach-driven-capture-ergonomics
written_at: 2026-04-24
---

# Audit-Quality Friction Notes

## What went smoothly

- Spec + plan + tasks + contracts were clean and complete — every FR was anchored to a contract field or call-site pattern, so traceability was almost mechanical.
- Every new `.sh` file in `plugin-kiln/scripts/context/` and `plugin-kiln/scripts/distill/` carries an FR-reference comment at the top. I didn't have to guess what each script was implementing — the authorship discipline saved a full pass of "which FR does this file satisfy?" archaeology.
- Running the 7 standalone behavioural tests (`project-context-reader-*`, `distill-multi-theme-*`, `distill-single-theme-no-regression`, `roadmap-coached-interview-*`) all passed on first invocation. No red.
- The `distill-multi-theme-determinism` test was exactly what the team-lead asked me to verify (runs the helpers twice, diffs byte-for-byte). Found it by name; confirmed behaviourally in under a minute.

## What was confusing

### 1. PRD FR numbering vs. Spec FR numbering diverged silently

The PRD has FR-001..FR-017 + NFR-001..NFR-005. The spec expanded this to FR-001..FR-021 + NFR-001..NFR-006. The expansion is fine, but **neither the spec nor the task list has a PRD↔Spec FR mapping table**. I had to reconstruct it from scratch by reading both documents side-by-side.

**Proposed improvement**: when the spec renumbers FRs relative to the PRD, include a "PRD FR-N → Spec FR-M" crosswalk in the spec's "Derived From" or Clarifications section. Costs the specifier 30 seconds; saves the auditor 10 minutes.

### 2. Three different test conventions in one feature

I encountered three distinct test layouts in this one feature:

- `run.sh`-only (standalone bash tests, runnable via `bash plugin-kiln/tests/<name>/run.sh`)
- `run.sh` + `fixtures/` + `inputs/` (same as above but with fixture files)
- `test.yaml` + `assertions.sh` + `fixtures/` + `inputs/` (kiln-test harness-driven)

The `test.yaml` form requires the kiln-test harness to run; `run.sh` form does not. **The task list (tasks.md T001–T052) does not distinguish which convention each task should produce.** I had to open each directory to discover the convention.

**Proposed improvement**: make the task template explicit about convention. `[X] T018 [harness]` vs `[X] T018 [standalone]` would have saved a full inspection pass.

### 3. Phase 6 polish tasks left unmarked — no signal on whether they were skipped intentionally

T053–T057 are unmarked. There's no note in any friction file saying "deferred to follow-up PR." I had to decide whether the feature is "done" or "mostly done" without clear guidance.

**Proposed improvement**: if Phase 6 is deferred, mark it with a sentinel like `[~]` (deferred) so the auditor can distinguish "not done, blocking" from "not done, intentionally deferred."

### 4. Tripwire vs. behavioural test distinction was not surfaced up front

Team-lead flagged this proactively in my brief ("decide if those count toward coverage"). Without that flag I would have had to read each tripwire's inline comment to discover it wasn't behavioural. The implementers were scrupulous about naming this limitation in the test file itself — but the test discipline assumes the auditor will read every `run.sh` file.

**Proposed improvement**: a header metadata line in each test file — e.g. `# type: tripwire` or `# type: behavioural` — would make the grep-for-quality pass a one-liner.

### 5. The NFR-003 determinism ask was single-sentence but covered multiple files

Team-lead said: "Verify the NFR-003 byte-identical-determinism test actually runs the multi-theme emitter twice." Determinism is tested in **two** places: `project-context-reader-determinism/run.sh` (reader, NFR-002) and `distill-multi-theme-determinism/run.sh` (distill, NFR-003). I verified both but the brief was singular. For a more junior auditor, the mis-direction risk is real — they might verify only one and report "confirmed."

**Proposed improvement**: when the team-lead flags a specific test to verify, pass the **file path** in the brief, not just the NFR name. `plugin-kiln/tests/distill-multi-theme-determinism/run.sh` is unambiguous.

## What required multiple passes

Only one finding needed a re-read: **FR-002 malformed-YAML stderr-warning gap**. The contract says "log warning to stderr, skip that file, continue." I first saw `read-plugins.sh:38` has the warning, ticked FR-002 as ✅, then noticed the roadmap-item awk parser in `read-project-context.sh` has no equivalent warning. It silently tolerates (empty fields, no crash) but doesn't log. Noted as a −1 % deduction. Low severity — the "defensive" requirement is satisfied; the "observable" half is not.

## Net time in audit

~25 minutes across: gate check (1 min), spec + PRD + tasks read (5 min), new-script inspection (5 min), test-file inspection + run (8 min), compliance-report writing (6 min).

If the proposed improvements above were in place, this audit would be ~15 minutes — the heaviest cost right now is reconstructing the PRD↔Spec FR mapping from scratch and opening each test file to discover its convention.
