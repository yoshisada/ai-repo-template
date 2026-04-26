# impl-plugin-guidance — friction note

**Agent**: impl-plugin-guidance
**Branch**: `build/claude-md-audit-reframe-20260425`
**Date**: 2026-04-25
**Phase**: 2B (author 5 first-party plugin guidance files)

## Files shipped

- `plugin-kiln/.claude-plugin/claude-guidance.md` (14 lines) — gold-standard reference
- `plugin-shelf/.claude-plugin/claude-guidance.md` (13 lines)
- `plugin-wheel/.claude-plugin/claude-guidance.md` (14 lines) — special case (plugin-agnostic infra)
- `plugin-clay/.claude-plugin/claude-guidance.md` (13 lines)
- `plugin-trim/.claude-plugin/claude-guidance.md` (13 lines)

All five pass the §4.4 self-verification checklist (path correct, `## When to use` first heading + 1–3 sentences not a list, no skill/command/agent/hook/workflow enumerations, 10–30 lines, single trailing newline).

## What was hard

### Distilling each plugin's voice down to "when to reach for it"

The raw temptation when authoring a guidance file for a plugin you know well is to enumerate — "here are the skills, here are the agents, here are the workflows." That's exactly the failure mode the reframe is correcting (it's plugin-surface and gets flagged by `enumeration-bloat`). The discipline I used: write each `## When to use` answering only "what kind of *task* should make Claude pick this plugin?" and then aggressively delete anything that drifted into "and here's how it does that."

The vision-style tone reference in `.kiln/vision.md` was load-bearing for keeping the right register. Without it I'd have probably defaulted to README-shaped prose. Re-reading the vision before each file kept the voice consistent.

### Wheel is genuinely tricky

Per the specifier handoff, wheel is plugin-agnostic infrastructure (per the `.kiln/vision.md` constraint "Plugins ship independently — wheel is plugin-agnostic infrastructure"). Every other plugin's `## When to use` reads "reach for X when the user wants to do Y" with Y being a user-recognizable activity. Wheel's "user" is *another plugin's skill*, not a human, so the framing had to shift. I cited the vision constraint inline in the When-to-use body so future authors don't accidentally bend wheel back toward feature-shaped framing.

### "Non-obvious behavior" is the section that needed the most judgment

The contract gave examples ("hidden config keys, side effects, ordering constraints") but no hard threshold for when something is non-obvious vs. self-evident. My heuristic: include only items that have actually bitten someone (or would predictably bite someone) — drift bugs, silent-failure modes, gates that look like warnings but aren't, lifecycle quirks. Things like "audit-style skills propose diffs but never apply them" and "wheel's `WORKFLOW_PLUGIN_DIR` portability rule" were the highest-confidence non-obvious items because there's existing PR / vision text documenting that they bit people.

I rejected several candidates for being self-evident from skill descriptions: "shelf can read GitHub issues" (skill description says so), "clay supports multiple modes" (skill descriptions list them).

## Judgment calls

1. **Inline mention of specific skill names is OK; bullet-list enumeration is not.** I read FR-002 + the contract §4.2 forbidden-list as targeting *enumeration as a content shape* (a list intended to be a catalog), not *any reference to a skill name in prose*. I cite `/kiln:kiln-distill` and `/kiln:kiln-build-prd` inline in kiln's `## Key feedback loop` because the loop literally needs those names to be intelligible. If the auditor disagrees, the names can be paraphrased ("the distill skill", "the build pipeline") without losing the loop's meaning.
2. **Section ordering is fixed (`When to use` → `Key feedback loop` → `Non-obvious behavior`)** even when an optional section is omitted. I authored all five with all three sections present because each plugin had genuine content for each. If a future plugin only has When-to-use, it should ship just that section per the contract.
3. **Soft 10–30 line cap, landed at 13–14 lines.** I deliberately came in below the midpoint because the reframe is about *less* CLAUDE.md content, not more — guidance files that are themselves bloated would model the wrong behavior. Authors of future guidance files for additional plugins should aim for the same range, not the upper bound.
4. **Wheel's "agent-resolver primitive" reference is intentional non-obvious-behavior content** even though resolver internals are arguably plugin-surface. The non-obvious part isn't that the resolver exists — it's that bare-name lookups are an anti-pattern and the central registry was deliberately deleted. That fact is genuinely load-bearing for anyone designing a new agent and is documented in CLAUDE.md's Recent Changes; folding it into wheel's guidance file co-locates it with the other architectural rules for that plugin.

## Process improvements

These would have helped this phase but aren't blockers:

- **A skim-pattern for plugins.** I read 1–2 SKILL.md files per plugin to internalize what each plugin DOES, but a 1-paragraph "what this plugin actually does" cheat-sheet per first-party plugin would have shortened the authoring time meaningfully. Could be derived from each plugin.json's `description` plus the plugin's README if one exists. Possible follow-on: a `read-plugins.sh` extension that emits a per-plugin one-paragraph synthesis.
- **A negative-example library.** The contract forbids enumerations, command catalogs, agent inventories, hook listings, workflow paths. A short anti-pattern doc with one concrete "don't write this" example per forbidden category would have made self-verification faster. The §4.4 checklist names what to check; it doesn't model the anti-pattern shape.

## For the retrospective

- The Phase 2A ↔ Phase 2B coupling (T082, T088 in audit-logic depend on at least kiln + shelf guidance files existing) was correctly flagged in tasks.md and my files for both shipped in the same commit, so the dependency was satisfied trivially. Worked well.
- The voice/tone reference (`.kiln/vision.md`) was the single most useful piece of context for this phase — more useful than the contract itself, which got me the *shape* but not the *register*. Future implementer prompts authoring narrative content should always cite a tone reference.
- The `## When to use` "1–3 sentences (not a list)" constraint is good but easily slipped if you start typing a list of activities. Consider adding "if the section needs to be a list, it's almost certainly the wrong section — promote it to `## Non-obvious behavior` (which is allowed to be a list)" to the contract or the §4.4 checklist as authoring guidance.
- The "wheel is special" handoff from the specifier was load-bearing — without it I'd have likely written a wheel guidance file shaped like the others (i.e. wrong). Suggest formalizing this in the contract: any plugin tagged as plugin-agnostic infrastructure in `.kiln/vision.md` Guiding constraints should have its guidance file framed at the infrastructure layer, not the user-task layer.

## Anything else flagged

Nothing blocking. All five files satisfy the §4.4 checklist; coupling with `impl-audit-logic`'s T082/T088 fixtures is preserved (kiln + shelf both shipped in the same commit and are available before audit-logic needs them).
