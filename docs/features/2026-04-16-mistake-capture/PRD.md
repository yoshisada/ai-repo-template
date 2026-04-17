# Feature PRD: Mistake Capture

## Parent Product

Kiln Claude Code plugin (`@yoshisada/kiln`) — spec-first development workflow with 4-gate enforcement, PRD-driven pipelines, integrated QA/debugging agents. The shelf plugin (`plugin-shelf`) is the sibling that syncs repo artifacts (issues, docs, progress) to an Obsidian "projects" system.

The Obsidian vault's `@manifest/` folder is the authoritative source of truth for what a "mistake" note is: `@manifest/types/mistake.md` (schema + honesty principle), `@manifest/templates/mistake.md` (template), `@manifest/systems/projects.md` (where mistakes live and how they're filed).

## Feature Overview

A new kiln skill, `/kiln:mistake`, that captures an AI-made mistake (wrong assumption, bad tool call, missed context) in a structured local artifact at `.kiln/mistakes/YYYY-MM-DD-<assumption-slug>.md`. The artifact conforms to the `@manifest/types/mistake.md` schema. Shelf picks it up on the next sync and files it as a proposal in `@inbox/open/` for human review; the maintainer then moves accepted notes into `@second-brain/projects/<slug>/mistakes/`.

**The feature runs on the wheel workflow engine**, mirroring the existing `/report-issue` → `workflows/report-issue-and-sync.json` pattern exactly. The `/kiln:mistake` skill is a thin entrypoint — it activates a wheel workflow (`report-mistake-and-sync`) and wheel's hook-driven state machine handles every step from there. This gives the feature the same characteristics `/report-issue` has today: hook-advanced progression, structured step outputs in `.wheel/outputs/`, composable terminal step into `shelf:shelf-full-sync`, and full state-file audit trail in `.wheel/history/`.

Architectural parallel:

| `/report-issue`                                   | `/kiln:mistake`                                   |
|---------------------------------------------------|---------------------------------------------------|
| Skill: `plugin-kiln/skills/report-issue/`         | Skill: `plugin-kiln/skills/mistake/`              |
| Workflow: `plugin-kiln/workflows/report-issue-and-sync.json` | Workflow: `plugin-kiln/workflows/report-mistake-and-sync.json` |
| Local artifact: `.kiln/issues/<slug>.md`          | Local artifact: `.kiln/mistakes/<slug>.md`        |
| Terminal step: `shelf:shelf-full-sync`            | Terminal step: `shelf:shelf-full-sync`            |
| Obsidian destination: issue notes in project      | Obsidian destination: proposal in `@inbox/open/`  |

## Problem / Motivation

Claude makes recoverable mistakes on this repo regularly — wrong tool names, stale assumptions about plugin install paths, hedging instead of investigating. The corrections land in conversation transcripts and evaporate at session end. Future Claude sessions on this stack repeat them.

The manifest has the full type spec for mistake notes (honesty principle, three-axis tagging, required fields, proposal write-flow) but there's no capture affordance in the repo. Without one:
- Contributors (human or AI) mid-session won't stop to hand-write a fully-conformant mistake note — the cost is too high for a 10-line artifact.
- Retroactive capture from transcripts is almost never done in practice.
- The training-data value of mistake notes depends on volume; zero-friction capture is the unlock.

## Goals

- Zero-friction mistake capture: one slash command from inside a Claude Code session, ~30 seconds to produce a conformant note.
- 100% manifest-schema conformance on write — tag on three axes, required fields filled, filename slug summarizes the assumption (not the action), honesty-principle linting applied to `assumption:`/`correction:`.
- Route to `@inbox/open/` via shelf sync (proposal flow) — never directly into `<project>/mistakes/`, because the manifest requires human review.
- Symmetric with `/report-issue` — same invocation style, same `.kiln/` local-first pattern, same shelf pickup.

## Non-Goals

- Direct writes to `@second-brain/projects/<slug>/mistakes/`. The manifest mandates proposal flow through `@inbox/open/`. Bypassing it is out of scope.
- Auto-capture of mistakes from hook failures, agent errors, or tool-call errors. V1 is human-invoked only. Automation is a future phase once the manual flow is producing high-quality notes.
- Backfill tooling that reads session transcripts and synthesizes historical mistake notes. Out of scope — retroactive mass creation produces shallow notes, per the manifest's LLM notes.
- Registering a formal `mistake-draft` proposal kind with the manifest. Use the existing `kind: content-change` with an explanatory body until the pattern settles, per `@manifest/systems/projects.md`.
- Severity auto-calibration. The skill asks; it does not decide. Honesty principle trumps convenience.
- Cross-linking automation (`led_to_decision` / `prompted_by_mistake`). V1 lets the user fill these manually if they apply.

