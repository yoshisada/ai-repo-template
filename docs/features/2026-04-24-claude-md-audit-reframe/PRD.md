# Feature PRD: CLAUDE.md Audit Reframe — Product-Focused Content + Plugin Guidance Sync

## Parent Product

Parent product: **kiln** (`@yoshisada/kiln`). This feature modifies the `kiln-claude-audit` skill, adds a new convention (`.claude-plugin/claude-guidance.md`) to the kiln plugin template, and introduces a plugin-guidance sync behavior. Parent PRD at `docs/PRD.md`.

## Supersedes

This PRD supersedes the thin open issue `.kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md`. That issue's verbatim body ("claude md audit does not take into account project context") is the seed; this PRD is the full design that came out of a follow-up design session. On merge, mark the issue `status: prd-created` and link this PRD.

## Feature Overview

Reframe what `/kiln:kiln-claude-audit` is auditing for, and add a plugin-guidance sync mechanism that removes the need to write or maintain `## Plugins`-style sections in CLAUDE.md by hand.

Three changes, working together:

1. **Content philosophy** — CLAUDE.md should describe **product + feedback-loop narrative + convention rationale**, not enumerate plugin surface (skills, agents, hooks, commands). Claude already receives those via runtime context; duplicating them in CLAUDE.md is token waste and a drift risk.
2. **Rule classes** — the audit rubric gains four new rule classes that grade content against the reframed philosophy (enumeration detection, benefit-narrative coverage, feedback-loop completeness, hook/claim consistency), while keeping the existing bloat/duplication rules.
3. **Plugin-guidance sync** — each plugin ships a short `.claude-plugin/claude-guidance.md` file that explains "when / why Claude should reach for this plugin." The audit collects guidance from enabled plugins only and maintains a `## Plugins` section in CLAUDE.md via proposed diff. Plugins without a guidance file are skipped silently.

## Problem / Motivation

The current `/kiln:kiln-claude-audit` is a **drift reducer**, not a **coverage checker**. Its seven rules (`load-bearing-section`, `stale-migration-notice`, `recent-changes-overflow`, `active-technologies-overflow`, `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`) all detect **bloat or staleness** — they flag content that shouldn't be there. They do not detect:

- Content that **should** be there but isn't (coverage gap).
- Enumerations that exist in CLAUDE.md but are **already available to Claude via runtime context** (skill lists, agent inventories, command catalogs) — duplicating them wastes tokens every turn and creates drift when names change.
- Convention sections that describe **what** a rule does but not **why** — Claude can follow a rule with a rationale but will drift on one without.
- **Feedback-loop narrative** — the compound benefit of capturing issues, feedback, roadmap items, mistakes. Without this, Claude treats capture surfaces as isolated tools and makes judgment calls that bypass them.
- **Hook / claim drift** — CLAUDE.md says "hooks block X" but the hook code no longer enforces X. Worse than missing content; it's actively wrong.

Additionally, today there's no standardized way for plugin authors to provide Claude-facing "when/why use this plugin" guidance. The `plugin.json` `description` field is UI-only (shown in the plugin manager). The result is that consumer CLAUDE.md files either (a) lack plugin context entirely, or (b) contain hand-rolled plugin descriptions that drift out of sync with the plugins themselves.

Anthropic's own best-practices documentation reinforces this direction: it explicitly discourages enumerating things that "change frequently" and says to "use skills instead" for domain-specific workflows that Claude can load on demand. Our reframe is aligned with their guidance, not diverging from it.

## Goals

