# Feature PRD: Structured Roadmap Planning Layer

## Parent Product

Parent product: **kiln** (`@yoshisada/kiln`) — the spec-first Claude Code plugin that provides 4-gate workflow enforcement, PRD-driven pipelines, and integrated QA/debugging agents. Parent PRD at `docs/PRD.md` (currently empty template — kiln's product context is effectively documented across `CLAUDE.md` and the many feature PRDs under `docs/features/`).

## Feature Overview

Replace the current `/kiln:kiln-roadmap` one-liner scratchpad with a structured product-planning layer rooted at `.kiln/vision.md` and `.kiln/roadmap/`. The new system captures **product intent** — what the product should become and why — in a shape that `/kiln:kiln-distill` can consume alongside feedback and issues to produce PRDs proactively rather than reactively.

Core mental model: **roadmap is product intent (multi-feature, phased, forward-looking), specs are engineering contracts (per-feature, activated when distill promotes a feature)**. Roadmap items become specs; they do not duplicate specs. This framing is the load-bearing distinction that prevents the roadmap from turning into a second source of truth for engineering.

## Problem / Motivation

Today there is no structured place to record product direction:

- `/kiln:kiln-roadmap` is a scratchpad — appends one-liner bullets to a single `.kiln/roadmap.md` file under four fixed theme groups, with no dedup, no frontmatter, no status, no dependencies, and no consumer.
- `/kiln:kiln-distill` currently ingests feedback and issues only. Every PRD is reactive (to friction/strategy corrections). There is no way to say "build toward this product vision."
- There is no home for adjacent concepts: goals that span features, research tracks that must complete before building, constraints/non-goals that document decisions, milestones that mark phase completion, and — most importantly — **critiques we want to prove wrong** (e.g., "kiln uses too many tokens," "kiln produces unauditable code," "kiln requires too much setup"). These shape the product more than any one-off feature, but the current system has no slot for them.
- The user has repeatedly said "I have a feature idea" and found nowhere structured to put it. The result is that product-direction thinking lives in memory or scattered Obsidian notes, and distill runs without any forward-looking signal.

This feature fixes that: one capture surface, one structured store, one consumer (distill), one Obsidian mirror.

## Goals

1. Provide a living **vision** document that anchors product direction and is updated as thinking evolves.
2. Provide a **phased roadmap** where phases have explicit status (planned | in-progress | complete) and bundle items.
3. Provide **typed items** (feature, goal, research, constraint, non-goal, milestone, critique) under a single schema with a `kind:` field — one file per item, rich frontmatter.
4. Provide an **adversarial interview mode** for capture that pushes back on thin ideas, captures implementation hints, and places the item in the right phase using current repo state as context.
5. Extend **`/kiln:kiln-distill`** to pull from three streams (items, feedback, issues), with phase and critique filters so the user can focus cycles on "current phase" or "everything that addresses critique X."
6. Mirror every roadmap document to Obsidian using `.shelf-config` so roadmap state is visible alongside issues and fixes in the project vault.
7. Bootstrap the system with real content (user-named critiques and a migration of the existing `.kiln/roadmap.md`) so it ships with signal, not an empty feature.

## Non-Goals

- **Review-cadence / staleness nagging** — not in v1. A future item ("flag items not touched in N weeks") can be added once the system has enough content to rot.
- **Retrospective loop** — the closure side of critiques (mark a critique `disproved` after a proof-path-addressing feature ships) is explicitly out of v1 and will itself be captured as a `kind: feature` in the roadmap on first run. This is intentional dogfooding: the first cycle of the new system will feel the gap and naturally prioritize the fix.
- **Cross-project roadmap view** — single-repo scope for v1. A cross-repo rollup is a future item.
- **GitHub issue sync** — roadmap items live in `.kiln/roadmap/` and Obsidian; they do NOT auto-file to GitHub.
- **Human-time or T-shirt effort estimation** — explicitly excluded. AI builds these, so human-day or S/M/L/XL estimates are meaningless. Sizing is AI-native (blast_radius + review_cost + context_cost) only.
- **Automated proof_path measurement** — critiques carry a `proof_path` as descriptive text in v1. Automated measurement of proof paths (e.g., tracking token cost across runs) is a future item.

## Target Users

Primary user: the kiln product owner (solo dev) who wants to steer the product direction over time and have that steering show up in the next PRD rather than live only in their head. Same persona as the existing `/kiln:kiln-feedback` and `/kiln:kiln-report-issue` users — this feature adds the third and highest-altitude capture surface.

## Core User Stories

1. **Capture a feature idea with context-aware placement** — The user types `/kiln:kiln-roadmap add a way to batch-process X`. The skill reads vision + phases + existing items, auto-detects `kind: feature`, and interviews adversarially: what's the hardest part, what are you assuming, what dependencies exist, is there a cheaper version. It places the item in the right phase and records implementation hints that will flow into the PRD later.

2. **Record a critique and let it steer work** — The user types `/kiln:kiln-roadmap kiln uses too many tokens compared to doing it by hand`. The skill auto-detects `kind: critique`, asks for a `proof_path` (what ships/measures would invalidate this critique), and links the critique so that later features/goals can reference it. The user can then tell distill: "this cycle, bundle everything that addresses the token-cost critique," and distill produces a PRD that actively proves the critique wrong.

3. **Quick capture without the interview** — The user is in a hurry and types `/kiln:kiln-roadmap --quick some idea I want to not forget`. The skill writes a stub item in the `unsorted` phase with `status: planned` and no interview. The user returns later to place and flesh it out.

4. **Update the vision** — The user types `/kiln:kiln-roadmap --vision` and walks through a short interview that updates `.kiln/vision.md`. The skill shows the current vision, asks what's changed, and writes the update. Obsidian mirror is patched.

5. **Distill across streams with filters** — The user runs `/kiln:kiln-distill --phase current` or `/kiln:kiln-distill --addresses token-cost-critique`. Distill bundles matching features + feedback + issues into a themed PRD. Features supply the forward-looking backbone, feedback shapes the narrative, issues populate the tactical FR layer.

## Functional Requirements

### Directory layout

- **FR-001** — On first run, create `.kiln/vision.md` from a template (if missing) with a short prompt for the user to fill in. The template follows a prescribed 7-slot schema so downstream consumers (notably the CLAUDE.md audit's `## Product` sync — see `docs/features/2026-04-24-claude-md-audit-reframe/PRD.md` FR-022–FR-029) can rely on a predictable shape:
  1. **One-line product summary** — what this product is, in one sentence.
  2. **Primary target user** (optional secondary) — persona, not just demographics.
  3. **Top 3 jobs-to-be-done** — what users hire this product to do.
  4. **Non-goals** — explicit "what this product is NOT."
  5. **Current phase** — one of: `pre-launch | early-access | maturing | mature | end-of-life`. Shapes how tradeoffs should be weighed this quarter.
  6. **North-star metric / success shape** — the one thing you'd move if you could only move one.
  7. **Key differentiator** — what this product does that alternatives don't.
  Each slot gets its own `## <slot>` heading so the audit can grade slot-level completeness. Slots may be marked `N/A` with a reason; empty slots fire `product-slot-missing` findings from the audit.
- **FR-001a** — `.kiln/vision.md` supports optional CLAUDE.md-sync region markers. If the file has `<!-- claude-md-sync:start -->` ... `<!-- claude-md-sync:end -->` fences, only content inside the fence is mirrored into CLAUDE.md's `## Product` section. If no fences are present, the whole file is mirrored (subject to FR-028 of the audit PRD — top-level `#` is demoted, slot `##` headings demoted to `###`). Fences let authors maintain a lean "hot" summary for per-turn Claude context while keeping a richer deep-dive document for humans. No behavior change for roadmap consumers — distill reads the full file regardless of fences.
- **FR-002** — On first run, create `.kiln/roadmap/` tree:
  - `.kiln/roadmap/phases/` — one file per phase (e.g., `foundations.md`, `current.md`, `next.md`, `later.md`, `unsorted.md`). `unsorted.md` is pre-created as the default landing spot for `--quick` captures and migration output.
  - `.kiln/roadmap/items/` — one file per item, named `<YYYY-MM-DD>-<slug>.md`.
- **FR-003** — All created files mirror to Obsidian using `.shelf-config` base_path + slug. Path shape:
  - `.kiln/vision.md` → `<base_path>/<slug>/vision.md` (patch_file on updates, create_file on first write)
  - `.kiln/roadmap/phases/<phase>.md` → `<base_path>/<slug>/roadmap/phases/<phase>.md`
  - `.kiln/roadmap/items/<id>.md` → `<base_path>/<slug>/roadmap/items/<id>.md`
- **FR-004** — Obsidian path composition reads `.shelf-config` directly (no vault discovery). This feature depends on blocker issue `2026-04-23-write-issue-note-ignores-shelf-config` being fixed first.

### Phase file schema

- **FR-005** — Phase frontmatter (required): `name`, `status` (`planned | in-progress | complete`), `order` (integer — lower is earlier), `started` (ISO date, optional), `completed` (ISO date, optional).
- **FR-006** — Phase body: short description, plus a bulleted list of item-ids assigned to the phase (maintained by the roadmap skill; not hand-edited).

### Item file schema

- **FR-007** — Item frontmatter (required): `id` (`<YYYY-MM-DD>-<slug>`), `title`, `kind`, `date`, `status`, `phase`, `state` (promotion lifecycle — see FR-015).
- **FR-008** — Item frontmatter (required sizing — AI-native only): `blast_radius` (`isolated | feature | cross-cutting | infra`), `review_cost` (`trivial | moderate | careful | expert`), `context_cost` (free-text rough estimate, e.g. "1 session", "3 sessions", "one-shot"). Human-time and T-shirt fields are **not permitted** by schema.
- **FR-009** — Item frontmatter (optional): `depends_on: [<item-id>, ...]`, `addresses: [<critique-id>, ...]`, `implementation_hints` (free-text — captured during feature interviews; flows into PRD when distill promotes the item).
- **FR-010** — `kind` is one of: `feature` (capability to build), `goal` (outcome, may span features), `research` (bounded investigation), `constraint` (we will do X), `non-goal` (we will not do X, with rationale), `milestone` (phase-completion marker), `critique` (criticism to disprove).
- **FR-011** — `kind: critique` items carry a required `proof_path` field (free-text — what would need to ship or measure to invalidate this critique). Critique `status` lifecycle: `open | partially-disproved | disproved`.
- **FR-012** — Items do not get auto-deleted. When a phase completes or a feature ships, items stay on disk (status updated) so the history is auditable.

### Capture skill (`/kiln:kiln-roadmap`)

- **FR-013** — `/kiln:kiln-roadmap <description>` launches the interview. The skill first reads `.kiln/vision.md`, all `.kiln/roadmap/phases/*.md`, and all `.kiln/roadmap/items/*.md` to build context.
- **FR-014** — **Cross-surface routing**: before any within-roadmap classification, the skill inspects the description and decides whether it belongs in a different capture surface. Heuristic:
  - Tactical framing ("X is broken / slow / wrong / crashes / hangs / doesn't work") → offer to route to `/kiln:kiln-report-issue`.
  - Strategic framing ("we should / the product should / direction / mission / architecture" without a concrete thing-to-build) → offer to route to `/kiln:kiln-feedback`.
  - Product-intent framing ("build X / add X / investigate X / prove X wrong / we will not do X") → stay in roadmap.
  When the match is ambiguous, the skill presents all three options and asks the user to pick — it NEVER silently re-routes. If the user confirms roadmap, proceed to FR-014a.
- **FR-014b** — **Hand-off actually invokes the target skill**. When the user picks `/kiln:kiln-report-issue` or `/kiln:kiln-feedback` at the routing prompt, the roadmap skill invokes the target skill (via the `Skill` tool) with the original description as its argument and then exits. It MUST NOT merely print "go run X instead" — that's a dead-end UX. The invocation is equivalent to the user having typed `/kiln:kiln-report-issue <description>` or `/kiln:kiln-feedback <description>` directly.
- **FR-014a** — After cross-surface routing confirms roadmap, the skill auto-detects `kind` from the description where possible (critique-like phrasing → critique; "investigate/research X" → research; "we will not X" → non-goal; default → feature). If ambiguous, ask the user to pick.
- **FR-015** — Interview is adversarial per kind. For `feature`: "what's the hardest part? what are you assuming? what dependencies exist? is there a cheaper version? what breaks if a dependency isn't ready?" For `critique`: "who would make this claim? what's the proof_path? what items would address it?" For `research`: "what's the decision this unblocks? what's the time-box?" Etc.
- **FR-016** — Interview places the item in a phase (`current`, `next`, `later`, `unsorted`) using existing phase content as context. User can override.
- **FR-017** — Interview captures AI-native sizing (blast_radius, review_cost, context_cost) — NEVER asks for human-time or T-shirt sizes.
- **FR-018** — `--quick` flag (or auto-detect short input / non-interactive sessions) skips the interview. The item is written with `phase: unsorted`, `state: planned`, and minimal frontmatter; the body is the raw description. User is told to return later to flesh it out.
- **FR-018a** — **Multi-item input handling**. If the description contains multiple distinct items (detected by: bullet lists, numbered lists, "and also / plus / as well as" conjunctions between concrete thing-to-build phrases, newline-separated sentences that each parse as an item), the skill asks the user up front: "I see N items in this description — handle as (a) N separate roadmap items, (b) one bundled item with sub-points, or (c) let me split them and you review?" Default is (a). If the user picks (a) or (c), the skill runs the capture flow once per item — one file per item — matching the existing `/kiln:kiln-feedback` and `/kiln:kiln-report-issue` policy. If (b), a single item is written with the full description preserved in the body.
- **FR-018b** — Multi-item splits share context: the skill runs the phase-assignment interview ONCE up front (asking which phase the batch belongs to) rather than re-asking per item, unless the user explicitly wants per-item placement. This keeps bulk capture cheap while preserving one-file-per-item storage.
- **FR-018c** — **Follow-up loop**. After each item (or batch) is written and confirmed, the skill asks "anything else on your mind?" If the user responds with another description, the skill loops back to FR-014 (cross-surface routing) and captures it — possibly routing to `/kiln:kiln-report-issue` or `/kiln:kiln-feedback` if the follow-up is tactical or strategic. The loop continues until the user says no / exits. On exit, the skill prints a session summary: count of items captured per surface (e.g., "captured 3 roadmap items, 1 issue, 1 feedback this session") with paths. The follow-up prompt is skipped entirely in `--quick` mode and in non-interactive sessions.
- **FR-019** — `/kiln:kiln-roadmap --vision` launches a short interview that updates `.kiln/vision.md`. Shows current vision, asks what has changed, writes the update, patches the Obsidian mirror.
- **FR-020** — `/kiln:kiln-roadmap --phase <action>` supports phase management: mark a phase `in-progress` (only one phase may be `in-progress` at a time), mark `complete`, create a new phase with ordering.

### Promotion lifecycle

- **FR-021** — Items carry a `state` field independent of kind: `planned | in-phase | distilled | specced | shipped`. Transitions:
  - `planned` → `in-phase`: when phase activates (phase status becomes `in-progress`) and item is assigned to it. Automatic.
  - `in-phase` → `distilled`: when `/kiln:kiln-distill` picks the item into a PRD. Automatic, written by distill.
  - `distilled` → `specced`: when `/specify` runs for a distilled item. Automatic, written by specify.
  - `specced` → `shipped`: when the PR implementing the item merges. Manual or hook-driven (out of v1 — can remain manual).
- **FR-022** — State transitions are explicit — no item ends up in limbo. The roadmap skill ships a `--check` flag that reports any items whose `state` is inconsistent with their `phase` / spec / PR status.

### Distill integration

- **FR-023** — `/kiln:kiln-distill` is extended to ingest `.kiln/roadmap/items/*.md` as a third input stream alongside `.kiln/feedback/` and `.kiln/issues/`.
- **FR-024** — Distill's narrative is led by feedback (as today) but now also by **features** from the current phase — the PRD's Background/Goals sections lean on roadmap features when present.
- **FR-025** — Distill supports filters: `--phase <name>` (default: current), `--addresses <critique-id>` (bundle everything that advances a critique), `--kind <kind>` (e.g., bundle only research items).
- **FR-026** — When distill promotes an item, it writes `state: distilled` to the item file and links the generated PRD via a `prd:` field (same pattern as feedback items).
- **FR-027** — `implementation_hints` from items flow into the generated PRD's "Implementation Hints" / "Known Unknowns" section — no re-elicitation.

### Migration

- **FR-028** — On first run, if `.kiln/roadmap.md` (legacy) exists: parse the existing bullets into `kind: feature` items with `phase: unsorted`, write each as an item file, archive the legacy file to `.kiln/roadmap.legacy.md`. User is shown a count and told to run `/kiln:kiln-roadmap --reclassify` to walk the unsorted items through the interview.
- **FR-029** — Bootstrap with **seed critiques** named by the product owner: "kiln uses too many tokens compared to doing it by hand," "kiln produces unauditable buggy code," "kiln requires too much setup." Each gets a pre-filled `proof_path` that the user can edit. This ensures the critique mechanism ships with real content the first day.

### Obsidian sync

- **FR-030** — All create/update operations on roadmap files dispatch to a new `shelf:shelf-write-roadmap-note` helper that follows the existing `shelf-write-issue-note` pattern but writes to the `roadmap/` subtree. The helper composes paths from `.shelf-config` (FR-004) — no discovery.
- **FR-031** — Vision updates use Obsidian's `patch_file` (frontmatter-preserving) so the Obsidian mirror doesn't churn on small edits.

## Absolute Musts

1. **Tech stack match with existing kiln plugin**: Markdown skill definitions, Bash inline commands, Obsidian MCP (`mcp__claude_ai_obsidian-projects__*`), `.shelf-config` for path composition. No new runtime dependencies.
2. **`.shelf-config`-reading shelf helpers** (blocker issue `2026-04-23-write-issue-note-ignores-shelf-config`) must be fixed first — roadmap sync cannot ship with guessed vault paths.
3. **AI-native sizing only** — schema explicitly forbids human-time fields. This is load-bearing; if it creeps back in, the whole sizing system is meaningless.
4. **Specs-vs-roadmap separation** — roadmap items describe *product intent*; specs describe *engineering contracts*. The promotion lifecycle is the only bridge. No duplication of spec content in items.
5. **One capture surface** — all item kinds (feature, goal, research, constraint, non-goal, milestone, critique) go through `/kiln:kiln-roadmap`, not separate skills. One skill, one interview, one store.
6. **Cross-surface routing is confirm-never-silent** — when the roadmap skill detects that a description belongs in `/kiln:kiln-report-issue` or `/kiln:kiln-feedback`, it MUST ask the user to pick rather than silently re-routing. Silent re-routing breaks the user's mental model of where their words went.

## Tech Stack

Inherited from parent kiln plugin — no additions:
- Markdown (skill definitions, templates, stored artifacts)
- Bash 5.x (inline commands within skills)
- `jq` (frontmatter parsing where needed)
- Obsidian MCP (`mcp__claude_ai_obsidian-projects__create_file` / `patch_file`)
- `.shelf-config` key-value file for path composition
- Distill is an existing skill being extended — no new infra

## Impact on Existing Features

- **`/kiln:kiln-roadmap`**: replaced. The old single-file append behavior is removed. Legacy `.kiln/roadmap.md` is parsed and archived (FR-028).
- **`/kiln:kiln-distill`**: extended. New input stream + new filter flags. Existing feedback+issues behavior is unchanged when no items exist.
- **`/kiln:kiln-next`**: should surface `state: in-phase` items from the current phase as candidates for what to work on next. Small update, same skill.
- **`shelf:`**: new `shelf-write-roadmap-note` helper. Requires the `.shelf-config`-reading fix from issue `2026-04-23-write-issue-note-ignores-shelf-config` (blocker).
- **`/specify`**: when run against a distilled item, should update the item's `state: specced`. One-line update, same skill.

No breaking changes to existing PRDs, feedback files, or issue files. Those capture surfaces and consumers are untouched.

## Alignment with In-Flight Direction

This redesign explicitly pairs with recent feedback entries that the product owner has already logged, so the implementer has the full context:

- `2026-04-23-we-need-to-move-more-plugins.md` — agents and primitives migrating to wheel
- `2026-04-23-all-agents-should-live-in.md` — all agents centralize in wheel
- `2026-04-23-we-should-add-a-way.md` — distill supporting multiple themed PRDs in sequence (natural fit with phase/critique filters)
- `2026-04-23-i-think-we-need-to.md` — whole-repo cleanup / structure improvements (paired concern: `.kiln/` tree is getting richer)

## Success Metrics

1. **Capture coverage**: 100% of new product-direction ideas land as structured items (measured by: no new one-liner bullets appearing anywhere else; `.kiln/roadmap/items/` is the only destination).
2. **Distill uses items**: Within one cycle of shipping, every `/kiln:kiln-distill` run that has items in the current phase produces a PRD that references ≥1 item by id (measured by grep of distilled PRD output).
3. **Critique graduation path works**: At least one seed critique transitions from `open` → `partially-disproved` after a feature that references it via `addresses:` ships (validates the end-to-end proof_path flow, even though the retrospective loop is manual in v1).
4. **Obsidian parity**: Every file in `.kiln/roadmap/` and `.kiln/vision.md` has a corresponding Obsidian note (measured by listing both trees and diffing).

## Risks / Unknowns

- **Interview fatigue**: if the adversarial interview is too long, users will always use `--quick` and we're back where we started. Mitigation: keep the per-kind interview to ≤5 questions, allow skipping any question, and respect short-input auto-detection for the quick path.
- **Duplication with `specs/`**: if roadmap items drift into containing engineering detail, they start to compete with specs. Mitigation: schema forbids tech-implementation fields on items except `implementation_hints` (explicitly marked as hints, not contracts). Distill is the only bridge.
- **Critique proof_path subjectivity**: "what would invalidate this critique?" is a judgment call. v1 accepts descriptive text; future work may introduce measurable proof_paths tied to telemetry.
- **`.shelf-config` blocker dependency**: this feature cannot ship until issue `2026-04-23-write-issue-note-ignores-shelf-config` is fixed, because roadmap mirroring needs deterministic path composition. The blocker is small — but it IS a blocker.
- **Migration edge cases**: existing `.kiln/roadmap.md` entries may be too terse to classify well. Mitigation: dump them all to `unsorted` and require `--reclassify` interview to promote; don't guess.

## Assumptions

- The product owner is a solo dev who interacts with kiln via Claude Code chat, not a web UI.
- `.shelf-config` is the canonical mapping from repo → Obsidian project, and the blocker fix will make all shelf helpers read it.
- `/kiln:kiln-distill` is the one-and-only consumer of roadmap items — no other skills walk the roadmap tree.
- The Obsidian vault is the "nice-to-have" mirror; `.kiln/` on disk is the source of truth. If Obsidian is unavailable, the roadmap still works (just without the mirror).

## Open Questions

1. Should `--vision` interview run only when explicitly requested, or should it auto-trigger (once every N runs, or when a phase completes)? v1 proposal: explicit only.
2. Should `state: shipped` transitions be hook-driven (post-merge) or manual? v1 proposal: manual; hook is a future item.
3. Should critiques that transition to `disproved` be archived out of the active roadmap listing, or stay inline for historical context? v1 proposal: stay inline with a visible `status: disproved` marker.
4. Is there a case for **multi-phase membership** (an item belongs to two phases)? v1 proposal: no — one phase per item. Cross-phase bundling is a distill-level concern via `--addresses`.
