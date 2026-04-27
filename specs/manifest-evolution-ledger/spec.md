# Feature Specification: Manifest-Evolution Ledger — V1 Pure-History View

**Feature Branch**: `build/manifest-evolution-ledger-20260427`
**Created**: 2026-04-27
**Status**: Draft
**Input**: PRD `docs/features/2026-04-27-manifest-evolution-ledger/PRD.md` (7 FRs / 5 NFRs / 6 SCs)

## User Scenarios & Testing *(mandatory)*

The ledger ships as a single new skill `/kiln:kiln-ledger` that stitches three already-populated capture substrates into one chronological markdown table. Three user stories — one for the monthly read, one for the per-PR-apply trace, one for the degraded-MCP fallback — each independently testable.

### User Story 1 — Monthly chronological view (Priority: P1) 🎯 MVP

Maintainer runs `/kiln:kiln-ledger --since 2026-04-01` once a month and gets a single chronological table that lists every `/kiln:kiln-mistake` capture, every shelf manifest-improvement proposal (open + applied), and every manifest-edit commit since the start of April. Per-row source links let the maintainer drill into any event in one click.

**Why this priority**: Vision win-condition (d) — "the self-improvement loop closes" — is currently unfalsifiable. Without this MVP the maintainer has no answer surface for "what happened to the manifests this month?". Every other story is incremental on top of this baseline view.

**Independent Test**: With `.kiln/mistakes/` populated (≥1 file), shelf MCP returning ≥1 inbox proposal, and `git log` containing ≥1 manifest-edit commit, run `/kiln:kiln-ledger --since 2026-04-01`. Assert (a) `.kiln/logs/ledger-<YYYY-MM-DD-HHMMSS>.md` is created, (b) stdout contains the same markdown table byte-for-byte, (c) every populated substrate contributes ≥1 row, (d) the table is sorted by date descending with stable tiebreak on source-path.

**Acceptance Scenarios**:

1. **Given** `.kiln/mistakes/` has 2 files dated 2026-04-10 and 2026-04-22, shelf MCP returns 1 open proposal dated 2026-04-15 and 1 applied proposal dated 2026-04-20, and `git log` returns 2 commits matching `MANIFEST_EDIT_PATTERNS` dated 2026-04-18 and 2026-04-25, **When** `/kiln:kiln-ledger --since 2026-04-01` runs, **Then** the rendered table contains exactly 6 rows in date-descending order (2026-04-25 → 2026-04-22 → 2026-04-20 → 2026-04-18 → 2026-04-15 → 2026-04-10) and every row carries a source-link column populated.
2. **Given** the same corpus, **When** the skill runs, **Then** `.kiln/logs/ledger-<timestamp>.md` is written AND the bytes piped to stdout are byte-identical to the file's contents (FR-004).
3. **Given** an `edit` commit whose body contains `applies inbox/open/2026-04-15-foo.md`, **When** the table renders, **Then** the `edit` row's `resolution-link` column points back at the matching proposal AND the `proposal-applied` row's `resolution-link` column points at the commit hash (SC-005).
4. **Given** two events share the same `date` value, **When** the renderer sorts, **Then** the tiebreak is stable on `source` path (NFR-001) so re-runs on unchanged repo state produce byte-identical output.

---

### User Story 2 — Verify a `/kiln:kiln-pi-apply` landed (Priority: P1)

After running `/kiln:kiln-pi-apply` and merging the resulting edits, the maintainer runs `/kiln:kiln-ledger --type edit --since 2026-04-20` to confirm which of the proposed edits actually landed as commits. The trace is one row per edit, not a per-proposal `git log | grep` chain.

**Why this priority**: Closes the "did the proposal land?" question that the PRD problem-2 calls out. P1 because it's the most common day-to-day use after pi-apply pipelines run.

**Independent Test**: With a corpus that has 3 mistake files, 2 proposals, and 4 edit commits, run `/kiln:kiln-ledger --type edit --since 2026-04-20`. Assert ONLY `edit` rows appear AND every row's `date >= 2026-04-20`. Filters are AND-combined (FR-003).

**Acceptance Scenarios**:

1. **Given** the corpus from US1 (6 events), **When** `/kiln:kiln-ledger --type edit --since 2026-04-20` runs, **Then** the rendered table contains EXACTLY the 2 `edit` rows (2026-04-25 + 2026-04-18) — no `mistake`, no `proposal-open`, no `proposal-applied` rows.
2. **Given** the same corpus and `--since 2026-04-19`, **When** the skill runs, **Then** ONLY events on or after 2026-04-19 appear (5 rows: drops the 2026-04-18 edit AND the 2026-04-15 proposal AND the 2026-04-10 mistake).
3. **Given** filter combinations `--type mistake --since 2026-04-15`, **When** the skill runs, **Then** rows are filtered by `type == mistake` AND `date >= 2026-04-15` (intersection — NOT union; SC-002).
4. **Given** an unrecognized value for `--type`, **When** the skill runs, **Then** the skill exits 1 with a single-line error to stderr `error: --type must be one of mistake|proposal|edit|all`. Exit-1 is reserved for malformed flags only (FR-005).

---

### User Story 3 — Degraded shelf MCP (Priority: P2)

The maintainer's Obsidian MCP is flaky in CI / a headless session. Running `/kiln:kiln-ledger --substrate mistakes,edits` (or letting the auto-degrade detect the failure) emits a partial timeline that explicitly skips proposals AND surfaces the degradation in a single-line banner above the table.

**Why this priority**: The PRD's user story explicitly calls this out as a first-class case ("with a flaky shelf MCP"). P2 because the manual `--substrate` opt-out exists; auto-detection of MCP failure is the convenience layer.

**Independent Test**: Stub `read-proposals.sh` to exit non-zero (or set `MCP_SHELF_DISABLED=1`). Run `/kiln:kiln-ledger`. Assert (a) skill exits 0 (FR-005), (b) the report includes the verbatim banner `Substrates included: mistakes, edits — (shelf unavailable, proposals omitted)` (NFR-002), (c) no `proposal-open` or `proposal-applied` rows are emitted, (d) `mistake` and `edit` rows render normally.

**Acceptance Scenarios**:

1. **Given** the shelf reader exits non-zero, **When** the skill runs without `--substrate`, **Then** the orchestrator catches the failure, omits proposals, emits the degraded-substrate banner, and exits 0.
2. **Given** `--substrate mistakes,edits` is passed explicitly, **When** the skill runs (even with shelf MCP fully healthy), **Then** the proposal substrate is skipped and the banner reads `Substrates included: mistakes, edits — (proposals opted-out via --substrate)`.
3. **Given** `.kiln/mistakes/` is empty AND shelf returns zero proposals AND `git log` returns zero matching commits, **When** the skill runs, **Then** the report renders with an empty `## Events` table and a Notes-section line `No events found in the requested window.`. Exit code is 0 (FR-005).
4. **Given** a malformed `--substrate` value like `--substrate banana`, **When** the skill runs, **Then** stderr emits `error: --substrate values must be subset of {mistakes,proposals,edits,all}` and exit code is 1 (FR-005 carve-out for malformed flags).

---

### Edge Cases

- `.kiln/mistakes/` directory missing entirely → reader emits zero rows, no error, no banner needed (FR-005).
- `.kiln/logs/` missing → orchestrator creates it before writing the report file.
- `git log --grep=...` returns commits whose authorship date is later than committer date (rebase) → use `%aI` (author ISO) as the canonical row date; document in Notes if the two diverge for any row.
- Manifest-edit commit whose body matches no proposal → `resolution-link` column renders as `—` (em-dash) per R-1 mitigation, AND the report's Notes section surfaces a single aggregated line `<K> edits found, <J> lacked proposal back-references` (R-1 visibility).
- Shelf MCP returns a proposal whose front-matter has no `date:` field → reader falls back to file mtime AND adds a Notes-section line `note: proposal <id> used file-mtime fallback (no date frontmatter)`.
- Multiple mistake files share the same date → stable tiebreak on source-path (NFR-001) — re-runs are byte-identical.
- Single commit lands edits to TWO manifest files (e.g., `CLAUDE.md` + `SKILL.md`) → ONE row per commit (OQ-2 resolution); affected files are listed in the `summary` column as `claude-md+skill-md`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** (from PRD FR-001): A new skill `/kiln:kiln-ledger` MUST be shipped at `plugin-kiln/skills/kiln-ledger/SKILL.md` and registered with the kiln plugin (auto-discovered via `plugin-kiln/skills/`). When invoked, it MUST walk three substrates and emit a chronological timeline:
  - `.kiln/mistakes/*.md` — one row per mistake-capture file, type=`mistake`.
  - Shelf `@inbox/open/*.md` AND `@inbox/applied/*.md` (read via Obsidian MCP) — one row per proposal, type ∈ `{proposal-open, proposal-applied}`.
  - Git log filtered by `MANIFEST_EDIT_PATTERNS` over the requested `--since` window — one row per matching commit, type=`edit`, dedup'd ONE-PER-COMMIT (OQ-2 resolution).