## Target Users

- **AI contributor agents working in this repo** — the entities most likely to have *made* the mistake. Primary caller of `/kiln:mistake`.
- **Humans reviewing `@inbox/open/` proposals** — the quality gate between draft and accepted note. Benefit from well-formed, honest drafts that are cheap to accept or reject.
- **Future AI agents on a similar stack** — the downstream consumer. They query accepted mistake notes by `mistake/*`, `topic/*`, and stack tags to avoid re-making the same errors. They never call the skill directly but are the reason the artifact exists.

## Core User Stories

- As a contributor AI that was just corrected by the user ("no, that's per-project, not per-vault"), I want to run `/kiln:mistake` so the correction is captured as a conformant note before the conversation moves on.
- As a contributor AI that caught its own mistake mid-session (rebuilt something because an earlier tool call returned unexpected output), I want to run `/kiln:mistake` so the false belief and the real correction are both recorded.
- As a human maintainer, I want mistake drafts to land in `@inbox/open/` with valid frontmatter and three-axis tags so I can accept them with one command instead of rewriting.
- As a future Claude session starting work on a Next.js + TypeScript project in this org, I want `TABLE assumption, correction FROM #mistake/tool-use AND #framework/next` to return real, honest notes so I can avoid the traps that prior agents fell into.

## Functional Requirements

### Skill entrypoint

**FR-1. `/kiln:mistake` skill exists in `plugin-kiln/skills/mistake/SKILL.md`.** User-invocable via the standard slash-command convention. Discoverable in the kiln plugin's skill listing.

**FR-2. The skill is a thin wheel-workflow wrapper.** Its job is: (a) capture the user's free-form description of the mistake from the slash-command input, (b) activate the `report-mistake-and-sync` wheel workflow via `<plugin_dir>/bin/activate.sh`, (c) stop. It does NOT prompt for fields, lint, validate, or write files itself — every one of those responsibilities lives in the workflow. This matches the existing `/report-issue` skill pattern exactly.

**FR-3. The skill's SKILL.md includes the LLM guardrails** from `@manifest/types/mistake.md` — honesty principle, severity calibration, "do not write mistake notes about the human", filename slug names the trap — so that the agent reading the skill before activation has the context to produce a good free-form description. These are read-only reference material for the user-facing entrypoint; the enforcement lives in the workflow's agent step.

### Wheel workflow

**FR-4. A wheel workflow `report-mistake-and-sync` exists at `plugin-kiln/workflows/report-mistake-and-sync.json`**, versioned `1.0.0` on initial release. Follows the same three-step shape as `report-issue-and-sync`:

1. `check-existing-mistakes` — `type: command`
2. `create-mistake` — `type: agent`
3. `full-sync` — `type: workflow`, `terminal: true`

**FR-5. Step 1 (`check-existing-mistakes`, `type: command`)** lists `.kiln/mistakes/*.md` and `@manifest/recent-session-mistakes/` (if present) so the agent step can detect duplicates. Writes to `.wheel/outputs/check-existing-mistakes.txt`. Must use `${WORKFLOW_PLUGIN_DIR}`-style paths if it invokes any script — no `plugin-kiln/scripts/...` repo-relative paths, per the portability rule in `CLAUDE.md`.

**FR-6. Step 2 (`create-mistake`, `type: agent`)** is the single point where the manifest schema is enforced. Its `instruction:` field directs the agent to:

1. Read the workflow activation context for the user's free-form mistake description.
2. Collect every required field from `@manifest/types/mistake.md`:
   - `date` (default: today, ISO 8601)
   - `status` (enum: `unresolved` | `worked-around` | `fixed` | `accepted`)
   - `made_by` (lowercase-kebab model name; inferred from current model ID, user confirms)
   - `assumption` (one sentence, first-person past tense)
   - `correction` (one sentence, first-person present tense)
   - `severity` (`minor` | `moderate` | `major`)
   - `tags` (exactly one `mistake/*`, at least one `topic/*`, at least one stack tag)
   - Title (H1)
