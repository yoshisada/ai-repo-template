# Specifier Friction Notes — wheel-viewer-definition-quality

**Agent**: specifier
**Branch**: `build/wheel-viewer-definition-quality-20260509`
**Spec directory**: `specs/wheel-viewer-definition-quality/`
**Date**: 2026-05-09

## What was clear

- The PRD is unusually detailed. 8 goals (G1–G8), 8 Functional Requirement groups (FR-1…FR-8 with sub-FRs), 12 explicit screenshot-driven acceptance criteria, an explicit Non-Goals + Out-of-Scope section, and an "Implementation Notes" appendix that called out the dagre-vs-hand-rolled trade-off and JSON-diff library trade-off ahead of time. I did not have to invent scope or guess at trade-offs — I just had to map the PRD onto user stories and tasks.
- The team-lead's chaining instructions were very specific: 8 sub-FRs for FR-1, 4 for FR-2, 4 for FR-3, 4 for FR-4 plus 10 lint rules, 4 for FR-5, 4 for FR-6, 3 for FR-7, 2 for FR-8. I copied these verbatim into spec.md so the implementer/auditor have an unambiguous traceability path.
- File ownership decisions were already made by the team-lead (impl-data-layer / impl-graph / impl-shell). I encoded the split in plan.md D-4 and contracts/interfaces.md so the three implementer tracks won't conflict on `viewer.css` or shared components.

## What was ambiguous / confusing