1. **Content philosophy codified** — the rubric classifies every section as `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified` and treats only the first three as keep-by-default.
2. **Enumeration bloat removed** — sections that re-enumerate skills/agents/commands/hooks are flagged for removal because Claude already has that information at runtime.
3. **Benefit narrative surfaced** — every workflow/convention in CLAUDE.md must have a one-line "why this matters" explanation. Plain rules without rationale are flagged for expansion.
4. **Feedback-loop continuity** — if the repo has capture surfaces (feedback, issues, roadmap, mistakes, retros), CLAUDE.md must describe how they connect and what's gained by using them.
5. **Hook/claim consistency** — assertions in CLAUDE.md ("hooks block X") are checked against actual hook code.
6. **Plugin guidance sync** — each enabled plugin's `.claude-plugin/claude-guidance.md` contents are gathered and reconciled with the `## Plugins` section in CLAUDE.md. No manual editing of plugin content in CLAUDE.md.
7. **External alignment documented** — the PRD and audit output cite Anthropic's best-practices page as the external rubric anchor; the custom `claude-guidance.md` convention is explicitly called out as kiln-specific with a migration path if Anthropic later ships an official field.

## Non-Goals

- **Automatic edits to CLAUDE.md** — the audit continues to propose diffs only. Human review and `git apply` remain the application path.
- **Enforcement of enumeration removal** — the rubric flags plugin-surface sections for removal, but the user can override per-section (see FR-017). We do not mandate removal.
- **Rewriting the consumer's CLAUDE.md from scratch** — the audit reconciles existing content against the new rules; it does not regenerate CLAUDE.md from templates.
- **Inventing a plugin.json field** — we do NOT add a `claudeGuidance` string to `plugin.json`. Markdown file is richer, version-controlled with the plugin, and won't collide with future Anthropic fields.
- **Migrating CLAUDE.md to a fixed section order** — we do not mandate section ordering. Humans can arrange CLAUDE.md however they like; the audit only grades content, not layout.
- **Pulling guidance from all globally-installed plugins** — only enabled plugins (project `.claude/settings.json` + user `~/.claude/settings.json` union) are considered. Plugins installed but disabled are ignored.
- **Per-plugin CLAUDE.md files as a plugin capability** — we are NOT making plugins ship full CLAUDE.md contributions, only short guidance snippets destined for one managed `## Plugins` section.
- **Semantic sync / LLM-based plugin guidance reconciliation** — the sync is a straightforward text replacement of the `## Plugins` section. It does not LLM-rewrite the guidance to match the surrounding CLAUDE.md voice.

## Target Users

- **Plugin authors** (maintainers of kiln, shelf, wheel, clay, trim, and future plugins) — they own their plugin's `claude-guidance.md` and update it when the plugin's role shifts.
- **Consumers** of kiln-enabled repos — their CLAUDE.md stays accurate with minimal manual effort.
- **Kiln maintainers** — they own the rubric and the sync logic. The rubric lives at `plugin-kiln/rubrics/claude-md-usefulness.md` and the sync is inside the existing `kiln-claude-audit` skill.

## Core User Stories

1. **Consumer runs audit after installing a new plugin** — A user installs `shelf` in their repo. They run `/kiln:kiln-claude-audit`. The audit detects shelf is enabled, reads `shelf/.claude-plugin/claude-guidance.md`, and proposes a diff that adds a new entry under `## Plugins` in CLAUDE.md with shelf's guidance text. The user reviews and applies.

2. **Consumer removes a plugin** — A user disables `trim`. They run `/kiln:kiln-claude-audit`. The audit detects trim is no longer enabled and proposes a diff that removes trim's entry from `## Plugins`. No stale content lingers.

3. **Plugin author updates guidance** — The kiln maintainer rewrites `plugin-kiln/.claude-plugin/claude-guidance.md` to reflect kiln's new feedback-loop philosophy. Downstream consumers running the audit see a proposed diff that updates kiln's entry in their `## Plugins` section. The plugin-author-to-consumer feedback cycle is automatic.

4. **Enumeration drift is flagged** — A consumer's CLAUDE.md has a section `## Available Commands` that lists every kiln skill. The audit flags the entire section for removal with action `enumeration-bloat` and rationale "Claude receives the available-skills list at runtime; re-enumerating it duplicates context and drifts on rename."

