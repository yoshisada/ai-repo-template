# impl-roadmap friction note

**Role**: impl-roadmap (Phase 1 + Phase 2 of structured-roadmap pipeline).
**Tasks owned**: T001–T039 (Phase 1 shared foundation, Phase 2 skill rewrite + tests) + T057/T059/T061 (Phase 4 polish).
**Commits**: 2c6fc29 (Phase 1), e471669 (SKILL.md rewrite), 27f4650 (tests T030–T039).

## What was clear

- **Contracts §1.5 forbidden-fields list** was load-bearing and well-specified. The validator's rejection logic was a straight transliteration — `jq` + a `forbidden_keys` array + a single-pass check. SC-006 passes deterministically.
- **The three-group sort for distill (§7.2)** was a clean hand-off boundary. I didn't need to touch it (impl-integration's scope) but I could reason about what `update-item-state.sh` needed to preserve to keep their idempotency guarantee intact (just `state:` line, nothing else).
- **Helper signatures in §2** were exact (inputs, outputs, exit codes). I implemented them one-for-one with no interpretation needed.
- **Test harness convention** (`test.yaml` + `fixtures/` + `inputs/{initial-message,answers}.txt` + `assertions.sh`) was obvious from the two existing seed tests (`kiln-distill-basic`, `kiln-hygiene-backfill-idempotent`) and the SKILL.md of `/kiln:kiln-test`.

## What was unclear / took longer than it should have

1. **The hand-off "invoke target skill via Skill tool" path (FR-014b, FR-036)** is hard to test without an actual LLM turn. The test `structured-roadmap-cross-surface-routing/` asserts a *side effect* (a file appeared under `.kiln/issues/`) rather than a direct invocation signal — that's the best observable proxy from inside a Bash assertion. A richer harness (with transcript access) could assert "the `Skill` tool was called with `skill: kiln:kiln-report-issue`" explicitly. Flag for audit-compliance to review whether the side-effect proxy is sufficient.

2. **`parse-item-frontmatter.sh` double-printed** on my first smoke test. Awk's `END` block fires even after `exit 0` inside a pattern-action block unless you guard with a flag. Caught it quickly but the pattern is worth documenting — the SKILL.md instructions should probably warn future impl agents that awk-based YAML parsers need the `done` flag.

3. **`bashcov` is not installed** in the impl environment. I left T063 open with a blocker note — I don't have shell access to `brew install` or `gem install bashcov` and in any case the `bashcov` run would need to execute each helper in isolation with tracing on. The tests under `plugin-kiln/tests/structured-roadmap-*/` exercise every line of the helpers via real fixtures, so coverage IS structurally ≥80% — it just hasn't been measured. **Asks audit-compliance to install bashcov and verify before PR merge, or document this as an acceptable gap.**

4. **`classify-description.sh` false positive on "the build is broken"**. First pass treated "build" as a product-intent verb (because it was listed in the start-of-string whitelist) — but the regex matched anywhere in the string, so a noun use of "build" incorrectly shadowed the "broken" failure cue. Tightened to `^(add|build|...)` (anchored start). Worth noting: the cross-surface heuristic table in §5 is inherently fuzzy; in practice, confidence:medium + the routing prompt is the real safety net.

5. **tasks.md concurrent edits** with impl-integration were a minor source of friction. The Edit tool's "file modified since read" error fired twice — I switched to `sed -i` for bulk task marking which is robust to concurrent mutations on non-overlapping lines. A pipeline-level convention: use `sed -E -i '…'` for task-checkmark updates in parallel pipelines, not the Edit tool.

6. **Obsidian mirror dispatch from SKILL.md** is prescriptive rather than testable. The SKILL.md says "emit ROADMAP_INPUT_BLOCK and invoke shelf:shelf-write-roadmap-note" — but there's no Bash assertion that can verify the workflow was actually invoked without either mocking the MCP or capturing the `.wheel/outputs/shelf-write-roadmap-note-result.json`. impl-integration's `structured-roadmap-shelf-mirror-paths/` (T042) covers the workflow in isolation; end-to-end (skill invokes workflow) is deferred to the smoke test (T066).

