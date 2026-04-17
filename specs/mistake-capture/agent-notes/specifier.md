# Specifier Friction Note — Mistake Capture

**Role**: specifier
**Date**: 2026-04-16
**Branch**: build/mistake-capture-20260416

Retrospective input. Writing before marking task #1 complete, per the team-lead's instructions.

## What was clear in the PRD

- **Architectural parity with `/report-issue`** was pinned with a side-by-side table and an explicit "Absolute Must". This eliminated an entire class of structural ambiguity — the three-step workflow shape, the terminal `shelf:shelf-full-sync`, and the `.kiln/<thing>/` local-first-then-sync pattern were settled before I started. Excellent.
- **Non-negotiables listed as a numbered block** ("Absolute Musts" 1–7). I copied each into the spec as constraints / success criteria. Easy to trace. The numbered-list format is a pattern worth keeping in future PRDs.
- **FR-1 through FR-16 with inline context** (not just bullet points). Each FR came with enough surrounding prose that I could turn it directly into a spec FR with a PRD-number reference. No guesswork on what any FR meant.
- **Manifest references** (`@manifest/types/mistake.md`, `@manifest/templates/mistake.md`, `@manifest/systems/projects.md`) were explicitly tagged as the source-of-truth for schema. I did not have to re-derive the mistake-note schema from scratch — the PRD treated the manifest as authoritative and I followed.
- **Portability rule** re-stated in the PRD ("Absolute Must #6") AND in `CLAUDE.md`. Redundancy here is good — the spec and contracts can quote `${WORKFLOW_PLUGIN_DIR}` with confidence that nobody will push back.
- **Open Questions section** distinguished what the PRD author knew they were leaving for `/plan`. Every one of them was resolvable with a short research note (research.md §R*). No true unknowns leaked into the spec.

## What was ambiguous or under-specified

- **MCP scope for `@inbox/open/` writes (R2)**. The PRD flagged this as "Needs verification during `/plan`". I resolved it as "assume `mcp__obsidian-projects__*`, fallback to `mcp__claude_ai_obsidian-manifest__*` if the create_file fails". This is a real runtime-verifiable unknown; the fallback is cheap. Worth calling out here because impl-shelf may hit it.
- **"Filed" state tracking for proposals (FR-14)**. The PRD said "prevent resurrection loops" and gave two options ("sibling state entry (or frontmatter field)"). I picked sibling state entry in the sync manifest in research.md §R4. This is a design decision I made as specifier that the PRD explicitly left to plan — the choice is documented but another reviewer could disagree. I'd welcome impl-shelf flagging if they prefer the frontmatter-marker approach.
- **Model ID detection for `made_by` (R6)**. PRD Risks section said "inferring from environment may be fragile". I chose "agent infers from its own runtime knowledge". This works for Claude but leaves a hole for non-Claude models running the workflow in the future. Flagged as an assumption; not blocking for v1.
- **Honesty-lint hedge-word list**. PRD FR-7 enumerated 8 hedge phrases (`may have`, `might have`, etc.). I encoded them verbatim in contracts §2.2. The PRD called out that the list will produce false positives — "false-positive friction is the lesser evil". I accepted this framing. Some rephrase friction during smoke-testing is expected and NOT a bug.
- **Template-metadata block stripping** (FR-6 step 7). The PRD says "Template-metadata block stripped" when writing from `@manifest/templates/mistake.md`. I inferred this means the top-of-file `---` frontmatter identifying the template itself (as opposed to the frontmatter of the instance being written). Contracts §2.1 step 8 restates this. If impl-kiln can't locate a template-metadata block in the current `@manifest/templates/mistake.md`, they should flag — the stripping instruction only makes sense if the template actually has such a block today.

## Assumptions I had to make