- **FR-002** (from PRD FR-002): The rendered timeline MUST be a markdown table with EXACTLY these columns, in this order:
  | `date` | `type` | `source-link` | `summary` | `resolution-link` |
  Where: `date` is `YYYY-MM-DD`; `type` is one of `mistake | proposal-open | proposal-applied | edit`; `source-link` is a relative link to the substrate file (or commit URL fragment for edits); `summary` is a ≤120-char one-line excerpt (newlines collapsed); `resolution-link` is empty (rendered as `—`) for `mistake` and `proposal-open` rows, the commit-hash link for `proposal-applied` rows, the proposal back-link for `edit` rows when detectable.

- **FR-003** (from PRD FR-003): The skill MUST accept three filter flags, AND-combined:
  - `--since <YYYY-MM-DD>` (default: 30 days ago, computed UTC on each invocation).
  - `--type <mistake|proposal|edit|all>` (default: `all`). `proposal` matches BOTH `proposal-open` AND `proposal-applied` (PRD vocabulary alignment).
  - `--substrate <comma-separated subset of mistakes,proposals,edits,all>` (default: `all`). Specifying `mistakes,edits` skips the proposals reader entirely.
  Unrecognized flag values MUST exit 1 with a single-line stderr error (FR-005 carve-out).

- **FR-004** (from PRD FR-004): The skill MUST write the rendered report to BOTH stdout AND `.kiln/logs/ledger-<YYYY-MM-DD-HHMMSS>.md` in one atomic operation per surface. The bytes piped to stdout MUST be byte-identical to the bytes written to the log file (`tee`-style, NOT a separate render pass). The log file is the audit trail; stdout is the user surface.

- **FR-005** (from PRD FR-005): The skill MUST degrade gracefully when a substrate cannot be read:
  - `.kiln/mistakes/` missing or empty → no mistake rows; no banner needed (substrate is "available" but empty).
  - Shelf MCP unavailable (reader exits non-zero, OR `MCP_SHELF_DISABLED=1`, OR `--substrate` excludes proposals) → no proposal rows; the report MUST surface the omission in the degraded-substrate banner per NFR-002.
  - `git log --grep=...` returns no matching commits → no edit rows; no banner needed.
  Skill exits 0 in all degraded cases. Exit 1 is reserved EXCLUSIVELY for malformed flags.

