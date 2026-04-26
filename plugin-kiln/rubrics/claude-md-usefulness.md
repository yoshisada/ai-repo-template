# CLAUDE.md Usefulness Rubric

**Version**: 1 (Apr 2026)
**Consumed by**: `/kiln:kiln-claude-audit` (full rubric) and `/kiln:kiln-doctor` (cheap-cost rules only).
**Overridable from**: `.kiln/claude-md-audit.config` — per-rule merge, repo values win. See that file's shape in `contracts/interfaces.md` §7 of the kiln-self-maintenance spec.

This rubric is the single source of truth for "is our CLAUDE.md still pulling its weight?". Each rule has a stable `rule_id`, a `signal_type` (load-bearing, editorial, or freshness), a `cost` (cheap = grep / line-count only; editorial = LLM required), a `match_rule` (how the rule fires), an `action` (what the diff should propose), and a one-sentence `rationale`. The `cached` field is reserved for a future hash-cache optimization; leave it `false` for now.

A rule is a "signal" when it fires against the audited file. The audit skill collects all signals, renders them as a single table, and proposes a unified diff that codifies each action. The output is review material for a human — the audit never applies edits itself (FR-004).

## When `inconclusive` is legitimate

The model running `/kiln:kiln-claude-audit` performs editorial evaluation in its own context — there is no sub-LLM call. For each editorial rule, the skill MUST load the reference document(s), read every `^## ` section, compare per `match_rule`, and emit findings or `(no fire)`. Skipping the comparison and marking `inconclusive` is forbidden.

The audit MAY emit `inconclusive` ONLY for these three triggers:

1. **Missing reference document** — the rule's `match_rule:` requires a file (e.g. `.specify/memory/constitution.md`, `.kiln/vision.md`, source-repo `CLAUDE.md`) that is not present on disk.
2. **Unparseable reference** — the file exists but is malformed in a way that breaks the `match_rule:` (e.g. invalid YAML frontmatter, encoding error, truncated).
3. **External dependency unavailable** — the rule depends on a remote fetch (WebFetch / MCP) that returned non-2xx or timed out.

"Editorial work feels expensive" is explicitly NOT a legitimate trigger. The Notes cell of an `inconclusive` row MUST cite the specific trigger and the specific resource (e.g. `inconclusive — reference document .specify/memory/constitution.md not found on disk`).

> **FR-018 cross-reference**: the load-bearing rewording (FR-018 of `claude-audit-quality`) aligns with FR-031 of `claude-md-audit-reframe`: a section is load-bearing only when cited from skill / agent / hook / workflow PROSE (instructions, descriptions, error messages), NOT when cited only inside a rule's `match_rule:` field. `enumeration-bloat`'s carve-out over `load-bearing-section` for `plugin-surface` sections (FR-031) remains in force; the new wording reinforces rather than conflicts.

## Configurable thresholds

These live under rule entries that reference them. Overridable from `.kiln/claude-md-audit.config` via the raw key name (no `rule_id.` prefix):

- `recent_changes_keep_last_n` — default `5`. Consumed by `recent-changes-overflow`.
- `active_technologies_keep_last_n` — default `5`. Consumed by `active-technologies-overflow`.
- `migration_notice_max_age_days` — default `14`. Consumed by `stale-migration-notice`. Rationale: the cutover window for a plugin rename is measured in days, not months — keeping the notice past two weeks means every future reader wastes attention on stale guidance. Override upward if your rename has a longer tail (e.g. `migration_notice_max_age_days = 90` for a staged multi-repo rollout).

---

## Rules

### load-bearing-section

```yaml
rule_id: load-bearing-section
signal_type: load-bearing
cost: cheap
match_rule: grep -F "CLAUDE.md" across plugin-*/skills plugin-*/agents plugin-*/hooks plugin-*/workflows templates/; cross-reference the cited section header; PROSE-only — citations from inside a rule's `match_rule:` field do NOT count (claude-audit-quality FR-018)
action: keep
rationale: Sections cited by name from a skill/agent/hook/workflow PROSE must never be removed — doing so silently breaks those references at runtime.
cached: false
```

