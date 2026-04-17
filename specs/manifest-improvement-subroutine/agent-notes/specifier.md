# Specifier Agent — Friction Notes

**Feature**: manifest-improvement-subroutine
**Date**: 2026-04-16
**Agent**: specifier (Opus 4.7)

## What went well

- The PRD was unusually well-structured — 16 FRs with explicit "Absolute Musts" and a Non-Goals section meant there was almost nothing to infer. The naming-authority rule was stated crisply.
- Existing workflow JSON for `shelf-full-sync` and `report-mistake-and-sync` made the caller-integration shape obvious — I could reuse the exact `type: "workflow"` pattern and not invent new plumbing.
- `contracts/interfaces.md` held up under the PRD's "silent-on-skip is non-negotiable" constraint. Writing the dispatch-envelope entity before the MCP agent step stopped me from hand-waving "the agent does it" — I had to specify the exact bash→agent handoff shape.
- The constitution's Principle VII (interface contracts before implementation) made me write signatures in `contracts/interfaces.md` early, which directly surfaced the "command step can't call MCP" reality — and forced R-001 (command→agent micro-pair) before I was deep in implementation.

## Friction with `/kiln:specify`

1. **Spec template's user-story priorities push toward P1/P2/P3 triage even when every core story is P1**. The template's default wording ("MVP = just US1") is misleading here — US1 (silent skip), US2 (write proposal), and US3 (scope clamp) are all equally load-bearing. I marked all three P1 in the spec but the template's downstream task template still formatted "User Story 1 MVP" with that singular tone. Suggestion: template should support "MVP = {US1, US2, US3}" multi-story MVPs with minor wording changes.
2. **The template's example FRs (`FR-020: rename/rebrand grep verification` and `FR-022: QA credentials flow`) are embedded as hints inside HTML comments** that leak into the author's mental model — they prompted me to consider whether this feature needs grep-verification (no) and QA creds (no). Suggestion: move these to a separate "common FR patterns" reference, not inline hints in the template.
3. **`/specify` validation checklist's "no implementation details" item conflicts with PRDs that NAME specific paths/tools**. The PRD explicitly names `plugin-shelf/workflows/propose-manifest-improvement.json`, `${WORKFLOW_PLUGIN_DIR}`, `mcp__claude_ai_obsidian-manifest__*` — these are contract/naming requirements, not implementation leakage. I had to mark the checklist item as passing with a Notes caveat. Suggestion: validation prompt should distinguish "contract-surface identifiers (paths, tool names, canonical IDs the PRD specifies)" from "implementation details (language choices, libraries, internal structure)".

## Friction with `/kiln:plan`

1. **Plan template's "Technical Context" section asks for Performance Goals / Scale / Storage / Testing** in a way that skews toward web-app / API domains. This feature is a ~150-LOC bash shell-out plus a JSON workflow file. Filling those fields forced me into "performance goals: <500ms skip path" language that is technically accurate but feels like ceremony. Suggestion: add a "wheel sub-workflow" project-type preset that collapses these fields into the ones that matter (portability, silence contract, MCP call count).
2. **The plan template's Source Code tree placeholder assumes a src/models/services layout**. I had to rewrite the entire tree to reflect `plugin-shelf/` + `plugin-kiln/` layout. Suggestion: detect from repo root (presence of `plugin-<name>/` folders) and pick a plugin-aware default.
3. **Constitution Check is presented as a table in the template but the template itself says "Gates determined based on constitution file"** — ambiguous whether I author the table or the template does. I wrote the table myself against the 8 principles. Suggestion: the template should include the 8-principle table pre-rendered with empty Status / Notes columns.

## Friction with `/kiln:tasks`

1. **Tasks template's "tests are OPTIONAL" note is at odds with Constitution II (80% coverage GATE)**. I kept tests in all cases because constitution overrides the template, but the template's framing pushed me to justify tests defensively. Suggestion: when the constitution mandates coverage, the tasks template should say "tests REQUIRED per constitution II" and not "optional".
2. **Task numbering runs a single sequence (T001, T002, ...) across all phases** which is fine, but dependency expressions like "depends on T004–T006" are hard to scan when phases are long. Minor suggestion: allow phase-prefixed IDs like `P2-T04` optionally, or add a visual dependency column.
3. **[P] marker semantics are "different file, no dependency"** — but I wanted to express "same-file serialization" (T013, T016, T017, T030 all edit the same agent instruction). The template has no non-parallel marker. I documented this in a "Within Each User Story" note but a first-class `[S]` (serialized-with) marker would be cleaner. Suggestion: add `[S:<taskID>]` to denote same-file serialization.

## Ambiguous in the PRD

- **FR-14 "same sync pass"** is literal for the two kiln callers (terminal == `shelf:shelf-full-sync`) but structurally impossible for `shelf-full-sync` itself (it would need to call `obsidian-apply` twice). I documented the asymmetry in research.md R-007 and accepted the one-run delay. If the PRD author intended strict same-run for all three, this needs revisiting — but I believe the intended spirit of the FR is "reachable to the maintainer quickly" and the two kiln callers already cover the hot path.
- **PRD FR-3 says "section" field** but neither the PRD nor any cited manifest file defines whether `section` is an H2 heading, an H3 heading, or a line-range. I specified in the data model as "H2/H3 heading text OR 'lines N-M'" — permissive union. Tighter spec could be valuable if maintainers have a preferred form.
- **PRD FR-10 slug derivation** says "stop-words removed" without specifying the vocabulary. I cribbed the set from `report-mistake-and-sync` (its Step 7) — ~20 common English stop-words. This is a reasonable default but an explicit list in the PRD would remove the copy-from-reference dependency.

## Suggestions to `/specify`, `/plan`, `/tasks` skills

1. **Add a "plugin sub-workflow" project type preset** across all three skills. This feature is the THIRD wheel sub-workflow in this repo (`shelf-full-sync`, `report-mistake-and-sync`, now `propose-manifest-improvement`) and each one has had to manually adapt the generic templates. The preset would pre-fill: bash + JSON + wheel + MCP tech context; plugin source tree; `${WORKFLOW_PLUGIN_DIR}` portability task; silent-on-skip contract boilerplate; command→agent micro-pair data-flow diagram.
2. **Auto-inject a "naming authority" checklist item in `/plan`** when the PRD's "Absolute Musts" or "Goals" sections name specific identifiers. Helps prevent subtle renames that break callers.
3. **`/tasks` should emit a portability audit task by default** when it detects a wheel workflow is being authored. Today I added T028 and T034 manually — both are rote checks that should be scaffolded.
4. **Add a "silent-contract" integration-test template** — `tests/integration/silent-skip.sh` has a shape (invoke → assert no file / no stdout / no stderr / exit 0) that recurs across features. A generator that takes the contract's silent-envelope name and emits this test would remove friction.

## Net assessment

Overall the three skills are in good shape. The friction is concentrated at the plugin-sub-workflow project type — the templates are adequate but not optimized for it. Nothing blocked progress; everything above is "could be 20% faster / less rote" rather than "broken".