- **FR-006** (from PRD FR-006): Implementation MUST follow the orchestrator + per-substrate-reader split, using the architectural pattern established by `plugin-kiln/scripts/metrics/extract-signal-<a..h>.sh` (PR #193 Theme D):
  - `plugin-kiln/scripts/ledger/read-mistakes.sh` — reads `.kiln/mistakes/*.md`, emits one NDJSON row per file to stdout.
  - `plugin-kiln/scripts/ledger/read-proposals.sh` — reads shelf via Obsidian MCP, emits NDJSON rows for `@inbox/open/*.md` AND `@inbox/applied/*.md`.
  - `plugin-kiln/scripts/ledger/read-edits.sh` — runs `git log` filtered by `MANIFEST_EDIT_PATTERNS`, emits NDJSON rows.
  - `plugin-kiln/scripts/ledger/render-timeline.sh` — reads aggregated NDJSON via stdin, sorts by `(date DESC, source ASC)`, emits the markdown report to stdout.
  Adding a new substrate requires (a) a new reader script, (b) one-line addition to the orchestrator's substrate list, (c) a new test fixture. The render pipeline is untouched.

- **FR-007** (from PRD FR-007): The manifest-edit pattern set MUST live in a single shell-array constant `MANIFEST_EDIT_PATTERNS` declared at the top of `plugin-kiln/scripts/ledger/read-edits.sh`. Initial set: `chore(claude-md):`, `pi-apply:`, `chore(roadmap):`, `chore: apply manifest improvement`. The constant name MUST be discoverable via `git grep -F MANIFEST_EDIT_PATTERNS plugin-kiln/scripts/ledger/`. **Maintenance contract**: adding a new commit-prefix pattern is a one-line edit to this array PLUS a per-reader PR — never a skill rewrite, never a change to render-timeline.sh.

### Non-Functional Requirements

- **NFR-001** (determinism): Re-running `/kiln:kiln-ledger` with the same `--since` / `--type` / `--substrate` against unchanged repo state MUST produce a byte-identical report (timestamp section header in the H1 excepted). Sort key is `(date DESC, source ASC)` with stable tiebreak. The `render-timeline.sh` invocation MUST run under `LC_ALL=C` so UTF-8 collation differences across macOS / Linux do not cause byte-divergence. Verified by SC-001 second-run assertion.

- **NFR-002** (degraded substrate observability): When ANY substrate is omitted (auto-degrade or `--substrate` opt-out), the report MUST include a single-line section above the events table with the verbatim shape `Substrates included: <csv> — (<reason>)`, where `<csv>` is the alphabetically-sorted list of included substrates and `<reason>` is one of: `shelf unavailable, proposals omitted | proposals opted-out via --substrate | mistakes opted-out via --substrate | edits opted-out via --substrate` (composable; multi-omission joins reasons with `; `). Silent omission of a substrate is a CONTRACT VIOLATION.

- **NFR-003** (shell-only V1): Implementation MUST be bash + jq + git only — no Python, no Node, no new runtime deps. Pattern matches `plugin-kiln/scripts/metrics/` precedent (PR #193 Theme D). The shelf MCP read inside `read-proposals.sh` is performed via the existing `plugin-shelf` MCP shim invoked from bash; no new MCP client added.

- **NFR-004** (coverage gate): ≥80% coverage on new code, measured per the run.sh-only test-substrate convention from PR #189 — assertion-block count inside each `tests/<fixture>/run.sh` fixture acts as the coverage proxy. The kiln-test harness CANNOT discover pure-shell `run.sh` fixtures (substrate gap B-1 from PR #166 + #168 blockers.md) — this is EXPLICITLY accepted for V1; do NOT silently downgrade to harness-discoverable `test.yaml` fixtures. Each new fixture MUST contain ≥4 distinct `assert_*` invocations to meet the proxy threshold.

- **NFR-005** (back-compat additivity): No existing skill, script, or template changes behavior. The ledger is purely additive: absence of the new skill MUST leave `/kiln:kiln-next`, `/kiln:kiln-distill`, `/kiln:kiln-build-prd`, and every other shipped skill byte-identical in behavior. Verified by SC-004 backward-compat fixture.

### Key Entities

- **Mistake row** — produced by `read-mistakes.sh` from one file in `.kiln/mistakes/<YYYY-MM-DD>-<slug>.md`. NDJSON shape: `{"date":"<YYYY-MM-DD>","type":"mistake","source":".kiln/mistakes/<file>","summary":"<≤120ch>","resolution":""}`.
- **Proposal row** — produced by `read-proposals.sh`. NDJSON shape: `{"date":"<YYYY-MM-DD>","type":"proposal-open|proposal-applied","source":"@inbox/open/<file>|@inbox/applied/<file>","summary":"<≤120ch>","resolution":"<commit-hash>|"}`. The `resolution` field is populated for `proposal-applied` rows only (links to the commit body that referenced the proposal).
- **Edit row** — produced by `read-edits.sh` from one `git log` commit matching `MANIFEST_EDIT_PATTERNS`. NDJSON shape: `{"date":"<YYYY-MM-DD>","type":"edit","source":"<commit-hash>","summary":"<commit-subject>(+<N> manifest files)","resolution":"<proposal-path>|"}`. The `resolution` field is populated only when the commit body contains a parseable `applies inbox/{open,applied}/<path>` reference (R-1 mitigation).
- **Ledger report file** — Markdown file at `.kiln/logs/ledger-<YYYY-MM-DD-HHMMSS>.md`. Sections: H1 title, optional `Substrates included:` banner (NFR-002), `## Events` (the table), `## Notes` (zero-row substrates, missing-link aggregate row, fallback notes).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** (V1 chronological emission): `plugin-kiln/tests/ledger-chronological-emission/run.sh` passes. Asserts (a) a 6-event corpus (2 mistakes, 2 proposals, 2 edits) renders 6 rows sorted date-descending, (b) `.kiln/logs/ledger-<timestamp>.md` is created, (c) stdout is byte-identical to the file (FR-004), (d) re-running on unchanged inputs produces a byte-identical report (NFR-001 — H1 timestamp excepted).

- **SC-002** (filter shape AND-combined): `plugin-kiln/tests/ledger-filter-shape/run.sh` passes. Asserts (a) `--type edit --since 2026-04-20` against the SC-001 corpus emits ONLY `edit` rows where `date >= 2026-04-20`, (b) `--type mistake --since 2026-04-15` is empty when the only mistake predates 2026-04-15, (c) `--substrate mistakes,edits` skips proposals entirely.

- **SC-003** (degraded-substrate graceful exit): `plugin-kiln/tests/ledger-degraded-substrate/run.sh` passes. Stubs `read-proposals.sh` to exit non-zero. Asserts (a) skill exits 0, (b) report contains the verbatim NFR-002 banner with reason `shelf unavailable, proposals omitted`, (c) no `proposal-*` rows in the events table, (d) `mistake` and `edit` rows still render.

- **SC-004** (back-compat additivity): `plugin-kiln/tests/ledger-back-compat/run.sh` passes. Asserts (a) `git diff --stat HEAD~N -- plugin-kiln/skills/` against the pre-PRD revision touches ONLY new paths under `plugin-kiln/skills/kiln-ledger/`, `plugin-kiln/scripts/ledger/`, `plugin-kiln/tests/ledger-*/`; no edits to existing skills/scripts (NFR-005 enforcement). Verified by `diff --stat` over a stub pre/post tree.

- **SC-005** (proposal-edit linking): `plugin-kiln/tests/ledger-proposal-edit-linking/run.sh` passes. Fixture creates one synthetic proposal at `@inbox/applied/2026-04-15-foo.md` AND one synthetic commit whose body contains `applies inbox/applied/2026-04-15-foo.md`. Asserts (a) the `proposal-applied` row's `resolution-link` column contains the commit hash, (b) the `edit` row's `resolution-link` column contains the proposal path, (c) for an edit commit lacking the back-reference, the `resolution-link` renders as `—` AND the Notes section reports `<K> edits found, <J> lacked proposal back-references`.

- **SC-006** (orchestrator-reader split survives reader-add): `plugin-kiln/tests/ledger-orchestrator-reader-split/run.sh` passes. Asserts via `git diff --stat` simulation that adding a hypothetical `read-feedback-resolutions.sh` reader requires editing ONLY (a) the new reader script, (b) the orchestrator's substrate-list constant in SKILL.md, (c) a new test fixture. `render-timeline.sh` is byte-identical pre/post (FR-006 architectural enforcement).

## Open Questions

(Decisions resolved by specifier per team-lead's brief — auditor verifies alignment.)

- **OQ-1** (manifest-edit pattern set): RESOLVED — anchor on the FR-007 list (`chore(claude-md):`, `pi-apply:`, `chore(roadmap):`, `chore: apply manifest improvement`). The maintenance contract is documented in FR-007: pattern additions = one-line edit to `MANIFEST_EDIT_PATTERNS` in `read-edits.sh` PLUS a per-reader PR. Future patterns surfacing in real corpora become per-reader PRs, NOT skill rewrites.

- **OQ-2** (edit-row deduplication): RESOLVED — ONE row per commit. Multi-file edits aggregate the affected manifest files in the `summary` column (e.g., `claude-md+skill-md`). Per-file granularity is explicitly deferred to V2; if maintainer feedback after 30 days surfaces "I need per-file rows for triage," V2 PRD revisits. Rationale: per-commit rows match the natural unit of the underlying capture (commits, not file changes) and avoid noise from rebase-style multi-file edits.

- **OQ-3** (ledger-as-file vs derived view): RESOLVED — V1 is purely derived. NO `.kiln/ledger/*.md` artifact is written; the only persisted output is the per-run audit log under `.kiln/logs/ledger-<timestamp>.md` (FR-004). Performance has not been profiled; the file-based-state principle wins for V1. If V1 use surfaces "this report takes 30+ seconds to render," V2 PRD revisits with concrete profile data.

## Assumptions

- The maintainer's environment has `bash` ≥ 4, `jq`, `git`, and shelf-MCP wiring functional in the calling Claude Code session. Headless / CI use cases pass `--substrate mistakes,edits` to opt out of MCP entirely.
- The shelf reader uses the same MCP substrate that `/kiln:kiln-mistake` and `shelf:shelf-propose-manifest-improvement` already use; no new MCP client/tool/auth is introduced (NFR-003).
- Manifest-edit commits have author dates within ±5 minutes of committer dates in normal day-to-day use; rebase-driven divergence is rare and surfaces in Notes if observed (edge case).
- The maintainer is the sole consumer for V1 — multi-tenant ledger views are out of scope.
- The orchestrator + per-extractor-script architectural pattern from PR #193 Theme D is reusable verbatim (same tooling: `bash` + `jq` + `git`; no Node/Python).

## Dependencies & Risks

- **D-1** (FR-006 architectural reuse): Implementation reuses the orchestrator-reader pattern from `plugin-kiln/scripts/metrics/extract-signal-<a..h>.sh` (PR #193 Theme D). No re-design required — the precedent is the template.
- **D-2** (FR-001 substrate read): The shelf MCP read path used by `read-proposals.sh` depends on the same shim that `/kiln:kiln-mistake` already exercises. No new MCP wiring required.
- **R-1** (proposal-edit linkage heuristic — PRD R-1): Edit commits don't always reference their source proposal in the body. Mitigation: when no `applies inbox/{open,applied}/<path>` token is detectable, the edit row's `resolution-link` is `—` AND the Notes section surfaces the missing-link aggregate. The PRD flags this as a future-V2 input — if the missing-link rate is high, future commits should adopt a stricter convention.
- **R-2** (shelf MCP brittleness in CI/headless — PRD R-2): `read-proposals.sh` depends on Obsidian MCP being available in the calling session. Mitigation: the `--substrate` flag (FR-003) explicitly supports opting out; CI/smoke tests pass `--substrate mistakes,edits`. The skill never hard-fails on MCP absence (FR-005).
- **R-3** (V2 fingerprinting design uncertainty — PRD R-3): Recurrence detection is the highest-value V2 feature but requires a design choice (LLM call per mistake / schema tag / embedding cluster). Mitigation: V1 ships without it. After 30 days of V1 use, write a separate PRD with concrete recurrence-detection requirements informed by the actual mistake corpus.
- **R-4** (substrate gap B-1 — kiln-test harness can't discover pure-shell run.sh): NFR-004 explicitly accepts the run.sh-only pattern with assertion-block counts as the coverage proxy. Documented in `blockers.md` if any test-substrate downgrade is attempted by the implementer.

## Substrate gap (B-1) carve-out

Per PR #166 + #168 blockers.md and explicit team-lead direction in this brief, the kiln-test harness cannot discover pure-shell `run.sh` fixtures. NFR-004 codifies the run.sh-only acceptance with assertion-block count as the coverage proxy. The implementer MUST NOT silently downgrade to a harness-discoverable `test.yaml` fixture; if they wish to, that's a separate spec change. This carve-out is recorded so the auditor verifies it survives implementation.