3. Collect the five body sections — `What happened`, `The assumption`, `The correction`, `Recovery`, `Prevention for future agents`. Empty sections written as `_none_`, never omitted.
4. Apply the honesty-principle lint (see FR-7).
5. Apply the three-axis tag lint (see FR-8).
6. Resolve the filename slug from the `assumption:` sentence (see FR-9).
7. Write the artifact to `.kiln/mistakes/YYYY-MM-DD-<assumption-slug>.md` using `@manifest/templates/mistake.md` structure. Template-metadata block stripped.
8. Refuse to overwrite existing files — append `-2`, `-3` suffix on collision.
9. Write a confirmation summary to `.wheel/outputs/create-mistake-result.md` listing the filename, assumption, severity, and tags.

**FR-7. Honesty-principle lint is enforced inside the `create-mistake` step:**
- Rejects `assumption:` values containing hedging markers: `may have`, `might have`, `possibly`, `could have`, `somewhat`, `a bit`, `arguably`, `perhaps`.
- Rejects `assumption:` that does not start with `I ` (first-person past).
- Rejects `correction:` that does not start with `I `, `The `, or `It `.
- On failure, the agent re-prompts for that field. No bypass flag in v1.

**FR-8. Three-axis tag lint is enforced inside the `create-mistake` step:**
- Exactly one `mistake/*` tag from the manifest vocabulary (`mistake/assumption`, `mistake/tool-use`, `mistake/scope`, `mistake/context`, `mistake/fabrication`, `mistake/premature-action`, `mistake/communication`). Two allowed only when the mistake genuinely spans classes.
- At least one `topic/*` tag.
- At least one tag matching `language/*`, `framework/*`, `lib/*`, `infra/*`, `testing/*`, or `blockchain/*`.
- On failure, the agent re-prompts for the missing axis.

**FR-9. Filename slug derived from the assumption, not the action.** `<assumption-slug>` is kebab-cased from the `assumption:` sentence, stop-words stripped, truncated to 50 chars. Matches the manifest rule that the slug names the trap future agents should watch for.

**FR-10. Step 3 (`full-sync`, `type: workflow`, `terminal: true`)** invokes `shelf:shelf-full-sync` as a terminal sub-workflow. Identical in shape to how `report-issue-and-sync` chains into `shelf:shelf-full-sync`. After the sub-workflow completes, the outer workflow archives.

### Shelf pickup and proposal flow

**FR-11. `plugin-shelf/workflows/shelf-full-sync.json` is extended to discover `.kiln/mistakes/*.md`** in the same pass that discovers `.kiln/issues/*.md`. The extension lives in `plugin-shelf/scripts/compute-work-list.sh` (or an accompanying script) — invoked via `${WORKFLOW_PLUGIN_DIR}/scripts/...` per the portability rule.

**FR-12. For each new mistake artifact, shelf generates a proposal note and writes it to `@inbox/open/`** via the appropriate MCP server (manifest-scoped or projects-scoped — verification required during `/plan`). Proposal frontmatter: `type: manifest-proposal`, `kind: content-change`, `target: @second-brain/projects/<slug>/mistakes/<filename>`, body calls out "this is a mistake draft" per the workaround path in `@manifest/systems/projects.md`.

**FR-13. Shelf skip-on-unchanged applies.** A `.kiln/mistakes/` file whose content hash matches the prior sync is not re-proposed. Uses the same content-hash strategy as issues/docs already in `update-sync-manifest.sh`.

**FR-14. Once a proposal is accepted (moved out of `@inbox/open/`), shelf does not re-propose it.** The local `.kiln/mistakes/` file is retained for history but marked as "filed" via a sibling state entry (or frontmatter field) to prevent resurrection loops.

### Infrastructure