A section is "load-bearing" if any file under `plugin-*/skills/`, `plugin-*/agents/`, `plugin-*/hooks/`, `plugin-*/workflows/`, or `templates/` cites it **from prose** — i.e., from instructions, descriptions, error messages, or any narrative text — by phrase-match ("per CLAUDE.md", "see the X section of CLAUDE.md", or cites the section-header text verbatim). The inventory under `specs/kiln-self-maintenance/agent-notes/phase-r-inventory.md` is the authoritative starting list. When fired, the diff contains NO change for that section — the rule only ever emits a `keep` action so downstream rules know not to touch it.

**FR-018 wording change** (claude-audit-quality): a section is load-bearing only when cited from **PROSE** — instructions, descriptions, error messages, narrative text. A citation from inside a rule's `match_rule:` field (e.g., this rubric's own `match_rule:` lines that mention `## Recent Changes` or `## Active Technologies`) does NOT make the cited section load-bearing. The reasoning: rule `match_rule:` fields are SELF-references — the rubric cites a section because the rule fires on it; that's not the same as a downstream skill/agent/hook needing the section to exist for its own runtime correctness.

The same FR-018 wording applies to **`## Active Technologies`** — cited by `active-technologies-overflow`'s `match_rule:` but not by any skill/agent/hook prose. `## Active Technologies` is therefore NOT load-bearing under the new wording, regardless of how many rules name it in their match logic.

This wording aligns with `claude-md-audit-reframe` FR-031 (where `enumeration-bloat` already wins over `load-bearing-section` for `plugin-surface` sections) — both rules say "rule-level citation alone is not enough; the load-bearing relationship must originate in the runtime-effective surface (prose instructions, runtime context)".

Known false-positive shape: a plugin that greps the literal string `CLAUDE.md` as part of a file-glob allow-list (e.g. `version-increment.sh`, `require-spec.sh`) does NOT make any section load-bearing — it's treating the filename as a pattern, not a content citation. Filter those out during grep. Equally, this rubric's own `match_rule:` lines mentioning section names do NOT count as prose citations.

### stale-migration-notice

```yaml
rule_id: stale-migration-notice
signal_type: freshness
cost: cheap
match_rule: presence of a blockquote containing "Migration Notice" OR "renamed from" older than migration_notice_max_age_days (default 14)
action: removal-candidate
rationale: Migration notices age out — once the cutover window passes, they become noise that every future reader has to skim past.
cached: false
```

Triggers when the file contains a `> **Migration Notice**:` blockquote or a line matching `renamed from .* to .*`. Staleness is measured from `git log --follow -1 --format=%at -- CLAUDE.md` intersected with the blockquote's surrounding context (the introducing commit). When the blockquote is older than `migration_notice_max_age_days` days, propose removal of the full blockquote plus any orphan blank lines.