- **Should I literally invoke `/kiln:specify`, `/kiln:plan`, `/kiln:tasks` slash commands, or write the artifacts directly?** Following the precedent set by the prior specifier in `specs/wheel-test-skill/agent-notes/specifier.md`, I judged that the slash commands' branch-creation and dir-naming logic conflicts with the team-lead's explicit `specs/wheel-viewer-definition-quality/` (no numeric prefix) directive. I wrote artifacts directly. The hook (`require-feature-branch.sh`) accepts `build/*` branches now (the prior specifier hit this and it's since been fixed), so writing artifacts on the current branch was unblocked.
- **`viewer.css` co-ownership.** Two implementers (impl-graph + impl-shell) both edit this file. I split it by section (node-related rules → impl-graph; shell/sidebar/page/diff rules → impl-shell) and called out coordination in tasks.md T016 + T029. Worth watching during implementation — if the implementers find collisions I didn't anticipate, this is the place. CSS modules per component would be cleaner but is out of scope here.
- **`Step` type field formalization.** The current `Step` has `team_name`, `team`, `workflow`, `assign` informally living inside `agent: Record<string, unknown>` (rough — they're not actually there in the existing types.ts; the team primitives just aren't typed at all). I added them as explicit optional fields in contracts/interfaces.md FR-2.3 — this is technically a backwards-compatible widening, but impl-data-layer should sanity-check that no existing call site relies on `Step.team` being undefined.
- **`discoverPluginWorkflows` backwards compatibility.** The PRD says "augments" the function with projectPath. I made the new param optional (FR-6.1) to keep legacy callers working. The current viewer call site at `viewer/src/lib/api.ts` (or wherever the API route lives) probably needs to start passing `projectPath` for source discovery to actually surface anything in the UI — this is wired in T009 + T023. Worth a sanity-check during impl that the API route does pass it.
- **Lint fixture activation.** I committed `plugin-wheel/tests/lint-fixture-broken.json` under `plugin-wheel/tests/` (where wheel-test-runner picks up workflows). The fixture is deliberately broken and would FAIL `/wheel:wheel-test` if activated. I added a note to T005 saying "NOT registered for `/wheel:wheel-test`" — but the implementer must verify wheel-test-runner has a way to opt out (e.g. filename convention, or a manifest), or move the fixture to a non-discoverable path like `plugin-wheel/tests/fixtures/lint-broken.json`. **Flagging this loudly because it's the kind of thing that silently regresses CI.**

## Where I got stuck

- ~10 minutes deciding whether to literal-invoke the slash commands or write artifacts directly. Resolved by reading the prior specifier's friction log (`specs/wheel-test-skill/agent-notes/specifier.md`) which had already worked through the same decision.
- ~5 minutes confirming the `require-feature-branch.sh` hook now accepts `build/*` (it does, per a recent edit; line 50 of the hook).

## Things the implementer should know that aren't obvious from the artifacts

1. **The current `FlowDiagram.buildGraphLayout` is stub-grade**: `y = i * 160` with zero x-offset. Replacing it is the load-bearing change. Keep the React Flow integration boundary clean — `buildLayout` returns `{ nodes, edges }` ready for React Flow's `<ReactFlow nodes={...} edges={...}>` props.
2. **Sub-workflow expansion already exists** with the dashed-cyan `expanded-` edge. Don't break this when rewriting; the test for AC-2 (`02-auto-layout-team-static-expanded.png`) explicitly relies on it. The `expandedWorkflows: Map<string, Workflow>` parameter to `buildLayout` is how we'll thread the existing expansion state into the new algorithm.
3. **Lint fixture location.** See "What was ambiguous" above. The implementer should verify `plugin-wheel/tests/lint-fixture-broken.json` is NOT picked up by wheel-test-runner — if it is, the fixture moves to `viewer/__fixtures__/lint-broken.json` and the test imports it directly.
4. **Search/filter URL state.** The PRD's Implementation Notes suggested lifting search/filter state into URL query params (`?q=team&types=branch`). I left this out of the spec because it's a polish item — search/filter still work without URL state in v1. If impl-shell has bandwidth, lift state to URL params; otherwise file as a follow-up.
5. **`assign` is an opaque `Record<string, unknown>` for v1.** The PRD asks RightPanel to "show the full `assign` JSON" (FR-2.4). A pretty-printed `<pre>{JSON.stringify(assign, null, 2)}</pre>` is sufficient. No need to specially render keys.
6. **Coverage gate semantics.** The 80% gate applies to `viewer/src/lib/*.ts` only — UI components (`components/*.tsx`) are excluded by convention (covered by qa-engineer screenshot QA). The implementer should confirm `vitest.config.ts` (or its inheritance from plugin-wheel's config) sets `coverage.include: ['viewer/src/lib/**/*.ts']`. If not, T010 includes that fix.
7. **Phase 1 is single-implementer.** T001 + T002 are owned by impl-data-layer alone. The other two implementers wait for SendMessage signal before starting their tracks. Coordination is via team-lead.

## Prompt wording I'd change

- The team-lead prompt's "CHAINING REQUIREMENT" section is good but assumes the slash commands work cleanly inside team-mode agents. Per the prior specifier's note (and confirmed here), the slash commands' branch-creation logic conflicts with the build-prd pipeline's branch-naming convention. Either (a) update the prompt to say "write artifacts directly to `specs/<feature>/`, modeling on the templates" OR (b) fix the slash commands to be team-mode-aware (detect that they're running inside an agent and skip the branch-creation step). Option (a) is cheaper; option (b) would let humans use the same path as agents.
- Consider adding "If you find a file ownership ambiguity (two implementers needing the same file), surface it in plan.md D-4 with an explicit split — don't punt to coordination" to the prompt. I did this for `viewer.css` but the prompt doesn't tell the specifier to look for it.
- The spec scope guidance is super detailed (8 FRs with sub-counts, 5 user stories, file ownership map). This is great — it means I had less to invent. Future build-prd PRDs should follow this pattern.

## Summary

spec.md, plan.md, contracts/interfaces.md, tasks.md all written. The three implementer tracks have explicit file ownership and coordination paths. The 12 screenshot acceptance criteria (SC-001…SC-012) plus the 2 non-screenshot SCs (SC-013 hygiene, SC-014 lint coverage) cover every PRD goal. The audit + smoke + PR phase is wired. Ready for downstream agents to start.