**FR-15. The skill/workflow pair is registered and discoverable.**
- `plugin-kiln/.claude-plugin/plugin.json` lists the new skill under `skills:` if an explicit listing is maintained (it's currently auto-discovered from the filesystem — confirm during `/plan`).
- `plugin-kiln/workflows/` contains the workflow JSON, portable via `${WORKFLOW_PLUGIN_DIR}` references.
- A local-override copy may be placed at `workflows/report-mistake-and-sync.json` if the consumer wants to customize — same override pattern shelf uses.

**FR-16. The workflow runs cleanly in both the source repo and the installed-plugin cache context** — portability validated per the `plugin-wheel/lib/dispatch.sh` `WORKFLOW_PLUGIN_DIR` export. Smoke-test target: `/wheel:wheel-run report-mistake-and-sync` succeeds end-to-end from a consumer checkout where only the installed plugin cache exists.

## Absolute Musts

1. **Wheel-framework parity with `/report-issue`.** The feature must run on the wheel engine — skill activates workflow, workflow drives steps, shelf sub-workflow handles the terminal Obsidian write. A skill that hand-rolls the capture flow without wheel is a rejection; it would diverge from the established kiln pattern and lose the state-machine / hook-driven properties that make the pipeline auditable.
2. **Tech stack unchanged** — Markdown + Bash + existing kiln plugin + wheel workflow engine + Obsidian MCP. No new dependencies, no new infrastructure.
3. **Manifest conformance is non-negotiable.** If a note the workflow would write fails schema validation, the `create-mistake` agent step refuses to write. No partial-write escape hatches.
4. **Proposal flow only.** The workflow and shelf must never write directly to `@second-brain/projects/<slug>/mistakes/`. The manifest explicitly requires human review.
5. **Honesty-principle linting is mandatory** (FR-7). The entire point of mistake notes is that they aren't hedged. A lint-free draft is worse than no draft.
6. **Plugin portability.** Every workflow command step must use `${WORKFLOW_PLUGIN_DIR}/scripts/...` — no `plugin-kiln/scripts/...` or `plugin-shelf/scripts/...` repo-relative paths. Non-negotiable per `CLAUDE.md`.
7. **Filename slug summarizes the assumption, not the action.** Training-data discoverability rule from the manifest; easy to get wrong.

## Tech Stack

Inherited from the kiln plugin. No additions.

- **Skill**: `plugin-kiln/skills/mistake/SKILL.md` — Markdown, thin wheel-activation entrypoint.
- **Workflow**: `plugin-kiln/workflows/report-mistake-and-sync.json` — JSON, three steps (command → agent → workflow). Same shape as `report-issue-and-sync.json`.
- **Shelf extension**: `plugin-shelf/scripts/compute-work-list.sh` (extended) or sibling script for `.kiln/mistakes/` discovery. `plugin-shelf/workflows/shelf-full-sync.json` gains one additional work-list target. All script invocations via `${WORKFLOW_PLUGIN_DIR}/scripts/...`.
- **Engine**: unchanged `plugin-wheel/lib/dispatch.sh` (post-`005e259` portability fix is a hard prerequisite).
- **MCP**: Obsidian tools (`mcp__obsidian-projects__*` or `mcp__claude_ai_obsidian-manifest__*` depending on which scope has write access to `@inbox/open/` — resolved in `/plan`).

## Impact on Existing Features

- **`/report-issue` and `report-issue-and-sync` workflow** — unchanged. Sibling skill + workflow; the two pairs coexist and share the same `shelf:shelf-full-sync` terminal step.
- **`plugin-kiln/workflows/`** — gains `report-mistake-and-sync.json`. Currently only holds `report-issue-and-sync.json`.
- **Wheel engine** — no changes. The existing `plugin-wheel/lib/dispatch.sh` (with the `WORKFLOW_PLUGIN_DIR` export added in `005e259`) is sufficient to host the new workflow.
- **`.kiln/` directory convention** — gains a new `mistakes/` subdirectory alongside `issues/`, `logs/`, `qa/`.
- **`plugin-shelf/workflows/shelf-full-sync.json`** — gains a new discovery path (`.kiln/mistakes/*.md`) and a new write-target (`@inbox/open/`). The `compute-work-list.sh` script is extended; the `obsidian-apply` agent step gains proposal-file writes.
- **Shelf templates (`plugin-shelf/templates/`)** — unchanged. This feature uses the manifest-level template at `@manifest/templates/mistake.md` as the source of truth. Shelf does not fork it.
- **`.wheel/outputs/`** — new step outputs (`check-existing-mistakes.txt`, `create-mistake-result.md`) land here during a run. No permanent state; cleared per the existing wheel conventions.
- **Dashboard rollup in `<project>/<project>.md`** — out of scope for this feature, but the manifest spec calls for a `## Mistakes` Dataview section parallel to `## Decisions`. Implementation of that rollup is a downstream change tracked separately.
- **Existing sync steady-state** — one additional MCP write per new mistake (proposal create). Zero if no new mistakes. Does not regress the "zero MCP writes on no-change sync" goal already in flight for shelf.

## Success Metrics

1. **Schema-conformance rate ≥80% on first try.** Of mistake notes produced by the workflow in the first month, ≥80% pass manifest validation (three-axis tags present, required fields filled, filename format correct, honesty lint clean) without re-prompting. Measured by parsing `.kiln/mistakes/` against the manifest schema.
2. **Zero direct writes to `<project>/mistakes/`.** Over the first month, every note that lands in `@second-brain/projects/ai-repo-template/mistakes/` arrived via the `@inbox/open/` proposal path. Measured by spot-checking file-creation source in the Obsidian audit log.
3. **End-to-end round trip ≤7 days for the first real mistake.** The first actual mistake captured in this repo moves from `/kiln:mistake` invocation → wheel activation → `.kiln/mistakes/` write → `shelf:shelf-full-sync` → `@inbox/open/` proposal → accepted/merged into `<project>/mistakes/` within a week of the feature landing. Proves the whole wheel-driven pipeline works on a real note, not a fixture.
4. **Workflow state hygiene.** Every `/kiln:mistake` run produces exactly one state file in `.wheel/history/success/` (or `.wheel/history/failure/` on error); zero orphaned state files in `.wheel/state_*.json` after completion. Measured after 10 runs.

## Risks / Unknowns

- **The honesty-lint heuristic is blunt.** Hedge-word detection will have false positives (someone may legitimately need to say "I assumed X might happen"). Mitigation: keep the wordlist short in v1 and iterate. False-positive friction is the lesser evil compared to letting hedged notes through.
- **Shelf's proposal write path to `@inbox/open/` may cross vault/MCP boundaries.** `@inbox/open/` lives in the same vault as `@second-brain/projects/` but the MCP scopes may differ (`obsidian-projects` vs. `obsidian-manifest`). Needs verification during `/plan` — if the scopes differ, the workflow needs to route through whichever MCP has write access to `@inbox/`.
- **Re-sync loops if the maintainer moves a proposal out of `@inbox/open/`.** Without state tracking (FR-12), shelf could re-propose. Mitigation is in the FR but needs implementation care.
- **Model ID detection for `made_by`.** The skill needs to know which model is running it. Inferring from environment may be fragile; default-then-confirm is safer.
- **Filename slug derivation is a prompt-engineering exercise.** "Summarize the assumption, not the action" is subtle; the skill may need an LLM call to generate a good slug rather than a naive kebab-cased substring. Acceptable v1: naive slugger with a user confirm step.

## Assumptions

- The manifest's mistake type, template, and system spec are stable — the v1 schema in `@manifest/types/mistake.md` (last_updated 2026-04-16) won't change under us during implementation.
- `@inbox/open/` is writable via an available MCP server. If not, the proposal write must fall back to a local file the user hand-files.
- Shelf-full-sync is the correct delivery mechanism (i.e., the rewired `/shelf:shelf-sync` skill or the direct workflow run). If the skill rewire is still pending when this feature ships, the user runs `/wheel:wheel-run shelf-full-sync` manually — acceptable for v1.
- Contributors invoking `/kiln:mistake` have enough session context to answer the required prompts accurately. If they don't, the correct behavior is to skip the capture, not to produce a hedged note.

## Open Questions

1. Should the skill auto-prefill `made_by` from the runtime model ID, or always ask? Auto-prefill is faster but masks the one field where ground truth is available.
2. Where does `.kiln/mistakes/` fit into the existing `.kiln/` directory conventions in `CLAUDE.md`? Should mistakes be listed alongside issues in the "active work surfaces" section, or kept separate?
3. Should the skill support `--from-transcript <path>` as a non-v1 flag placeholder, documenting the retroactive-capture path even though v1 doesn't implement it? Or leave transcript-capture entirely out until a separate feature?
4. Severity calibration guidance is long (the whole `## Severity` section of `@manifest/types/mistake.md`). Does the skill inline all of it, link to it, or show a condensed one-liner per level? Inline is robust but bloats SKILL.md.
5. For the `mistake/*` tag picker, should the skill offer the seven-item vocabulary as a multiple-choice prompt, or free-text with post-validation? Multiple-choice is lower-friction but forecloses on edge cases.