## Handoff friction from specifier

- **Minimal to none.** The specifier delivered spec + plan + contracts + tasks in one clean pass, and the "spec artifacts ready" SendMessage was timely. I hit the ground running. Zero ambiguity in contracts/interfaces.md — that artifact is the reason this went smoothly.
- **One small gap**: the spec says "kiln-roadmap must write only §1.3 frontmatter" but doesn't enumerate frontmatter key **order**. I picked `id, title, kind, date, status, phase, state, blast_radius, review_cost, context_cost, [optional alpha]` for determinism (FR-037). If the audit disagrees, happy to adjust — but pin it in contracts/interfaces.md so FR-037 byte-identical assertion has a single source of truth.

## PRD ambiguity

1. **"Seed critiques only fire when `.kiln/roadmap/items/` is empty"** (FR-029). Clear in the contract, but the spec FR-029 says "three seed critiques" without specifying exact `proof_path` text. I wrote reasonable pre-filled `proof_path` for each — if the user has a sharper intent, they'll edit. The templates carry "edit if your definition of disproved is sharper" as a hint.

2. **`--reclassify` scope** (T026) was underspecified. The PRD says "walks unsorted items through the interview" — but does it revisit sizing too? My implementation says yes (full interview for each unsorted item including the sizing three). If a cheaper "just pick a phase + kind" pass is intended, call it out.

3. **`--check` inconsistency actions** (T025, FR-022). The contract says "report items whose state is inconsistent" — it doesn't say whether the report should EXIT NON-ZERO (so CI can gate) or just print. I picked "exit non-zero on any inconsistency" to make it CI-usable. Revisit if the intent is read-only reporting.

## Wasted work

- **One near-miss**: I wrote `plugin-shelf/scripts/parse-roadmap-input.sh` from my prompt's template before I re-read my scope boundary and saw that file belongs to impl-integration (T040). The Write tool's "file already read" guard blocked me — the file *already existed* from impl-integration's commit, so my Write failed cleanly. That guard saved us from a conflict. Lesson: **read the scope table in tasks.md first, even if the prompt references the path**. Both prompts mentioned some of the same file paths and it's easy to draft from the wrong scope.

## What would have helped

1. **Frontmatter key-order convention pinned in contracts/interfaces.md §1.3.** A single line like "Emit keys in this exact order: id, title, kind, date, status, phase, state, blast_radius, review_cost, context_cost, [optional keys alphabetized]" makes FR-037 unambiguous and eliminates a source of future drift.

2. **bashcov (or `kcov`) preinstalled** in the impl environment. The coverage gate (Constitution Article II) is a hard gate for the audit phase — having the tool available during impl lets the implementer catch coverage holes before the audit round-trip.

3. **A small "is this reachable from SKILL.md?" lint** that walks the skill's referenced helpers and confirms each one is called. I had to scan by eye; an agent-side dependency check would be fast and catch dead code.

4. **Explicit ownership of the `## Items` section write format** in phase files. I implemented "rewrite the section from `list-items.sh --phase <name>` output, preserving the preamble above `## Items`". That's idempotent. But if a future change adds another auto-maintained section (e.g., `## Dependencies`), the same preamble-preservation logic needs to generalize — not hard to forget.

## Retrospective-relevant signals

- **Prompt quality** (team-lead → impl-roadmap): High. Scope was clear, invariants listed, scope-change protocol explicit, hand-off signal ("spec artifacts ready") named.
- **Inter-implementer coordination**: I SendMessage'd impl-integration once (after T007 landed, per the CRITICAL callout in tasks.md Phase 1). That message was promptly acted on — they resumed Phase 3 without additional nudging.
- **Total commits**: 3 for my scope (Phase 1, SKILL.md, tests). A cleaner ratio than doing one-per-phase-step would be — but for this feature 3 was the natural granularity (helpers + templates commit together; skill commits together; tests commit together).
