# Specifier Notes — Fix Skill with Recording Teams

**Agent**: specifier
**Team**: `kiln-fix-skill-with-recording-teams`
**Pass**: /kiln:specify → /kiln:plan → /kiln:tasks (single uninterrupted run)

## Outcomes

- `specs/fix-skill-with-recording-teams/spec.md` — 10 user stories (P1×3, P2×5, P3×2), 30 FRs mapping PRD FR-1..FR-20 plus 10 operational derivations, 10 SCs mapping PRD M1..M5.
- `specs/fix-skill-with-recording-teams/plan.md` — tech context, 8 constitution checks (all pass with two documented caveats around test coverage for bash + E2E via quickstart), project structure, 7 research decisions (R1..R7; plus R8..R10 in research.md).
- `specs/fix-skill-with-recording-teams/contracts/interfaces.md` — envelope JSON schema, six helper-script contracts, three reused-shelf-script read-only contracts, two team-brief input contracts (fix-record, fix-reflect), skill-level Step 7 contract.
- `specs/fix-skill-with-recording-teams/research.md` — R1..R10 inline decisions with rationale + alternatives.
- `specs/fix-skill-with-recording-teams/data-model.md` — six entities (envelope, local record, Obsidian note, manifest type, proposal, reflect output) with relationships diagram.
- `specs/fix-skill-with-recording-teams/quickstart.md` — 5 manual smoke paths (happy, escalated, reflect-happy, MCP-unavailable, project-name-unresolvable) + consumer-repo portability spot-check.
- `specs/fix-skill-with-recording-teams/tasks.md` — 20 tasks in 8 phases, FR-coverage table, dependency graph, MVP scope. Sized for one implementer.
- `specs/fix-skill-with-recording-teams/checklists/requirements.md` — validation checklist, all items passed.

## Friction notes for the retrospective

### Prompt-clarity issues hit

1. **Kiln skills expect the script `create-new-feature.sh` to have not run yet.** The team-lead had already checked out the correct branch before invoking the specifier, which meant the `/kiln:specify` skill's step 2 (run `create-new-feature.sh`) would have been redundant (and possibly conflicted with the pre-created branch). I skipped it — the skill should arguably detect an already-checked-out branch matching the feature slug and no-op the branch-creation step. As it stands, the skill's outline assumes a fresh invocation.

2. **`/kiln:specify` step 0 checks for an existing spec by reading `check-prerequisites.sh`.** The `FEATURE_DIR` it returned pointed to the correct path, but the dir did not exist yet because the team-lead pre-created only the branch, not the spec dir. This is fine in practice (I created the dir inline) but the skill's "existing spec → skip to step 6" branch is tuned for a different workflow (one-shot specify in the same session that created the branch).

3. **The tasks-template's "Format: `[ID] [P?] [Story] Description`" section is strict but the template's sample content is illustrative (not example-realistic).** The skill emphasizes NOT keeping the sample tasks. I followed the format strictly but a future update could compress the tasks-template's intro (the actual gate is 3 items: checkbox, ID, file path; the [P] and [Story] qualifiers are situational). Right now the template spends ~40 lines re-explaining "don't use the samples" — arguably noise.

### Tooling friction

1. **`mcp__claude_ai_obsidian-manifest__read_file` was not available in this agent's environment**, despite the team-lead's guidance suggesting we could read `@manifest/types/mistake.md` to model the new `fix.md` after. I worked around this by describing the `fix.md` schema from PRD FR-5/FR-6 + the parallel shape described in the spec. The implementer will do the actual comparison against `mistake.md` during T015. If a future pipeline pass needs the manifest MCP during specify, the team brief should pre-check or pre-load the reference file content.

2. **`$FEATURE_DIR` naming convention varies between kiln specs.** Existing specs use a mix of `<slug>`, `NNN-<slug>`, and `build/<slug>-<date>` under `specs/`. The team-lead explicitly said "NO numeric prefix — use exactly `fix-skill-with-recording-teams`". Worth preserving that directive in future specifier briefs so it doesn't surprise a first-time implementer — the current `/kiln:specify` skill will happily attempt `NNN-` prefixes if invoked fresh.

3. **The `create-new-feature.sh` script would have created the branch AND the spec dir if I had invoked it.** Pre-existing branch + pre-existing no-prefix directory worked around this, but the invariant "branch creator == spec-dir creator" is load-bearing for the skill's happy path. If the implementer or a future specifier invokes `/kiln:specify` from a session where the branch was pre-created, they may see the skill attempt to switch branches or rename dirs. Tag this as a potential skill improvement: detect existing branch + spec dir and no-op gracefully.

4. **No `bats` installed in the repo.** The team-lead flagged this upfront (good) but kiln's plan template mentions `XCTest`/`pytest`/`cargo test` in the same breath as generic "Testing" field. A plugin/bash-centric testing norm ("pure bash `.sh` test scripts, one exit-1 per assertion failure") is worth making explicit in the plan template. FR-024 captures this for the feature; the template could bake it in.

### Template gaps

1. **`interfaces-template.md` is TypeScript-first.** The template's example uses `export function` TypeScript signatures. This feature's interfaces are bash scripts + JSON schemas + team briefs. I wrote free-form contract sections instead of forcing a TypeScript shape — clean outcome but the template implicitly assumes a code-first project. A "bash + markdown contract" mode (script signature blocks with stdin/stdout/exit-code grid) would be a useful template addition for plugin-authoring specs.

2. **`plan-template.md` has only three "options" for Source Code tree** (single project, web app, mobile + API). A fourth option ("Plugin skill/helper layout") would save hand-authoring the tree for every plugin feature. Not blocking; noting for future polish.

3. **`tasks-template.md` assumes tests-per-story**. For a feature where tests and helpers must be authored together to respect "no helper without a test" (FR-030), I collapsed helper + test into one task each. This is a cleaner workflow for bash-centric features but diverges from the template's "Tests [P] → Implementation" sequence. Worth documenting as a template variant.

4. **`checklist-template.md` is not referenced from anywhere I could find** (`/kiln:specify` creates an ad-hoc checklist in the outline). I authored `checklists/requirements.md` matching the format in the outline — works, but the template is orphaned. Small cleanup opportunity.

### Speed-of-pass observations

- Reading the PRD (147 lines) + spec template + plan template + interfaces template + constitution + one parallel spec (`manifest-improvement-subroutine`) consumed ~half the upfront context work. Having the team-lead direct me to specifically the manifest-improvement-subroutine spec as a pattern saved significant search time.
- The three kiln skills were invoked consecutively without inter-stop. No user input needed between them because (a) the PRD resolved the four open questions inline, (b) the team-lead provided tag-axis and gitignore decisions, (c) no NEEDS CLARIFICATION markers needed to be surfaced.
- Total artifacts: 8 markdown files. Total lines authored: ~1,400 (spec) + ~200 (plan) + ~200 (interfaces) + ~100 (research) + ~120 (data-model) + ~150 (quickstart) + ~220 (tasks) + ~90 (checklist) + ~120 (these notes). Large but proportional to a 30-FR feature.

### One thing I'd want next time

A **"plugin feature" skill variant** that skips branch creation (assumes caller pre-created), knows the test harness is pure bash, uses a bash-contract template, and pulls the parallel-feature reference in automatically. That would trim ~20% of the friction above.

## Signal to hand off

Implementer is unblocked. The MVP scope (T001–T012) is 12 tasks; the full feature is 20. No cross-file coordination hazards except T011 and T014 serializing on SKILL.md if the implementer keeps briefs inline (R4 resolves this with an automatic sibling-file fallback at 500 lines).