Known false-positive shape: an active, near-term migration (e.g. a rename that's mid-flight for the current release cycle). The default 14-day threshold assumes a quick cutover; override upward for longer transitions.

### recent-changes-overflow

```yaml
rule_id: recent-changes-overflow
signal_type: freshness
cost: cheap
match_rule: count of bullet entries under "## Recent Changes" exceeds recent_changes_keep_last_n (default 5)
action: archive-candidate
rationale: Recent Changes is a changelog tail — more than a handful of entries and readers skip the whole section.
cached: false
```

Fires when the file has a `## Recent Changes` heading and the immediately-following bulleted list exceeds the threshold. Entries are assumed to be ordered newest-first; the proposed diff keeps the top `N` (default 5) and removes the rest. The audit does NOT try to archive the removed entries to another file — that's a maintainer call. The diff annotation cites the git log entries they came from so the maintainer can reconstitute them if needed.

Known false-positive shape: the section is used for long-form release notes rather than a changelog tail. In that case, override the threshold or disable this rule in `.kiln/claude-md-audit.config`.

### recent-changes-anti-pattern

```yaml
rule_id: recent-changes-anti-pattern
signal_type: substance
cost: cheap
match_rule: presence of literal "## Recent Changes" heading in the audited file
action: removal-candidate
ctx_json_paths: []
rationale: A ## Recent Changes section becomes a churn surface and circular-load-bearing protection (rules cite it because it exists; it exists because rules cite it). git log + roadmap phases + ls docs/features/ + /kiln:kiln-next collectively cover the same need without churn.
cached: false
```

Fires whenever the literal string `## Recent Changes` appears as a heading in the audited file. **`signal_type: substance`** — co-located with `recent-changes-overflow` for topical grouping but evaluated under the substance rules' precedence (sorts to top of Signal Summary alongside other substance findings per FR-010).

When fired, the proposed diff replaces the ENTIRE `## Recent Changes` section (heading through end-of-section, i.e. up to the next `^## ` heading or EOF) with this exact block (claude-audit-quality FR-016 + OQ-4 reconciliation — generic `<active-phase>` placeholder preserves byte-identity across re-runs):

```markdown
## Looking up recent changes

This file does not maintain a running changelog. To find recent changes:
- `git log --oneline -n 20` — commit-level history.
- `.kiln/roadmap/phases/<active-phase>.md` — phase-level status (in-progress, complete, planned items).
- `ls docs/features/` — shipped feature PRDs.
- `/kiln:kiln-next` — current session-pickup recommendations.
```

The audit log's Notes section MAY include a one-line companion comment naming the current phase (e.g. `current phase: 10-self-optimization`) for apply-time interpretation; this companion comment lives in Notes, NOT in the diff body, so byte-identity holds.

**Reconciliation with `recent-changes-overflow`** (claude-audit-quality FR-017): when `recent-changes-anti-pattern` fires in the same audit, `recent-changes-overflow` is demoted to `keep` — the anti-pattern's removal proposal supersedes the overflow flag. When `## Recent Changes` is absent from the audited file, `recent-changes-overflow` emits no signal at all (absence is not drift, not a missing-section coverage failure).

Known false-positive shape: a project that genuinely uses `## Recent Changes` as a long-form release-notes destination, where readers expect to find the changelog directly in CLAUDE.md. Override via `.kiln/claude-md-audit.config`'s `recent-changes-anti-pattern.enabled = false`.

### active-technologies-overflow

```yaml
rule_id: active-technologies-overflow
signal_type: freshness
cost: cheap
match_rule: count of bullet entries under "## Active Technologies" exceeds active_technologies_keep_last_n (default 5)
action: archive-candidate
rationale: Active Technologies accretes one bullet per feature branch; without trimming it becomes an unreadable list of historical stacks.
cached: false
```

Same mechanic as `recent-changes-overflow`, applied to the `## Active Technologies` section. Keeps the top `N` bullets (default 5), proposes removal for the rest. If the section is missing entirely, the rule does not fire — a missing section is not drift, just a minimal CLAUDE.md.

Known false-positive shape: a repo that uses this section as a genuine tech-stack inventory rather than a feature-branch tail. Override or disable.

### duplicated-in-prd

```yaml
rule_id: duplicated-in-prd
signal_type: editorial
cost: editorial
match_rule: LLM comparison of CLAUDE.md sections against docs/PRD.md (if present) and products/*/PRD.md
action: duplication-flag
rationale: If a CLAUDE.md section duplicates PRD content, the PRD is the source of truth; the duplicate decays out of sync.
cached: false
```

When fired, the audit reads CLAUDE.md and any PRD files at `docs/PRD.md`, `products/*/PRD.md`, or `docs/features/*/PRD.md`, then asks the editorial LLM to return a list of section headings from CLAUDE.md whose content is substantively duplicated in a PRD. The diff proposes removal of the duplicated section with a citation pointing to the PRD location. Editorial rules must mark their output `inconclusive` if the LLM call fails (edge case in spec) — the audit writes the signal with `inconclusive` in the action column and does NOT propose a diff for that section.

Known false-positive shape: short shared boilerplate (project name, one-line project description) that reasonably lives in both places. The LLM prompt explicitly tells the model to ignore ≤3-line shared context and only flag substantive duplication.

### duplicated-in-constitution

```yaml
rule_id: duplicated-in-constitution
signal_type: editorial
cost: editorial
match_rule: LLM comparison of CLAUDE.md sections against .specify/memory/constitution.md
action: duplication-flag
rationale: Constitution articles are load-bearing governance; CLAUDE.md paraphrases of them silently drift and contradict the source.
cached: false
```

Same editorial pattern as `duplicated-in-prd`, but the reference document is `.specify/memory/constitution.md` (or `plugin-kiln/scaffold/constitution.md` when auditing the plugin source repo). Flags CLAUDE.md sections that paraphrase or restate constitutional articles (e.g. the "4 Gates" section duplicating Article IV, or "Implementation Rules" duplicating Article VIII). The diff proposes replacing the duplicated section with a one-line pointer to the constitution article.

Known false-positive shape: CLAUDE.md legitimately contains a condensed "cheat-sheet" summary of the constitution that is explicitly maintained for onboarding. Override by disabling this rule.

### stale-section

```yaml
rule_id: stale-section
signal_type: editorial
cost: editorial
match_rule: LLM evaluation of each section's continued relevance given the current repo state (plugin list, skill list, workflow list)
action: removal-candidate
rationale: Sections describing features that no longer exist actively mislead readers; the LLM is the cheapest way to catch this without hand-maintaining an allow-list.
cached: false
```

The editorial LLM receives each section body plus a small inventory of the current repo (plugin directories that exist, skill directories under each plugin, workflow file names) and is asked whether the section's claims still match the repo. Mismatch = signal fires with `removal-candidate` action; the diff proposes removal and includes the LLM's one-line justification as a diff comment. On LLM failure, mark `inconclusive`.

Known false-positive shape: aspirational sections ("Planned: X") that describe work-in-progress. The LLM prompt instructs the model to only flag sections that describe features claimed to exist NOW; aspirational wording is left alone.

---

## Substance rules — substance evaluation against project context (claude-audit-quality FR-006..FR-009)

The rules above are **drift-reducers** (content that aged badly) and the reframe rules below are **coverage-checkers** (does each section pull its weight). The substance rules below are the **teaching-quality** axis — does the audited file communicate the project's load-bearing concepts (thesis, loop, architecture)?

Substance rules carry a new `signal_type: substance` value. They MUST populate the `ctx_json_paths:` field naming every `CTX_JSON` path their `match_rule:` reads — this is the FR-013 enforcement anchor (the audit emits the `(no project-context signals fired)` placeholder row only when zero rules with non-empty `ctx_json_paths:` fire).

Substance findings sort to the top of the Signal Summary table per FR-010 (`signal_type_rank: 0`); they appear in `## Notes` before any mechanical findings.

### missing-thesis

```yaml
rule_id: missing-thesis
signal_type: substance
cost: editorial
match_rule: read CTX_JSON.vision.body; extract vision-pillar phrases (vision.md ^## headings + first paragraph); pre-filter the audited file's opener + ## What This Repo Is body via grep for any pillar phrase; if pre-filter returns 0 hits, invoke editorial pass to confirm absence
action: expand-candidate
ctx_json_paths: [vision.body]
rationale: A CLAUDE.md that doesn't name the project's thesis lets Claude operate without anchoring product intent to mechanics. Vision pillars are the highest-leverage content.
cached: false
```

Reads `.kiln/vision.md` via `CTX_JSON.vision.body`. The cheap pre-filter extracts vision-pillar phrases (every `^## ` heading from vision.md plus the first paragraph) and `grep -F`'s the audited file's opener and `## What This Repo Is` body for any pillar phrase. If the pre-filter returns ≥1 hit, the rule does NOT fire — the file already references a pillar. Only when the pre-filter returns zero hits does the model invoke the editorial pass to confirm true absence (Risk R-1 mitigation: cheap before expensive).

When the rule fires, the proposed diff inserts a thesis paragraph derived from vision.md content into the audited file's opener (or creates a `## What This Repo Is` section if absent). Action: `expand-candidate`.

Known false-positive shape: a CLAUDE.md that intentionally elides the thesis because the project IS the thesis statement (e.g., a README-as-CLAUDE.md). Override via per-rule disable in `.kiln/claude-md-audit.config`.

### missing-loop

```yaml
rule_id: missing-loop
signal_type: substance
cost: editorial
match_rule: read CTX_JSON.vision.body + CTX_JSON.roadmap.phases; if any phase has status: in-progress or status: complete (i.e., the project has shipped or is shipping a feedback loop), AND the audited file does not name the loop's input → consumer → output triple, fire
action: expand-candidate
ctx_json_paths: [vision.body, roadmap.phases]
rationale: A capture surface (issues, feedback, roadmap, mistakes, fixes) without a named consumer becomes an isolated tool; the loop is the product per .kiln/vision.md.
cached: false
```

Reads `.kiln/vision.md` (for the loop's input/consumer/output narrative) and `.kiln/roadmap/phases/*.md` (status check) via `CTX_JSON.vision.body` and `CTX_JSON.roadmap.phases`. The rule fires once per audit (not per section) when at least one roadmap phase has shipped or is shipping AND the audited file fails to draw the loop (input → consumer → output relationship).

Distinct from `loop-incomplete` (in the reframe section): `loop-incomplete` checks whether CLAUDE.md names `/kiln:kiln-distill` as a capture-surface consumer; `missing-loop` checks whether the file teaches the *narrative* of the loop (where items come from, who consumes them, what comes out). A file can pass `loop-incomplete` (mentions distill) but fail `missing-loop` (mentions distill in passing without drawing the chain).

The proposed diff inserts a paragraph naming the loop's input → consumer → output triple, sourced from vision.md narrative. Action: `expand-candidate`.

Known false-positive shape: pre-loop projects that haven't shipped a feedback surface yet. Pre-check on `roadmap.phases` status guards against this — if no phase is `in-progress` or `complete`, the rule does not fire.

### missing-architectural-context

```yaml
rule_id: missing-architectural-context
signal_type: substance
cost: cheap
match_rule: count distinct plugin-*/ roots from CTX_JSON.plugins.list; if count > 1, parse the audited file's ## Architecture section (or equivalent ## Architecture-tagged heading); fire if section describes only one plugin or is absent
action: expand-candidate
ctx_json_paths: [plugins.list]
rationale: Multi-plugin repos have architectural surface that one-plugin Architecture sections silently hide. Documenting only one plugin teaches the wrong mental model.
cached: false
```

Counts distinct `plugin-*/` roots from `CTX_JSON.plugins.list`. When `>1`, parses the audited file's `## Architecture` section (or any `## ` heading containing the word "Architecture") and fires if (a) the section is absent or (b) the section describes only one plugin. The "describes only one plugin" check is grep-shaped: count `plugin-` mentions in the Architecture section; fire if `count <= 1` and `plugins.list` length `> 1`.

This rule is `cost: cheap` — no editorial pass required. The check is mechanical (count vs threshold).

The proposed diff inserts an architecture overview paragraph naming each plugin and its responsibility — sourced from each plugin's `.claude-plugin/plugin.json` `description:` field when available. Action: `expand-candidate`.

Known false-positive shape: a multi-plugin repo where the audited file is intentionally scoped to one plugin (e.g., a per-plugin README). Override via per-rule disable in the config.

### scaffold-undertaught

```yaml
rule_id: scaffold-undertaught
signal_type: substance
cost: editorial
match_rule: applies only when audited file path matches plugin-*/scaffold/CLAUDE.md (or repo's documented scaffold-template glob); read CTX_JSON.claude_md.body (source-repo CLAUDE.md); for each load-bearing concept family in the source — (a) thesis (vision pillar), (b) loop (input → consumer → output), (c) architectural pointer (e.g. "scaffold deploys into consumer projects via X") — verify the scaffold communicates the same concept; fire per missing concept family
action: expand-candidate
ctx_json_paths: [claude_md.body, vision.body]
rationale: Scaffolds are seeds; they propagate the load-bearing concepts the source repo teaches. A scaffold that omits thesis / loop / architecture seeds Claude with a mechanics-only template.
cached: false
```

Path-scoped: applies only when the audited file matches `plugin-*/scaffold/CLAUDE.md` (or the equivalent scaffold-template glob the repo documents). Reads `CTX_JSON.claude_md.body` (the source-repo CLAUDE.md) and `CTX_JSON.vision.body`.

For each of the **three load-bearing concept families** (per OQ-6 reconciliation), the model verifies the scaffold communicates the concept:

- **(a) thesis** — a vision-pillar phrase appears in the scaffold's opener or `## What This Repo Is` body.
- **(b) loop** — the scaffold names the input → consumer → output triple from vision.md.
- **(c) architectural pointer** — the scaffold mentions the deployment / install path that connects scaffold → consumer project (e.g., "scaffold deploys into consumer projects via `bin/init.mjs`").

The rule fires **per missing concept family** — a scaffold missing all three families fires three signals; missing one fires one signal. Each signal's proposed diff inserts a paragraph for that specific family. Action: `expand-candidate`.

Known false-positive shape: a scaffold deliberately minimal because consumers customize from a near-empty starting point. Override via per-rule disable in the config.

---

## Reframe rules — content classification + sync (claude-md-audit-reframe, FR-001..FR-008, FR-022..FR-029)

The seven rules above are the **drift-reducer** axis (content that aged badly). The rules below are the **coverage** axis — they classify what each section is FOR and flag content that is fundamentally not pulling its weight regardless of age.

The classification call (FR-001) runs ONCE per audited file, before any rule-firing. It returns one of `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified` per `## ` heading. Classification-driven rules below carry a `classification_input:` field naming which class triggers them.

Three new schema fields appear on rules in this section:

- `classification_input: <class>` — rule fires only on sections classified as that class. Multiple classes joined with ` | `.
- `sort_priority: top` — Signal Summary table places this rule's rows at row 1 regardless of default sort order (FR-025). Currently only `product-undefined` uses it.
- `target_file: <path>` — rule runs against this file instead of the audited CLAUDE.md (FR-026). `render_section: <name>` steers the rule's findings into a dedicated subsection of the audit output.

Three new `action` enum values appear on rules in this section:

- `expand-candidate` — proposed diff inserts a placeholder for the user to fill (e.g., a `Why:` line, a `## Product` scaffold).
- `sync-candidate` — proposed diff replaces a section with content sourced from a managed file (e.g., `## Plugins` from per-plugin guidance, `## Product` from `vision.md`).
- `correction-candidate` — proposed diff strikes content asserted to be enforced but not actually present (e.g., a hook claim with no enforcing hook).

### enumeration-bloat

```yaml
rule_id: enumeration-bloat
signal_type: editorial
cost: editorial
classification_input: plugin-surface
match_rule: section classification (FR-001) returned `plugin-surface` AND no exclude_section_from_classification override matched
action: removal-candidate
rationale: Claude receives the available skills / agents / commands list at runtime; re-enumerating it duplicates context and drifts on rename.
cached: false
```

Fires on every section the classifier returns as `plugin-surface` (e.g., a `## Available Commands` section enumerating slash commands, a `## Agents` list, an explicit hook inventory). The diff proposes removing the section in full. The rationale citation is verbatim: "Claude receives available skills / agents / commands via runtime context."

This is the ONE carve-out from `load-bearing-section`'s precedence (FR-031). When `enumeration-bloat` and `load-bearing-section` both fire on the same section, `enumeration-bloat` WINS — re-enumerating runtime-provided context is bloat even if a skill happens to cite the section by name. All other rules continue to lose to `load-bearing-section`.

Known false-positive shape: a section the maintainer wants to keep enumerated despite the runtime overlap (a one-of preference, not drift). Override via `.kiln/claude-md-audit.config`'s `exclude_section_from_classification = <regex> # reason: ...` — matched sections are reclassified as `preference` and never fire `enumeration-bloat`.

### benefit-missing

```yaml
rule_id: benefit-missing
signal_type: editorial
cost: editorial
classification_input: convention-rationale | feedback-loop
match_rule: editorial LLM evaluation — section body lacks any sentence answering "why does this matter" (rationale phrasing: "because", "without this", "prevents", "so that", or a `Why:` line)
action: expand-candidate
rationale: Plain rules without rationale drift; Claude follows a rule with a "why" but skips one without.
cached: false
```

Fires on `convention-rationale` or `feedback-loop` sections whose body contains no rationale phrasing. The diff proposes inserting a placeholder `Why:` line at the end of the section for the user to fill.

The cheap pre-filter (regex for the keywords listed in `match_rule`) runs first; only sections that lack the keywords are passed to the LLM for the final benefit-missing judgment. Sections containing `Why:` or any of the keywords short-circuit to "rule does not fire" without an LLM call.

Known false-positive shape: a section whose rationale lives in the immediately-following section header (e.g., a heading that IS the rationale). Override via per-section disable in the config or by adding a one-line `Why:` summary to the body.

### loop-incomplete

```yaml
rule_id: loop-incomplete
signal_type: editorial
cost: editorial
match_rule: at least one of `.kiln/issues/`, `.kiln/feedback/`, `.kiln/roadmap/`, `.kiln/mistakes/`, `.kiln/fixes/` is non-empty AND CLAUDE.md does not name `/kiln:kiln-distill` (or the canonical consumer of capture surfaces)
action: expand-candidate
rationale: Capture surfaces without a named consumer become isolated tools; the loop is the product per `.kiln/vision.md`.
cached: false
```

Fires once per file (not per section) when the repo has populated capture surfaces but CLAUDE.md never names the canonical consumer (`/kiln:kiln-distill`) or the expected output (PRD → spec → code). The proposed diff inserts a linkage paragraph naming `/kiln:kiln-distill` and the PRD chain.

A cheap pre-check first verifies capture-surface presence (`find .kiln/issues -mindepth 1 -name '*.md'` etc.) and CLAUDE.md non-mention of `/kiln:kiln-distill` (`grep -F`). Only when both pre-checks pass does the LLM judge whether the existing CLAUDE.md content already names an equivalent consumer — false positives cluster here, so the LLM gets the final call.

Known false-positive shape: CLAUDE.md uses a different (custom) consumer surface and the maintainer prefers it. Override by disabling the rule.

### hook-claim-mismatch

```yaml
rule_id: hook-claim-mismatch
signal_type: editorial
cost: editorial
match_rule: extract claims about hook behavior from CLAUDE.md; for each claim, grep `plugin-*/hooks/*.sh` for the named hook + claim keywords; fire when grep returns 0 hits
action: correction-candidate
rationale: Claims about hook behavior that no hook enforces actively mislead Claude; worse than missing content.
cached: false
```

Two-pass: (1) cheap pre-pass extracts hook-claim sentences from CLAUDE.md (sentences containing the word `hook` plus an enforcement verb like `block`, `bump`, `enforce`, `prevent`, or naming a `*-hook` / `<name>.sh` token). (2) for each candidate claim, grep `plugin-*/hooks/*.sh` for the named hook and the enforcement keywords; if grep returns 0 hits, fire with `correction-candidate`.

Per FR-008, this rule is **scoped to static text presence only**. Semantic verification (does the hook actually block X at runtime? does a `jq` filter inside the hook silently bypass the claim?) is out of scope. False positives from grep-missing-jq-filtered-logic are accepted; the output is human-reviewed.

Known false-positive shape: a claim about a hook that lives in a different plugin (e.g., a wheel hook referenced from kiln docs). The grep across `plugin-*/hooks/*.sh` is repo-wide, but only matches files matching `*.sh` — claims about wheel hooks compiled differently can produce false positives. Override per-claim by editing the wording or disabling the rule.

### product-undefined

```yaml
rule_id: product-undefined
signal_type: freshness
cost: cheap
match_rule: CLAUDE.md has no `## Product` section AND `.kiln/vision.md` does not exist
action: expand-candidate
rationale: CLAUDE.md without a Product section never tells Claude what the product IS — only how to operate the build pipeline.
cached: false
sort_priority: top
```

Fires once per audit when both `## Product` is absent from CLAUDE.md AND `.kiln/vision.md` does not exist in the repo. The proposed diff is combined: it creates `.kiln/vision.md` from the template at `plugin-kiln/templates/vision-template.md` AND adds a `## Product` placeholder section to CLAUDE.md.

The `sort_priority: top` field places this signal at row 1 of the Signal Summary table whenever it fires (FR-025, SC-007). This signal is the highest-leverage finding — a CLAUDE.md without a product narrative leaves Claude operating the pipeline without knowing what the pipeline is FOR.

Known false-positive shape: a repo that genuinely has no product (e.g., a meta-tooling plugin used standalone). Override via `.kiln/claude-md-audit.config`'s `product_sync = false  # reason: ...` — when set, all `product-*` rules are suppressed.

### product-slot-missing

```yaml
rule_id: product-slot-missing
signal_type: editorial
cost: editorial
match_rule: editorial LLM evaluation against `.kiln/vision.md` — fires once per slot of the 7-slot schema (FR-024) that is empty or contains template placeholder text
action: expand-candidate
rationale: Vision slots without content silently propagate template placeholders into CLAUDE.md via FR-022 sync.
cached: false
target_file: .kiln/vision.md
render_section: Vision.md Coverage
```

Runs against `.kiln/vision.md`, NOT CLAUDE.md (`target_file` override). Evaluates each of the 7 slots from FR-024 (one-line summary, primary user, top-3 jobs, non-goals, current phase, north-star metric, key differentiator). Fires one signal per empty / placeholder-filled slot.

Findings render under a dedicated `### Vision.md Coverage` sub-section (`render_section` override) so they don't intermix with CLAUDE.md findings. The 7 slots are enumerated in fixed order in the table — slots that DID NOT fire render as ✅ filled rows, so the maintainer sees the full coverage shape every run.

Known false-positive shape: a slot the maintainer intentionally left as a non-applicable placeholder (e.g., "non-goals" empty for a product still pre-launch). The rule cannot distinguish "intentionally empty" from "forgot to fill"; override the slot's signal via per-rule disable, or add a single sentence noting the omission is intentional.

### product-section-stale

```yaml
rule_id: product-section-stale
signal_type: freshness
cost: cheap
match_rule: byte-compare current `## Product` section against the synced-from-vision composition (per FR-023 + FR-028); fire when bodies differ. Sub-signal fires when vision.md is >40 lines AND has no fenced markers.
action: sync-candidate
rationale: Drift between CLAUDE.md's Product section and vision.md silently misrepresents the product narrative.
cached: false
```

Composes the synced `## Product` section from `vision.md` per FR-023 (whole file ≤40 lines, OR fenced region delimited by `<!-- claude-md-sync:start --> ... <!-- claude-md-sync:end -->`) with header demotion per FR-028 (`#` → `## Product`, `##` → `###`). Byte-compares against the current `## Product` section in CLAUDE.md. Differing bodies fire with `sync-candidate`; the diff replaces the section in full (one hunk).

**Sub-signal** (per spec.md Edge Cases): when `vision.md` is >40 lines AND has no `claude-md-sync:start/end` markers, fire under `product-section-stale` with action `expand-candidate` proposing the user add markers around a summary region. Do NOT mirror the long file — that would bloat CLAUDE.md and undo the reframe.

Known false-positive shape: not applicable — `## Product` is machine-managed (FR-022), so any divergence is by definition stale. Override via `product_sync = false`.

## Signal reconciliation (FR-031, extends existing precedence)

The existing precedence rule still applies: any signal on a section that also carries `load-bearing-section` is demoted to `keep (load-bearing)` in the Signal Summary table — no diff proposed. The seven pre-existing rules are unchanged on this axis.

The new rules add ONE carve-out:

```text
For each signal S on section X:
  if any signal exists on X with rule_id == load-bearing-section
     AND S.rule_id != enumeration-bloat:
       demote S to keep (load-bearing); no diff proposed
  if S.rule_id == enumeration-bloat
     AND S.classification_input == plugin-surface:
       S WINS over load-bearing-section; diff proposed
  if S.rule_id starts with "product-":
       no conflict with load-bearing-section possible (## Product is machine-managed)
```

The rationale: `plugin-surface` content is bloat by definition (Claude already receives the runtime context); a load-bearing reference to a bloated section is itself a smell that should be fixed at the citation site, not preserved in CLAUDE.md.

The `product-*` rules don't conflict with `load-bearing-section` because `## Product` is machine-managed — its content is replaced wholesale on each sync. Skills citing the section by name continue to work; only the content underneath changes.

## Convention Notes

`.claude-plugin/claude-guidance.md` is a **kiln-specific convention** — not an Anthropic Claude Code primitive. The file is read by `/kiln:kiln-claude-audit` (FR-009..FR-016 of `specs/claude-md-audit-reframe/`) to build a managed `## Plugins` section in CLAUDE.md.

**Migration path**: if Anthropic ships an official field for Claude-facing plugin guidance (e.g., `plugin.json:claudeGuidance` or equivalent), migrate to the official field and deprecate this convention within one release cycle. Mark this section deprecated, update `kiln-claude-audit` to read the official field as the primary source with `claude-guidance.md` as fallback, then remove the fallback after one release.

**External anchor**: <https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md> is the rubric's external alignment target (FR-018).