1. **Filename slug derivation algorithm** (contracts §2.4): the PRD says "kebab-cased, stop-words stripped, truncated to 50 chars". I wrote a seven-step algorithm but did NOT prescribe a specific stop-word list beyond a small illustrative set. The agent has latitude; impl-kiln may refine the list during smoke-testing.
2. **`check-existing-mistakes.sh` as a script file** vs an inline shell one-liner in the workflow JSON (research §R1). The `/report-issue` equivalent is inlined, but I factored this out because our Step 1 is structurally more complex (two source paths, formatted output headers) and because shelf factors similarly. impl-kiln could push back and inline — the contract §3 cap at 80 lines makes either choice workable.
3. **`mistake_class` frontmatter field on the proposal** (contracts §5.1). The PRD did NOT require a dedicated `mistake_class:` field on the proposal — only that the class be present somewhere in tags. I added the field for scannability. If impl-shelf objects, we can drop it and rely on the tag alone.
4. **Proposal filename infix `-mistake-`** (`YYYY-MM-DD-mistake-<slug>.md`, research §R3). The PRD specified `@inbox/open/` but not the filename convention. I added `-mistake-` for inbox-scan ergonomics. Swap-outable without consequence.
5. **"Filed" state detection via `list_files` on `@inbox/open/`** (contracts §6). One MCP list call per sync, guarded. The PRD did NOT enumerate a detection mechanism. I chose this because it's O(1) reads per sync regardless of mistake count and reuses MCP tooling already present in `obsidian-apply`. If MCP's `list_files` is not available or is prohibitively paginated, impl-shelf should fall back to per-entry `read_file` existence checks (N reads) and flag the regression.

## What I wish the PRD had said explicitly

1. **Whether `make_by:` values should include a version suffix** (e.g., `claude-opus-4-7` vs `claude-opus-4-7-20260101`). I chose the kebab-cased short form per the manifest examples, but if the manifest's intention is that longer-form identifiers are preferred for disambiguation across model snapshots, the spec should say so.
2. **Whether the `create-mistake` agent step should persist partial progress** if the user cancels mid-collection. I defaulted to "no partial writes" (FR-6 step 8, the `-2` suffix behavior only kicks in on a successful-complete collision). Confirming this in the PRD would foreclose the question.
3. **What happens if `@manifest/types/mistake.md` is unavailable** at runtime (e.g., the Obsidian MCP is down). The PRD assumed the manifest is readable. If MCP-read failure should fall back to a local cached copy of the schema vs just refusing to capture, the spec should say so. Currently: undefined behavior.
4. **Whether the proposal body should preserve the source artifact's H1 or re-write it**. I chose "re-write to `# Mistake Draft — <title>`" in contracts §5.2 so the proposal is distinguishable from the source at a glance. If the reviewer prefers to move the proposal and have the H1 already match the project-mistakes format, this choice matters.
5. **Whether `/kiln:mistake` should be a top-level `/mistake` after plugin activation**. The skill's discoverability depends on Claude Code's skill namespacing. Currently I assumed `/kiln:mistake` (namespaced). If the kiln plugin exposes skills at the top level, rename.
6. **Severity-auto-calibration stance under stress**. PRD Non-Goals says "no severity auto-calibration". I enforced this in contracts §2.1 ("Do NOT auto-calibrate"). But during a live capture where the user is rushing, the cost of asking for severity is non-trivial. If the PRD were to relax to "suggest a severity, user confirms" (a la `made_by`), friction would drop. Flagged for the retrospective — not a change request.

## Observations for the retrospective agent

- Chaining `/kiln:specify → /kiln:plan → /kiln:tasks` in one pass worked cleanly when the branch was pre-checked-out and the spec directory was specified canonically (no `001-` numeric prefix) in every invocation. The team-lead's explicit canonical-path instruction was load-bearing — without it, `/kiln:specify` would have tried to run `create-new-feature.sh` and clobbered the pre-existing branch state.
- I bypassed `create-new-feature.sh` entirely and wrote the spec directly at the canonical path. The skill's step-0 check (existing spec) would also have handled this had a spec existed, but this feature started with no spec and the branch already checked out, which is not the skill's default path.
- The `/kiln:plan` skill expected `setup-plan.sh` to be run; I skipped it for the same reason (it would have produced non-canonical paths). Writing plan.md directly at the canonical path was fine but means the skill's own setup steps are bypassed — the step is advisory when the canonical path is pinned externally.
- The `/kiln:tasks` skill's template suggests organizing by user story. I organized by OWNER instead, because the team-lead's instructions explicitly called for that split and the feature's boundary genuinely is plugin-owned, not story-owned. The tasks.md calls this deviation out in its "Organization" section.
