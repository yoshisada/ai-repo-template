# Feature Specification: Kiln Self-Maintenance

**Feature Branch**: `build/kiln-self-maintenance-20260423`
**Created**: 2026-04-23
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-23-kiln-self-maintenance/PRD.md`

## User Scenarios & Testing

### User Story 1 — Audit CLAUDE.md drift on demand and via kiln-doctor (Priority: P1)

A kiln maintainer who has just finished a feature pipeline wants to know whether `CLAUDE.md` has drifted — has it accumulated stale migration notices, old "Recent Changes" entries, or content that now duplicates `docs/PRD.md` / `.specify/memory/constitution.md`? They run either a dedicated audit skill or `/kiln:kiln-doctor` and get back a reviewable, git-diff-shaped proposal — not auto-applied edits. The maintainer keeps final say.

**Why this priority**: CLAUDE.md is loaded into every session in every consumer repo. Bloat is a permanent multiplicative tax. Without a mechanism, the file only gets audited when someone notices — which is never routine. This is the load-bearing half of the PRD.

**Independent Test**: Run the audit skill against a hand-crafted rubric-conformant fixture CLAUDE.md → expect an empty diff file. Run it against the current source-repo CLAUDE.md → expect a non-empty diff file naming the migration notice, old Recent Changes entries, and at least one duplicated section.

**Acceptance Scenarios**:

1. **Given** a source-repo CLAUDE.md with no drift against the rubric, **When** the maintainer invokes the audit skill, **Then** the skill writes `.kiln/logs/claude-md-audit-<timestamp>.md` with an empty diff body and exits 0.
2. **Given** a source-repo CLAUDE.md containing a months-old migration notice, 15 Recent-Changes entries, and a block duplicated verbatim in the constitution, **When** the maintainer invokes the audit skill, **Then** the output diff proposes removal of the migration notice, archival of all but the last N Recent-Changes entries, and flags the duplication.
3. **Given** the maintainer runs `/kiln:kiln-doctor` (no extra flags), **When** the doctor's structural sweep completes, **Then** the report includes a `CLAUDE.md` row with pass / `DRIFT: <N signals>` status and a pointer to the latest audit log (doctor runs only cheap greppy checks; editorial LLM signals run only in the dedicated audit skill per plan Decision 2).
4. **Given** the audit skill is invoked in a consumer repo, **When** it runs, **Then** it audits only that repo's `CLAUDE.md` (the scaffold template lives under the cached plugin directory, not the consumer's repo).

---

### User Story 2 — Versioned, discoverable usefulness rubric (Priority: P1)

The maintainer wants the definition of "useful CLAUDE.md content" written down, versioned with the plugin, and evolvable. They (and future maintainers) read the rubric, not the audit skill's source, to understand what the audit checks and why. Consumer projects can optionally override specific rules via a repo-local config — without forking the plugin.

**Why this priority**: Without the rubric as a first-class artifact, the audit logic is implicit and drifts silently. The rubric is also what makes the mechanism evolvable — a new signal type is a rubric edit, not a skill rewrite.

**Independent Test**: File exists at the plan-locked path (`plugin-kiln/rubrics/claude-md-usefulness.md`). `grep -rn` finds at least one reference to that path outside the audit skill body (e.g., this spec, or a doc). Rubric conforms to the schema in `contracts/interfaces.md`.

**Acceptance Scenarios**:

1. **Given** the rubric exists at `plugin-kiln/rubrics/claude-md-usefulness.md`, **When** the audit skill runs, **Then** the skill reads the rubric at invocation and does not hardcode signal rules.
2. **Given** a consumer has written `.kiln/claude-md-audit.config` with a rule override, **When** the audit runs in that consumer repo, **Then** the override takes precedence for that rule and the plugin default applies for every un-overridden rule (repo override > plugin default, per-rule merge per plan Decision 1).

---

### User Story 3 — Rewritten consumer-repo scaffold template (Priority: P1)

A new consumer running `kiln init` should receive a `CLAUDE.md` that reflects the plugin's current architecture — not the months-stale version. The current scaffold has drifted far enough that incremental pruning is insufficient; it gets rewritten from scratch in this feature as the new baseline.

**Why this priority**: Every new consumer onboarding pays the cost in confusion when the scaffolded CLAUDE.md describes a state that no longer matches the plugin. The rewrite is a one-time fix; future audits keep it fresh.

**Independent Test**: `git log -p plugin-kiln/scaffold/CLAUDE.md` in this PR shows a substantial rewrite (>50% of lines changed), not just pruning. The new scaffold passes the audit skill against the rubric with an empty diff.

**Acceptance Scenarios**:

1. **Given** the rewrite has landed, **When** a consumer runs `kiln init` in a fresh repo, **Then** the scaffolded `CLAUDE.md` matches the minimal-skeleton shape defined in `contracts/interfaces.md` and passes the audit.

---

### User Story 4 — Feedback skill interviews before writing (Priority: P2)

A maintainer files strategic feedback with `/kiln:kiln-feedback "<description>"`. Instead of writing immediately, the skill runs a short structured interview (3 default + up to 2 area-specific questions, capped at 5 per plan Decision 4) covering what "done" looks like, who triggers it, scope, any paired tactical backlog entry, and 1–2 area-specific follow-ups. The interview answers are written to the feedback file's body as a `## Interview` section. `/kiln:kiln-distill` picks up that section and builds richer PRD narratives.

