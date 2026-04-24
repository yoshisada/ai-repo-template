# impl-vision-audit — Friction Notes

**Agent**: impl-vision-audit
**Pipeline**: kiln-coach-driven-capture
**Branch**: build/coach-driven-capture-ergonomics-20260424
**Scope**: FR-008 through FR-016 (vision self-explore + CLAUDE.md audit)

## What went well

- **Contract-first parallelism worked**. `specs/coach-driven-capture-ergonomics/contracts/interfaces.md` had the exact `jq` queries I needed under "Call Sites" — I could copy-paste them into `SKILL.md` with minor shaping. No ambiguity, no round-trip with impl-context-roadmap required.
- **WebFetch gave a clean verbatim excerpt of the Anthropic best-practices section** on the first try. The cached rubric at `plugin-kiln/rubrics/claude-md-best-practices.md` is grounded in the real doc, not a paraphrase.
- **Specifier's unblock message called out all four clarifications up front** (cache TTL 30 days, per-section diff grouping, partial-snapshot no-banner, FR-007 tone scoped to impl-context-roadmap). I didn't have to re-read the full spec to disambiguate.

## Friction + where the pipeline could improve

1. **Graceful fallback vs TDD tension**. Per Constitution Article I, tests should fail before implementation. But my SKILL.md defensively falls back to an empty snapshot JSON when the reader isn't installed — which means a test run against a pre-Phase-1 consumer repo would silently succeed with "blank-slate fallback" rather than fail. I kept the fallback because NFR-004 requires it for offline consumers, but the tension should be documented: **parallel-branch TDD with defensive fallbacks means tests must assert the positive path, not the absence of the feature.** My assertions do this (they grep for the banner text, the evidence citation, etc.) — but a future implementer might accidentally write a "file exists" test that passes under the fallback path.

2. **No easy way to actually run my fixtures during authoring**. The kiln-test harness spawns `claude --print` subprocesses; I can't dry-run them from within this agent. The fixtures are therefore "author against the contract, trust the integration test harness to run them downstream" — which means any shape regression between the contract's `jq` queries and the actual Phase 1 reader output won't surface until T057 runs the full suite. Consider a lighter "assertion-shape sanity check" that just validates the fixture directories have the right file layout (test.yaml + inputs/ + assertions.sh + fixtures/) without actually invoking the skill.

3. **Fixture for network-fallback test is inherently racy**. T031 assumes WebFetch will fail — but in a clean network environment, WebFetch succeeds and the "cache used, network unreachable" note never appears. I worked around this with a secondary-signal assertion (if the preview references the cached rubric path, PASS), but the cleanest fix would be a harness env var like `KILN_TEST_FORCE_WEBFETCH_FAIL=1` that the skill body checks. That'd be an ergonomic upgrade for the kiln-test harness substrate.

4. **The vision template section names in spec.md §Assumptions are wrong**. Spec says "Mission, What we are building, What we are not building, Current phase." The actual `plugin-kiln/templates/vision-template.md` uses "What we are building / What it is not / How we'll know we're winning / Guiding constraints." I went with the template's ground-truth names because that's what the skill actually writes. Future PRD cycles should reconcile this in the Assumptions block.

5. **Clarification #4 wording is slightly off**. Spec.md says partial snapshot "does not trigger the banner-style blank-slate fallback" — my SKILL.md implements this as a hard rule ("MUST NOT include `blank-slate` anywhere in the drafted body") and my assertion for T021 greps for that absence. If a future edit accidentally adds the word in an unrelated context, the test would false-positive. A canonical "blank-slate fallback banner:" prefix on the banner line would let the assertion grep for a precise marker instead of a substring match.

## Coordination with team

- **Phase 1 reader landed during my Phase 3 work** (impl-context-roadmap marked T001–T009 [X] mid-authoring). My pre-emptive fallback JSON is now dead code in the normal path, but kept for consumer-repo safety. Zero coordination cost — the contract's determinism made ships invisible.
- **I did not touch `plugin-kiln/scripts/context/` or `plugin-kiln/scripts/distill/`** — those are impl-context-roadmap and impl-distill-multi's scopes respectively. The only cross-track file I touched was `specs/coach-driven-capture-ergonomics/tasks.md` (to mark my own tasks [X]).
- **Signature Change Protocol was not invoked** — the contract shape was sufficient as written.

## Coverage (Constitution Article II)

- Both SKILL.md paths (§V vision + kiln-claude-audit) added FR-citing comments at every new logic block.
- Test fixtures carry FR / acceptance-scenario references in their `test.yaml` `description:` fields and in `assertions.sh` header comments.
- Coverage on shell-in-markdown is not measurable by `nyc`/`vitest`; the proof is acceptance-scenario mapping in the fixture headers.

## Artifacts shipped

**Phase 3 (T018–T028)**:
- `plugin-kiln/skills/kiln-roadmap/SKILL.md` — rewrote §V from a 3-question interview to a four-mode self-explore (first-run draft / re-run diff / empty fallback / partial snapshot).
- `plugin-kiln/tests/roadmap-vision-first-run/`
- `plugin-kiln/tests/roadmap-vision-re-run/`
- `plugin-kiln/tests/roadmap-vision-empty-fallback/`
- `plugin-kiln/tests/roadmap-vision-partial-snapshot/`
- `plugin-kiln/tests/roadmap-vision-no-drift/`

**Phase 4 (T029–T038)**:
- `plugin-kiln/rubrics/claude-md-best-practices.md` — new cached rubric.
- `plugin-kiln/skills/kiln-claude-audit/SKILL.md` — added Step 1 (reader consume), Step 3b (WebFetch + cache + staleness), extended Step 4 preview shape with `## Project Context` + `## External best-practices deltas` subsections; tightened Rules for FR-013/FR-014/FR-015/FR-016.
- `plugin-kiln/tests/claude-audit-project-context/`
- `plugin-kiln/tests/claude-audit-cache-stale/`
- `plugin-kiln/tests/claude-audit-network-fallback/`
- `plugin-kiln/tests/claude-audit-propose-dont-apply/`

All phase boundaries committed separately for clean reviewable history.
