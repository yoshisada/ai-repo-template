# CLAUDE.md Usefulness Rubric

**Version**: 1 (Apr 2026)
**Consumed by**: `/kiln:kiln-claude-audit` (full rubric) and `/kiln:kiln-doctor` (cheap-cost rules only).
**Overridable from**: `.kiln/claude-md-audit.config` — per-rule merge, repo values win. See that file's shape in `contracts/interfaces.md` §7 of the kiln-self-maintenance spec.

This rubric is the single source of truth for "is our CLAUDE.md still pulling its weight?". Each rule has a stable `rule_id`, a `signal_type` (load-bearing, editorial, or freshness), a `cost` (cheap = grep / line-count only; editorial = LLM required), a `match_rule` (how the rule fires), an `action` (what the diff should propose), and a one-sentence `rationale`. The `cached` field is reserved for a future hash-cache optimization; leave it `false` for now.

A rule is a "signal" when it fires against the audited file. The audit skill collects all signals, renders them as a single table, and proposes a unified diff that codifies each action. The output is review material for a human — the audit never applies edits itself (FR-004).

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