5. **Benefit narrative missing** — CLAUDE.md's convention section says "Every PR must have a spec + plan + tasks." The audit flags this with `benefit-missing`: the rule has no "why" line. User adds a short rationale ("because un-specced features produce code that drifts from intent and can't be audited") and re-runs; flag clears.

6. **Hook claim is stale** — CLAUDE.md says "the version-increment hook bumps the 4th segment on every edit." A refactor removed that hook. The audit runs `hook-claim-check`, scans hooks directory, and flags the claim as contradicted. The diff proposes either removing the claim or pointing to the replacement.

7. **Feedback-loop narrative is incomplete** — Repo has `.kiln/issues/`, `.kiln/feedback/`, and soon `.kiln/roadmap/`. CLAUDE.md describes `/kiln:kiln-report-issue` but never explains that issues feed into `/kiln:kiln-distill` → PRD → spec → code. The audit flags `loop-incomplete` with a suggested diff linking the capture surfaces to their consumer.

## Functional Requirements

### Content classification rubric

- **FR-001** — Every `## ` section in CLAUDE.md is classified into exactly one of: `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified`. Classification is via an editorial (LLM) call that reads the section and grades against rule-specific definitions.
- **FR-002** — Sections classified as `plugin-surface` are flagged for removal with action `enumeration-bloat` unless exempted by a user override (FR-017). The rationale line cites: "Claude receives available skills / agents / commands via runtime context."
- **FR-003** — Sections classified as `preference` (user-specific ritual that Claude should follow but that isn't derivable from project state — e.g., "always use single quotes in Python") are NEVER flagged for removal. Classification catches them explicitly so they stay out of other rules' crosshairs.
- **FR-004** — Sections classified as `unclassified` are surfaced in the audit's Notes section for human review. Default action: `keep` with a reviewer prompt. The rubric should never silently delete content it doesn't understand.

### Benefit-narrative rubric

- **FR-005** — Rule `benefit-missing` (editorial). Every section classified as `convention-rationale` or `feedback-loop` must contain at least one sentence answering "why does this matter" (keywords: "because", "without this", "prevents", "so that", or other rationale phrasing). Sections without rationale are flagged with action `expand-candidate` and a proposed diff that inserts a placeholder `Why:` line the user fills in. This matches the user's memory-writing convention (rule + `Why:` + `How to apply:`).
- **FR-006** — Rule `loop-incomplete` (editorial). If the repo has capture surfaces (any of `.kiln/issues/`, `.kiln/feedback/`, `.kiln/roadmap/`, `.kiln/mistakes/`, `.kiln/fixes/`), CLAUDE.md must describe how they connect — at minimum, name the consumer (`/kiln:kiln-distill`) and the expected output (PRD → spec → code). If the narrative is missing, fire with action `expand-candidate` and propose an inserted block.

### Hook/claim consistency rubric

- **FR-007** — Rule `hook-claim-mismatch` (cheap + editorial hybrid). Parse CLAUDE.md for assertions about hook behavior (e.g., "hooks block X," "the Y hook enforces Z"). For each claim:
  1. Extract the claim text and the named hook or behavior.
  2. Grep the actual hook scripts for language that enforces the claim.
  3. If no hook enforces it (text absent from all `plugin-*/hooks/*.sh`), fire with action `correction-candidate` and note the mismatch.
- **FR-008** — Out of scope: semantic verification (did the hook ACTUALLY block X in practice?). The rule is limited to static text presence. False positives (hook enforces via jq filter, grep misses) are acceptable; the output is reviewed by a human.

### Plugin-guidance convention

- **FR-009** — Each plugin may ship a file at `<plugin-dir>/.claude-plugin/claude-guidance.md`. The file is a short markdown block (~10-30 lines) with:
  - A `## When to use` section — user-facing framing, 1-3 sentences describing the kinds of tasks that should trigger this plugin.
  - A `## Key feedback loop` section (optional) — how this plugin feeds into other plugins / the overall pipeline.
  - A `## Non-obvious behavior` section (optional) — things Claude must know that aren't self-evident from skill descriptions (e.g., "shelf-sync reads `.shelf-config` for vault paths; don't pass them explicitly").
  - NO skill enumeration, NO command catalog, NO agent lists — those are plugin-surface and flagged for removal wherever they appear.
- **FR-010** — The file is UTF-8 markdown, committed to the plugin repo, versioned with the plugin. No separate versioning. Plugin authors update it when the plugin's role changes materially.

### Plugin-guidance sync

- **FR-011** — The audit enumerates enabled plugins by reading and union-ing:
  - `.claude/settings.json` (project-local) — enabled plugin names
  - `~/.claude/settings.json` (user-global) — enabled plugin names
- **FR-012** — For each enabled plugin, resolve its install path:
  - Source-repo mode (local `plugin-*/` exists): prefer the local directory.
  - Consumer mode (no local `plugin-*/`): use `~/.claude/plugins/cache/<org>-<marketplace>/<plugin>/<version>/` matching the settings-declared version; fall back to highest cached version.
- **FR-013** — Read each plugin's `.claude-plugin/claude-guidance.md` if present. Plugins without the file are skipped silently (they don't opt in; don't coerce).
- **FR-014** — Build the authoritative `## Plugins` section content:
  ```
  ## Plugins
  
  ### <plugin-name>
  
  <claude-guidance.md content, with its top-level `## When to use` demoted to `#### When to use`>
  
  ### <next-plugin-name>
  ...
  ```
  Plugins are listed in alphabetical order by name for deterministic diffs.
- **FR-015** — Diff the built section against the `## Plugins` section in CLAUDE.md:
  - Section missing entirely → propose insertion.
  - Section exists but drifted → propose replacement (full section swap, one unit).
  - Section exists and matches exactly → no diff (already synced).
  - Plugin listed in CLAUDE.md but no longer enabled → proposed diff removes it.
- **FR-016** — The `## Plugins` section is treated as machine-managed. The audit output's Notes section includes a one-line reminder: "This section is auto-synced from per-plugin `.claude-plugin/claude-guidance.md` files. Edit the plugins, not CLAUDE.md, for persistent changes." Manual edits to the section will be reverted on next sync.

### Override surface

- **FR-017** — `.kiln/claude-md-audit.config` supports two new override shapes:
  - `exclude_section_from_classification = <section-regex>, <section-regex>` — sections matching any regex are classified as `preference` and exempt from content-class rules (FR-002). Use for truly local rituals.
  - `exclude_plugin_from_sync = <plugin-name>, <plugin-name>` — listed plugins are skipped during guidance sync (FR-011). Use for plugins enabled globally but irrelevant to this repo (e.g., `gmail`, `drive`).
  Each override requires an inline comment (`# reason: ...`) or the audit fires a warning about unexplained overrides.

### Anthropic alignment

- **FR-018** — The audit output's Notes section cites https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md as the external rubric anchor. Rule rationales that depend on Anthropic's guidance cite the specific claim from that page.
- **FR-019** — The rubric file (`plugin-kiln/rubrics/claude-md-usefulness.md`) includes a "Convention Notes" section documenting that `claude-guidance.md` is a kiln-specific convention. It names the migration path: "If Anthropic adds an official field for Claude-facing plugin guidance (e.g., `plugin.json:claudeGuidance`), migrate to the official field and deprecate this convention within one release cycle."

### Target-product description — vision.md sync

CLAUDE.md must tell Claude what the product IS and what it ASPIRES TO BE. Today the rubric classifies `product` as keep-worthy but doesn't prescribe content shape. This subsection fills that gap by prescribing a `## Product` section in CLAUDE.md that is auto-synced from `.kiln/vision.md` — same pattern as the plugin-guidance sync, different source.

- **FR-022** — The `## Product` section in CLAUDE.md is treated as machine-managed. Its contents are synced from a designated region of `.kiln/vision.md` (the roadmap system's canonical target-product document — see `docs/features/2026-04-23-structured-roadmap/PRD.md` FR-001). Manual edits to `## Product` are reverted on next sync, same policy as `## Plugins`.
- **FR-023** — The source region of `vision.md` is either:
  - The entire file, if `vision.md` is short (≤40 lines), OR
  - A fenced region delimited by `<!-- claude-md-sync:start -->` ... `<!-- claude-md-sync:end -->` markers, if the vision author wants a shorter summary mirrored into CLAUDE.md while keeping a longer vision.md for deep dives.
- **FR-024** — `vision.md` follows a prescribed 7-slot schema (see the roadmap PRD's updated FR-001 for the canonical schema). The audit runs a rubric on `vision.md` itself, flagging missing slots. Slots:
  1. One-line product summary
  2. Primary target user (+ optional secondary)
  3. Top 3 jobs-to-be-done
  4. Non-goals (what the product is NOT)
  5. Current phase (pre-launch | early-access | maturing | mature | end-of-life)
  6. North-star metric / success shape
  7. Key differentiator
- **FR-025** — Rule `product-undefined` (cheap). If CLAUDE.md has no `## Product` section AND `.kiln/vision.md` does not exist, fire with action `expand-candidate` and propose a combined diff:
  - Create `.kiln/vision.md` from the template (prompting each slot for the user to fill).
  - Add a `## Product` section to CLAUDE.md that will be populated on the next audit once `vision.md` is filled in.
  This is a high-signal coverage gap; put the signal at the top of the Signal Summary table regardless of sort order.
- **FR-026** — Rule `product-slot-missing` (editorial). Runs against `vision.md` (not CLAUDE.md). Each of the 7 slots from FR-024 must have at least one sentence of content. Empty or template-placeholder slots fire with action `expand-candidate` per missing slot. The audit output calls these out in a dedicated sub-section labeled "Vision.md Coverage" to keep them separate from CLAUDE.md findings.
- **FR-027** — Rule `product-section-stale` (cheap). Compare the current `## Product` section in CLAUDE.md against the synced-from-vision composition. If they differ, fire with action `sync-candidate`. Proposed diff is the full section swap. Same mechanic as the plugin-sync (FR-015).
- **FR-028** — The sync output applies lightweight formatting: `vision.md`'s top-level `#` title is demoted to `## Product`, and any `## slot-name` headings inside the synced region are demoted one level (to `### slot-name`) so they fit inside CLAUDE.md's section hierarchy. No LLM rewriting.
- **FR-029** — If the user wants to opt out of vision sync entirely (e.g., a repo with no product aspirations document — rare), `.kiln/claude-md-audit.config` accepts `product_sync = false`. The `## Product` section is then left alone and classified like any other section under FR-001. Requires an inline `# reason: ...` comment per FR-017's policy.

### Existing rubric preservation

- **FR-030** — All existing rubric rules (`load-bearing-section`, `stale-migration-notice`, `recent-changes-overflow`, `active-technologies-overflow`, `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`) continue to run. They are the drift-reducer axis; the new rules are the coverage axis. Both run every audit.
- **FR-031** — Signal reconciliation is extended: `load-bearing-section` still wins over flag-for-removal signals, BUT new rule `enumeration-bloat` (FR-002) wins over `load-bearing-section` for sections classified as `plugin-surface`. Rationale: the whole point of the reframe is to remove those sections even if something cites them; cited plugin-surface content is exactly the drift risk we're trying to kill. The new `product-*` rules (FR-025–FR-027) do not conflict with `load-bearing-section` — the `## Product` section is machine-managed and never needs protection from removal rules.

## Absolute Musts

1. **Tech stack match with existing kiln plugin** — Markdown skills, Bash 5.x, `jq`, existing rubric-parsing code in `kiln-claude-audit`. LLM calls reuse whatever call convention the existing editorial rules use (`duplicated-in-prd`, etc.). No new runtime deps.
2. **Anthropic alignment is load-bearing** — our content philosophy matches Anthropic's best-practices. If their guidance changes, the rubric's rationales must be revisited. Cite them in the rubric, not just this PRD.
3. **Plugin-guidance convention is ours, clearly labeled** — `claude-guidance.md` is kiln-custom. Document it as such in the rubric's Convention Notes. Migrate if Anthropic ships an equivalent.
4. **Audit never applies edits** — propose-diff-only remains the contract. Every new rule adheres.
5. **Plugin-surface removal is reversible by override** — FR-017's `exclude_section_from_classification` is the escape hatch. Users who have reasons to keep an enumeration can keep it.
6. **Sync is text-diff-clean, not semantic** — the `## Plugins` section is a deterministic build from plugin inputs. No LLM rewriting to "match the voice of CLAUDE.md" — predictability > style.

## Tech Stack

Inherited from parent kiln plugin — no additions:
- Markdown (skill definitions, rubric file, plugin-guidance files)
- Bash 5.x (skill logic, grep-based rules)
- `jq` (settings JSON parsing, state)
- LLM editorial calls (existing convention for `duplicated-in-*` and `stale-section` rules)
- No new dependencies

## Impact on Existing Features

- **`plugin-kiln/skills/kiln-claude-audit/SKILL.md`** — extended with new classification step and sync step. Existing rubric-loading / diff-writing code is reused. Estimated ~200 additional lines.
- **`plugin-kiln/rubrics/claude-md-usefulness.md`** — gains new rule definitions (`enumeration-bloat`, `benefit-missing`, `loop-incomplete`, `hook-claim-mismatch`) and a Convention Notes section (FR-019).
- **`specs/kiln-self-maintenance/contracts/interfaces.md`** — updated to reflect new rubric rules and override shapes.
- **`plugin-kiln/.claude-plugin/claude-guidance.md`** — new file, shipping the reference example. Covers kiln's feedback-loop philosophy.
- **`plugin-shelf/.claude-plugin/claude-guidance.md`**, **`plugin-wheel/.claude-plugin/claude-guidance.md`**, **`plugin-clay/.claude-plugin/claude-guidance.md`**, **`plugin-trim/.claude-plugin/claude-guidance.md`** — new files, one per first-party plugin. Also ship as reference examples.
- **Kiln plugin template** (if/when created) — the template includes a `claude-guidance.md` stub with section headers and prompts.
- **Existing CLAUDE.md audit consumers** — backward compatible. Old behavior is preserved; new rules fire additively.
- **Consumer CLAUDE.md files** — first audit post-upgrade may flag many `enumeration-bloat` signals if the consumer has hand-rolled plugin sections. Expected and desired; user reviews and applies.

## Alignment with In-Flight Direction

- Pairs with the open issue `2026-04-23-claude-md-audit-lacks-project-context.md` (superseded).
- Pairs with the `2026-04-23-structured-roadmap` PRD — roadmap items use the same benefit-narrative convention (rule + why + how to apply) that FR-005 enforces in CLAUDE.md.
- Pairs with the user's filed feedback on removing skill enumerations from CLAUDE.md (conversation preceding this PRD).
- Does NOT depend on the `2026-04-23-wheel-user-input` PRD or the `.shelf-config` blocker — it's self-contained in kiln.

## Success Metrics

1. **Post-audit CLAUDE.md is shorter and more narrative** — measured by: median section-classification-rate where `product / feedback-loop / convention-rationale` account for ≥70% of sections after the first audit-and-apply cycle. (Before: sections are mostly plugin-surface.)
2. **Plugin guidance is actually used** — at least 3 first-party plugins ship a `claude-guidance.md` within one release cycle; consumer CLAUDE.md files in the wild contain auto-synced `## Plugins` sections with matching content.
3. **Re-audit produces zero new signals on a just-applied diff** — the audit is idempotent within its own output. Applying the proposed diff and re-running should yield "no drift."
4. **Benefit narrative coverage** — 100% of `convention-rationale` sections have a `Why:` line after one cycle. Measured by `benefit-missing` signals dropping to zero.

## Risks / Unknowns

- **LLM classification accuracy** — the `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified` classification is editorial. If the LLM misclassifies (e.g., labels a convention section as plugin-surface), content gets flagged for removal incorrectly. Mitigation: the audit proposes diffs; human reviews. FR-017 override handles false positives.
- **Plugin guidance content quality** — plugins could ship unhelpful `claude-guidance.md` (too long, promotional, inconsistent). Mitigation: reference implementations for first-party plugins set the bar; third parties copy the shape.
- **Sync collisions** — if two plugins both want a section for themselves in different parts of CLAUDE.md, sync only manages `## Plugins`. Plugins with content that must live elsewhere aren't supported. Call this out explicitly; accept the constraint.
- **Anthropic ships a conflicting convention later** — FR-019 plans the migration. Low probability; high-cost if it happens. Accept the risk.
- **Existing CLAUDE.md files have a lot of `enumeration-bloat`** — first audit post-upgrade will produce large diffs. Users may reject en masse. Mitigation: the audit output is a review surface, not an enforcement gate. Users can apply piecemeal or `exclude_section_from_classification` their way through transition.
- **`hook-claim-mismatch` has false positives from grep-based matching** — hooks that enforce via jq filters or non-obvious code paths won't trigger the keyword match, and the rule will incorrectly claim the hook doesn't enforce the behavior. Mitigation: FR-008 explicitly scopes to static text presence; human review required. False-positive rate will be measured in practice.

## Assumptions

- The `kiln-claude-audit` skill is actively maintained and its existing editorial-rule LLM call pattern can be reused for the new classification / benefit-missing / loop-incomplete rules.
- Most plugin authors are willing to maintain a ~20-line `claude-guidance.md` per plugin. First-party plugins set the example; third-party adoption is best-effort.
- `.claude/settings.json` in consumer repos is the authoritative source for enabled plugins. If users enable plugins outside this file, they fall outside the sync.
- CLAUDE.md at the repo root is the only CLAUDE.md the audit cares about. Nested CLAUDE.md files (in subdirectories) are out of scope.
- Anthropic's best-practices page remains stable enough to cite from. If it moves or changes URL, the rubric is updated in a follow-up PR.

## Open Questions

1. Should the `## Plugins` section name be configurable, or always `## Plugins`? Proposal: fixed as `## Plugins` for determinism. Users who prefer `## Tools` or `## Integrations` can rename via a one-line config key in a later release.
2. When a plugin's `claude-guidance.md` is updated, should the audit offer to auto-apply the diff for just that section (one-button "sync this one plugin")? Proposal: no special-case; the diff shows the change and the user applies with `git apply` as usual.
3. Should `claude-guidance.md` support frontmatter for additional metadata (e.g., `applies_to: [source-repo, consumer]`)? Proposal: no in v1. Plain markdown. Add frontmatter if a clear use case emerges.
4. Does the `enumeration-bloat` rule run on the scaffold CLAUDE.md (`plugin-kiln/scaffold/CLAUDE.md`) as well as the consumer's real CLAUDE.md? Proposal: yes — the scaffold is itself a CLAUDE.md seed and should follow the same rules. Audit both in source-repo mode; same rubric.

## Sequencing

- **Depends on**: nothing external. Self-contained in the kiln plugin.
- **Blocks / enables**: consumer repos that install multiple kiln-family plugins benefit immediately from auto-synced plugin guidance. The `2026-04-23-structured-roadmap` PRD's benefit-narrative convention lines up cleanly with FR-005's `benefit-missing` rule — once both ship, roadmap item descriptions and CLAUDE.md sections follow the same discipline.
- **Ordering within this PRD**: classification rubric (FR-001–FR-004) and plugin-guidance sync (FR-009–FR-016) are independent; either can ship first. The benefit-narrative rules (FR-005–FR-006) and hook-claim rule (FR-007–FR-008) layer on top and can be added incrementally as follow-up PRs if v1 scope needs to shrink.
