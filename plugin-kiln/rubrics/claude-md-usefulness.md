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
match_rule: grep -F "CLAUDE.md" across plugin-*/skills plugin-*/agents plugin-*/hooks plugin-*/workflows templates/; cross-reference the cited section header
action: keep
rationale: Sections cited by name from a skill/agent/hook must never be removed — doing so silently breaks those references.
cached: false
```

A section is "load-bearing" if any file under `plugin-*/skills/`, `plugin-*/agents/`, `plugin-*/hooks/`, `plugin-*/workflows/`, or `templates/` cites it by phrase-match ("per CLAUDE.md", "see the X section of CLAUDE.md", or cites the section-header text verbatim). The inventory under `specs/kiln-self-maintenance/agent-notes/phase-r-inventory.md` is the authoritative starting list. When fired, the diff contains NO change for that section — the rule only ever emits a `keep` action so downstream rules know not to touch it.

Known false-positive shape: a plugin that greps the literal string `CLAUDE.md` as part of a file-glob allow-list (e.g. `version-increment.sh`, `require-spec.sh`) does NOT make any section load-bearing — it's treating the filename as a pattern, not a content citation. Filter those out during grep.

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
