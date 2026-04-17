# impl-kiln Friction Note — Mistake Capture

## What was clear

- **Contracts were excellent.** `contracts/interfaces.md` §§1–3 and §7 gave me exact filenames, exact JSON shape, exact step IDs, exact body-section headings, exact honesty-lint trigger words, and exact slug-derivation algorithm. Almost no judgment calls required for the files I owned.
- **Parity references worked.** Each new artifact pointed to a canonical sibling (`report-issue/SKILL.md`, `report-issue-and-sync.json`) whose shape I could mirror verbatim. The call-out that the mistake SKILL.md *adds* a guardrails block vs report-issue was the only intentional divergence — easy to apply.
- **Portability rule was unambiguous.** The `${WORKFLOW_PLUGIN_DIR}/scripts/...` requirement was stated in three places (CLAUDE.md, tasks.md preamble, contracts/interfaces.md §3) with the exact grep check baked into T010. Hard to miss.
- **The team-lead briefing was correctly scoped.** Explicit scope boundary ("plugin-kiln only, do NOT touch plugin-shelf/") plus the list of reference files to read before starting prevented cross-owner file collisions.

## What was ambiguous or friction-inducing

1. **T013 was slightly miscast.** The contract §7 says "if plugin.json maintains an explicit `skills:` listing, add `mistake`". Kiln's plugin.json has no `skills:` list — but it DOES have a `workflows:` list, and the new workflow MUST be registered there or `/wheel-list` won't discover it. The contract mentions workflow registration tangentially ("Consumer-repo override") but doesn't explicitly require editing `workflows:` in plugin.json. I added the workflow registration in the same edit as the skip-skills-list decision; called it out in T013's note. A future contract should split skill registration and workflow registration into separate bullets.

2. **T014/T015 aren't runnable inside Phase 3.** `workflow_discover_plugin_workflows` (plugin-wheel/lib/workflow.sh:323) reads from `~/.claude/plugins/cache/<marketplace>/kiln/<version>/workflows/...`. Source-tree changes in `plugin-kiln/workflows/` don't surface via `/wheel-run kiln:<name>` until the plugin is published to the marketplace and the consumer reinstalls. Tasks.md Phase 3 treats T014/T015 as independent sanity checks, but in practice they're Phase-5-smoke prerequisites. I documented this and performed surrogate static checks (jq validity, portability grep, direct command-step eval with `WORKFLOW_PLUGIN_DIR` exported).

3. **The `@manifest/templates/mistake.md` strip step (contract §2.1 step 8).** Per team-lead note, the template's metadata block may or may not exist at run time. The instruction says to strip "everything before the first `---` frontmatter delimiter ... if the template has no such block, proceed with the body as-is". I reflected the no-op fallback, but the whole concept of "read the template via MCP, strip a block, use as layout" requires the `create-mistake` agent to have MCP read access to `@manifest`. The workflow doesn't explicitly declare that capability. If the agent step runs in a subagent without manifest-scope MCP, the template read will fail silently and the agent will just construct the body from the section-heading list in the instruction — which happens to produce the same result because the contract re-states the five headings verbatim. So this is a silent robustness property, not a bug. Worth pointing out in retrospective: the instruction is intentionally self-contained and doesn't actually need the template.

4. **`made_by` inference is fragile.** The instruction says "infer from your own runtime model ID if known, then confirm with the user". There's no reliable way for the agent to read its own model ID from inside a wheel agent step — the `claude-opus-4-7[1m]` string appears in the system prompt but isn't exported to the agent as a variable. In practice the agent will always ask the user. That's fine — the contract says "if inference is impossible, the agent asks" — but we should expect 100% user-ask rate on this field. Calling it "inferred" in the contract gives a false sense of automation.

## Assumptions I made

- **Skill discovery is filesystem-based.** Based on the absence of a `skills:` list in plugin.json and the parity with every existing kiln skill (none are listed), I assumed creating `plugin-kiln/skills/mistake/SKILL.md` is sufficient for discovery. If plugin.json gains an explicit `skills:` list in the future, this will need updating.
- **Workflow version 1.0.0 is correct.** Contract §2 "Workflow parity reference" says "Version starts at 1.0.0 not 2.0.0 because this is the first release". Applied verbatim.
- **The template-strip instruction is defensive.** The instruction tells the agent to strip a block that may not exist. I didn't try to remove that step — if the template ever grows a metadata block, the instruction already handles it.
- **Leaving the `.kiln/mistakes/2026-04-16-fixture-shelf-discovers-mistakes.md` fixture alone.** impl-shelf created it for their T030. Tasks T034 instructs them to delete it before committing. I did NOT stage or delete it — scope boundary.

## What I wish was more explicit

- **Workflow registration in plugin.json.** Contract §7 should explicitly say "add `workflows/<name>.json` to plugin.json `workflows:` array" as a required sub-task, not just "the consumer-repo override mechanism applies identically". I inferred it from reading plugin.json + parity with report-issue-and-sync, but a new implementer might miss it.
- **Explicit deferral note for T014/T015.** The tasks.md task description for T014 says "verify `report-mistake-and-sync` is listed under the kiln plugin" — but the plugin-cache discovery model makes this impossible inside a single Phase 3 session on source. A preamble note saying "these two tasks are deferred-to-Phase-5 in source-tree runs and will only pass after a marketplace re-install" would prevent me guessing whether I was doing something wrong.
- **`WORKFLOW_PLUGIN_DIR` availability in the `create-mistake` agent step.** The contract uses it for the command step only. If the agent step ever wants to resolve the template path via the plugin cache, it would need the variable. Not a bug, but worth noting: today's instruction doesn't use it, and that's fine.

## Integration friction with impl-shelf

**None observed.** File ownership was a hard boundary. I did NOT touch:
- `plugin-shelf/scripts/compute-work-list.sh`
- `plugin-shelf/scripts/update-sync-manifest.sh`
- `plugin-shelf/workflows/shelf-full-sync.json`

I only read `plugin-shelf/workflows/shelf-full-sync.json` to confirm the `terminal: true` workflow-step signature for my `full-sync` step. That file wasn't modified by me.

The only shared-surface touch is `.kiln/mistakes/` — I don't scaffold it (spec says create-on-first-write); impl-shelf's compute-work-list.sh must tolerate its absence. Their script does (per contract §4 "If the directory does not exist, emit an empty array `[]`"). Clean hand-off.

## Total time spent / blockers

- Reading references (contracts, plan, tasks, parity files): ~5 min.
- Writing the three plugin-kiln artifacts: ~10 min.
- Validation + static contract checks: ~3 min.
- Friction note (this file): ~8 min.
- **No blockers.** T014/T015 hit the plugin-cache limitation but were resolvable via surrogate checks + deferral to Phase 5.