**Why this priority**: Shallow feedback makes distill guess. Enforcing a short interview raises the floor of every downstream PRD. Independent of the CLAUDE.md track.

**Independent Test**: Invoke `/kiln:kiln-feedback "CLAUDE.md should be refreshed"` with area classified as `architecture`. The skill prompts for exactly 5 questions (3 default + 2 area-specific). The resulting file under `.kiln/feedback/` contains a `## Interview` section with the answers.

**Acceptance Scenarios**:

1. **Given** the user invokes `/kiln:kiln-feedback <description>`, **When** classification resolves unambiguously, **Then** the skill asks the 3 default interview questions before the file write.
2. **Given** the classified area is `architecture`, **When** the skill runs the interview, **Then** it asks the 2 additional architecture-area questions from the map locked in `contracts/interfaces.md` (≤5 total).
3. **Given** the user answers all interview questions, **When** the skill writes the file, **Then** the body contains the raw description at top, followed by a `## Interview` section with one sub-heading per question and the user's answer beneath.

---

### User Story 5 — In-prompt interview skip (Priority: P2)

A maintainer who already knows exactly what the PRD should say, and just wants the one-liner captured, needs a visible escape hatch. Each prompt shows "skip interview — just capture the one-liner" as the last option; selecting it writes a file with no `## Interview` section.

**Why this priority**: Without a skip, the interview becomes friction every time. Plan Decision 5 makes skip the LAST option at every interview prompt (matching clay-ideation-polish precedent: no CLI flags on interactive skills).

**Independent Test**: Invoke `/kiln:kiln-feedback "<description>"`, choose the skip option at the first prompt. The resulting file body equals the raw description with no `## Interview` section; grep `## Interview` returns zero hits.

**Acceptance Scenarios**:

1. **Given** the user invokes the skill, **When** the first interview prompt is displayed, **Then** the final option reads verbatim `skip interview — just capture the one-liner`.
2. **Given** the user picks the skip option, **When** the skill writes the file, **Then** the file has the same shape as today's feedback skill output (no `## Interview` section).

---

### User Story 6 — First audit pass proves the mechanism (Priority: P3)

Immediately after the audit mechanism lands, a first audit pass runs against the source-repo `CLAUDE.md`. The resulting diff is reviewed, and any non-controversial edits are applied in the same PR. This is both a smoke test and the baseline-setting audit.

**Why this priority**: Proving the mechanism on the accumulated bloat that motivated the feature. Depends on US1–US3.

**Independent Test**: `git log -p CLAUDE.md` in this PR shows pruning/restructuring commits. The audit log file exists under `.kiln/logs/claude-md-audit-<timestamp>.md`.

**Acceptance Scenarios**:

1. **Given** the audit mechanism has landed, **When** the first pass runs against source-repo CLAUDE.md, **Then** the diff identifies (a) the speckit-harness → kiln Migration Notice as a removal candidate, (b) Recent Changes entries beyond the last-N threshold, (c) at least one section duplicated in docs/PRD.md or the constitution.
2. **Given** the maintainer reviews the diff, **When** non-controversial edits are applied, **Then** the PR contains a commit touching `CLAUDE.md` with the accepted prunings.

---

### Edge Cases

- **Rubric file missing in consumer repo cache** (first `kiln init` run, plugin not yet cached): the audit skill exits with a clear message `rubric not found at <path>; run kiln init or re-install the plugin` — it does not silently pass.
- **Empty consumer CLAUDE.md**: audit produces a single-signal diff recommending the minimal-skeleton baseline (not an empty diff — empty file is itself a signal).
- **No drift and no changes since last run**: repeated invocation produces byte-identical diff files (NFR-002 idempotency).
- **Interview answer left blank**: skill re-prompts once; second blank answer is written as literal `(no answer)` — does not block the write.
- **Area classified as `other`**: interview uses the 3 defaults only (no area-specific add-ons); total = 3 questions.
- **`$ARGUMENTS` empty on `/kiln:kiln-feedback` invocation**: existing behavior preserved — skill asks for the one-liner first, THEN runs the interview on the provided description (NFR-003 keeps the existing contracts intact).
- **LLM editorial signal unavailable** (offline / model failure): audit skill records the signal as `inconclusive` in the diff, does not fail.
- **`.kiln/claude-md-audit.config` malformed**: audit warns and falls back to plugin defaults for all rules; never silently applies a half-parsed override.

