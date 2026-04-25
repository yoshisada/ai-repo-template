# Specifier friction note — wheel-step-input-output-schema

**Track**: specifier (TaskList #1)
**Branch**: `build/wheel-step-input-output-schema-20260425`
**Authored**: 2026-04-25

## What I produced

- `specs/wheel-step-input-output-schema/spec.md` — 6 user stories, 5 themes (G1..G5), 22 FRs, 7 NFRs, 13 edge cases, recalibrated SC-G-1 against research.md §baseline.
- `specs/wheel-step-input-output-schema/plan.md` — architecture overview, 6-phase phasing, FR→file→test tracking matrix.
- `specs/wheel-step-input-output-schema/contracts/interfaces.md` — 7 contracts: `_parse_jsonpath_expr`, `resolve_inputs`, `extract_output_field`, `substitute_inputs_into_instruction`, `workflow_validate_inputs_outputs`, schema additions, `CONFIG_KEY_ALLOWLIST`.
- `specs/wheel-step-input-output-schema/tasks.md` — 7 phases, ~40 tasks across two implementer tracks (impl-resolver-hydration, impl-schema-migration) with `[DEP]` cross-track flags.

## OQ-G-1 spec-phase decision

Picked **Candidate A — allowlist of safe config keys, default-deny on unknown** for `$config(<file>:<key>)` resolution per NFR-G-7. Rationale documented in spec.md "OQ-G-1" section. Allowlist lives at `plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST`; v1 ships 5 entries (all `.shelf-config` keys, all non-secret by inspection). JSON-file resolution form (`<file>:<jq-path>`) is NOT allowlisted — the literal jq path in the workflow JSON is the gate.

Also resolved OQ-G-2 (defer `context_from:` rename — research.md §audit-context-from confirms 84% of uses are pure-ordering and would rename cleanly, but the 10 data-passing/probable cases need migration first; rename in a follow-on PRD avoids parallel-name maintenance) and OQ-G-3 (scope `inputs:` to agent-step types in v1; parallel/loop/teammate are deferred).

## What was confusing in my prompt

1. **"Run /specify, then /plan, then /tasks back-to-back" — these slash commands are interactive UX skills, not pipeline-ready batch generators.** I produced the four artifacts directly using the established shape from `specs/cross-plugin-resolver-and-preflight-registry/` rather than literally invoking `/kiln:specify`, `/kiln:plan`, `/kiln:tasks` because each is structured for a turn-by-turn human conversation. **Improvement**: the specifier prompt should either (a) explicitly say "produce the four artifacts directly using the templates at `templates/spec-template.md` etc." or (b) the kiln pipeline should ship a non-interactive batch entrypoint like `kiln:specify --from-prd <path> --output <dir>` that the specifier teammate can call without UX collisions.

2. **The PRD's SC-G-1 was numerically wrong** ("≥3 fewer agent Bash/Read tool calls"). The researcher-baseline track caught this in §baseline — post-FR-E batching, the baseline `command_log` length is already 1, so the post-PRD goal is 0 (delta of 1 agent call). The correct headline metric is the count of disk-fetch sub-commands inside the formerly-batched bash (3→0). I recalibrated SC-G-1 in spec.md to be a compound (a)+(b) gate that captures both the tool-call delta AND the inline-sub-command delta. **Improvement**: the PRD authoring step should run a baseline pass BEFORE freezing headline metrics — the team-lead's "captured at PR #165's merge commit before implementation begins" phrasing in the PRD shows the intent, but the actual numbers were not in the PRD at freeze time, so the SC-G-1 threshold was stale-by-default.

3. **researcher-baseline ran before specifier finished.** TaskList shows #1 and #2 both `in_progress`; in practice the researcher already produced research.md before I could finish my pass. This is FINE for outcome (their findings strengthened my SC-G-1 recalibration) but the team-lead's task-dependency graph (#2 blocked by #1) was violated. **Improvement**: the team-lead pipeline should either (a) actually serialize via `blockedBy` enforcement, or (b) explicitly document that researcher-baseline runs in parallel with specifier and the specifier should plan to fold in research findings on a second pass. The current state ("blocked by #1" but actually running concurrently) is misleading.

4. **Contracts file is the choke point.** Article VII (mandatory interface contracts) is correct — without it, two parallel implementers will diverge on function signatures. The contract format (signature + invariants + edge-case table) lifted from cross-plugin-resolver works well; I cloned its shape verbatim. **No improvement needed** — keep it as-is.

5. **No anchor in the prompt for "what existing artifacts to mirror."** I had to grep `specs/` to find a previous similar PRD's structure. **Improvement**: the team-lead specifier prompt could include a `**Mirror**: specs/<previous-similar-feature>/` line pointing at the canonical exemplar. Without it, the specifier wastes a turn picking a template.

6. **Where I got stuck (briefly)**: deciding whether to invoke the slash skills literally (interactive turns) vs produce artifacts directly (batch). I chose batch given the prompt's "single uninterrupted pass" + "do NOT stop, do NOT wait, do NOT go idle" framing — those phrases are incompatible with multi-turn skill invocation. **Improvement**: clarify intent in the specifier prompt — direct artifact production is what the pipeline actually wants here.

## Improvements to suggest to /kiln:kiln-build-prd / specify / plan / tasks

- **(P0)** Surface the ambiguity in #1 above: either provide a non-interactive batch entrypoint OR explicitly tell pipeline-spawned specifiers "produce artifacts directly using `templates/`."
- **(P1)** PRD authoring step should freeze SC numbers AFTER a baseline capture, not before. The current PRD format has the SC text frozen at PRD-creation time, which means stale-by-default if any code change between PRD-creation and pipeline-start affects the baseline. Either: (a) PRD specifies the *shape* of the metric (e.g. "drop tool-call count" without a number), and the spec phase fills in the threshold from research.md; (b) the build-prd pipeline runs a baseline-capture step BEFORE the PRD is finalized.
- **(P2)** Pipeline contract should clarify whether `blockedBy` is enforced or advisory. Right now it appears to be advisory — researcher-baseline started before specifier finished. If that's intentional (parallelism), document it. If it's a bug, fix it.
- **(P2)** Add a `**Mirror**` field to the team-lead's specifier prompt template pointing at the canonical exemplar PRD.

## Next-step ownership

After this commit, I notify (per task-#1 prompt requirements):
- `researcher-baseline` — informational ("specifier complete; spec.md acknowledges your §baseline recalibration of SC-G-1; research.md §audit-context-from is now FR-G5-3's anchor")
- `impl-resolver-hydration` — unblocked (Phase 2.A → Phase 3 → tests, per tasks.md)
- `impl-schema-migration` — unblocked (Phase 2.B → Phase 4, with `[DEP impl-resolver-hydration]` flags)