## Requirements

### Functional Requirements

**CLAUDE.md audit mechanism (PRD FR-001..FR-006):**

- **FR-001** (PRD FR-001): Kiln MUST provide a way to audit `CLAUDE.md` that the maintainer can invoke ad-hoc (as a dedicated skill `/kiln:kiln-claude-audit`) AND that integrates with `/kiln:kiln-doctor`'s structural sweep as a cheap greppy subcheck. The dedicated skill runs the full rubric (including editorial LLM signals); doctor runs only the cheap greppy signal set.
- **FR-002** (PRD FR-002): A usefulness rubric artifact MUST exist at `plugin-kiln/rubrics/claude-md-usefulness.md` before the audit skill is implemented (Phase R precedes Phase S). The audit skill reads the rubric at invocation — it does NOT hardcode signal rules.
- **FR-003** (PRD FR-003): The rubric MUST cover at least these signal types: (a) **load-bearing** — grep references from `plugin-*/skills/`, `plugin-*/agents/`, `plugin-*/hooks/`, `plugin-*/workflows/`, and `templates/` to specific CLAUDE.md section headers or phrases (if referenced, the section stays); (b) **editorial** — LLM-judgment flags for staleness or duplication against `docs/PRD.md` and `.specify/memory/constitution.md`; (c) **freshness** — migration notices older than a configurable age threshold become removal candidates; "Recent Changes" and "Active Technologies" entries beyond the last N (rubric-configured, default N=5) are archival candidates.
- **FR-004** (PRD FR-004): The audit MUST produce a git-diff-shaped preview at `.kiln/logs/claude-md-audit-<YYYY-MM-DD-HHMMSS>.md`. The skill MUST NOT write edits directly to `CLAUDE.md` — maintainer applies the diff manually. No auto-apply mode in v1.
- **FR-005** (PRD FR-005): When invoked in the plugin source repo, the audit MUST cover BOTH `CLAUDE.md` AND `plugin-kiln/scaffold/CLAUDE.md`. When invoked in a consumer repo, only that repo's `CLAUDE.md` is audited (the scaffold template lives under the cached plugin directory, not in the consumer repo).
- **FR-006** (PRD FR-006): `plugin-kiln/scaffold/CLAUDE.md` MUST be rewritten from scratch in this feature as a minimal skeleton per the shape locked in `contracts/interfaces.md`. Future `kiln init` invocations pick up the new template.

**`/kiln:kiln-feedback` interview mode (PRD FR-007..FR-010):**

- **FR-007** (PRD FR-007): `/kiln:kiln-feedback` MUST run a structured interview between the classification gate (Step 4 in the current skill) and the file write (Step 5). Question count is 3 default + up to 2 area-specific = 5 max (plan Decision 4). Interview runs inline in main chat — no wheel workflow, no MCP, no background sync (NFR-003).
- **FR-008** (PRD FR-008): The 3 default interview questions MUST be (exact wording in `contracts/interfaces.md`): (1) what does "done" look like?, (2) who triggers this and when?, (3) what's the scope (this repo, consumer repos, other plugins)? Area-specific add-ons follow the area → question-set map in `contracts/interfaces.md` (e.g., `architecture` adds two questions about structural shape; `ergonomics` adds two about friction measurement).
- **FR-009** (PRD FR-009): Interview answers MUST be captured in the feedback file body (not frontmatter) as a `## Interview` section placed immediately after the raw description. Each question becomes a `### <question text>` sub-heading; the user's answer is the paragraph beneath. Shape locked in `contracts/interfaces.md`.
- **FR-010** (PRD FR-010): The interview MUST be skippable via a single in-prompt opt-out — the LAST option at every interview prompt reads verbatim `skip interview — just capture the one-liner`. Picking it writes the file with no `## Interview` section (identical shape to today's skill output). No CLI flag (plan Decision 5 — matches clay-ideation-polish precedent).

**Tactical first pass (PRD FR-011):**

- **FR-011** (PRD FR-011): Immediately after FR-001..FR-006 land, the first audit pass MUST be executed against the source-repo `CLAUDE.md` in Phase V. The resulting diff is reviewed; non-controversial edits are applied and committed in this PR.

### Non-Functional Requirements

- **NFR-001** (PRD NFR-001): No new runtime dependencies. All work is Bash + Markdown (rubric + skill bodies) + optional LLM judgment via agent steps (same pattern `/kiln:kiln-audit` uses today).
- **NFR-002** (PRD NFR-002): The audit skill MUST be idempotent. Running it twice against an unchanged `CLAUDE.md` and an unchanged rubric produces byte-identical diff files. Timestamp in the output filename is allowed to differ; diff body is byte-identical.
- **NFR-003** (PRD NFR-003): The interview step MUST NOT break `/kiln:kiln-feedback`'s existing contracts: no wheel workflow, no MCP writes, no background sync, no new frontmatter keys. Frontmatter Contract 1 stays unchanged.
- **NFR-004** (PRD NFR-004): The rubric artifact MUST be grep-discoverable — at least one non-skill reference to the rubric path exists in the repo (this spec counts; future docs/README references are additive).

### Key Entities

- **Rubric** — Markdown file at `plugin-kiln/rubrics/claude-md-usefulness.md` with entries conforming to the schema in `contracts/interfaces.md` (signal_type, match_rule, action, rationale).
- **Audit log** — Markdown file at `.kiln/logs/claude-md-audit-<timestamp>.md`, body is a git-diff-style preview plus a signal-summary header.
- **Consumer override config** — Optional file at `.kiln/claude-md-audit.config` (plain key-value, same format family as `.shelf-config`). Per-rule overrides merge with plugin defaults.
- **Interview question set** — Static map (3 defaults + area-specific add-ons) defined in `contracts/interfaces.md` and referenced by the updated feedback skill body.
- **Feedback file** — Existing `.kiln/feedback/<date>-<slug>.md` shape, extended with an optional `## Interview` body section per FR-009.

## Success Criteria

- **SC-001** (PRD SC-001): Audit mechanism exists and runs clean on the empty case. A fixture CLAUDE.md crafted to match the rubric produces a zero-diff output file when audited. Verified by: fixture + audit invocation + grep for `no drift` marker in the output.
- **SC-002** (PRD SC-002): The FR-011 first pass output (`.kiln/logs/claude-md-audit-<timestamp>.md`) contains at least: (a) the speckit-harness → kiln Migration Notice as a removal candidate, (b) Recent Changes entries older than the rubric's threshold flagged as archival candidates, (c) at least one section flagged as duplicated vs. `docs/PRD.md` or the constitution.
- **SC-003** (PRD SC-003): `git log -p plugin-kiln/scaffold/CLAUDE.md` in this PR shows a substantial rewrite (>50% of lines changed), not just pruning. The new scaffold is audit-clean against the rubric.
- **SC-004** (PRD SC-004): The rubric file exists at `plugin-kiln/rubrics/claude-md-usefulness.md`, is referenced from the audit skill body, AND `grep -rn plugin-kiln/rubrics/claude-md-usefulness.md` finds at least one non-skill reference (this spec satisfies this).
- **SC-005** (PRD — interview runs by default): Invoking `/kiln:kiln-feedback "<description>"` with an unambiguous area prompts for exactly 3 default + up to 2 area-specific questions before writing. Verified by: scripted run + question-count check.
- **SC-006** (PRD — interview captured): The resulting `.kiln/feedback/<file>.md` contains a `## Interview` section with one sub-heading per question. Verified by: grep `^## Interview$` returns exactly 1 hit in the file.
- **SC-007** (PRD — skip works): Invoking `/kiln:kiln-feedback "<description>"` and picking the last option (skip) produces a file whose body is the raw description with no `## Interview` section. Verified by: grep `^## Interview$` returns 0 hits.
- **SC-008** (PRD SC-008): This PR contains a commit applying the first audit pass's accepted edits to the source-repo `CLAUDE.md`. Verified by: `git log -p CLAUDE.md` in the PR shows pruning/restructuring commits authored as part of Phase V.

## Assumptions

- Consumer-override config shape (`.kiln/claude-md-audit.config`) uses the same plain key-value format family as `.shelf-config` — no new parser.
- The "editorial" LLM signal uses the same agent-step pattern `/kiln:kiln-audit` uses today; no new agent definitions required (NFR-001).
- `/kiln:kiln-doctor`'s CLAUDE.md check runs only cheap greppy signals on every invocation; editorial signals are gated to the dedicated `/kiln:kiln-claude-audit` skill (plan Decision 2 path (c)).
- The scaffold rewrite is a minimal skeleton (plan Decision 3) — per-plugin READMEs (tracked in `.kiln/issues/2026-04-22-plugin-documentation.md`) carry the canonical-commands surface, so the scaffold does NOT need to enumerate every plugin's commands.
- Interview area-specific questions are authored as part of Phase U; mission / scope / ergonomics / architecture each get 2 add-ons; `other` gets none (total = 3 for `other`).
- First-pass acceptance of audit-suggested edits is a maintainer judgement call in Phase V — the spec does not dictate which edits are "non-controversial"; that is review-time discretion.
