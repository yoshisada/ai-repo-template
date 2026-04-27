---
derived_from:
  - .kiln/roadmap/items/2026-04-24-manifest-evolution-ledger.md
distilled_date: 2026-04-27
theme: manifest-evolution-ledger
---
# Feature PRD: Manifest-Evolution Ledger — V1 Pure-History View

**Date**: 2026-04-27
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Vision win-condition (d) — *"the self-improvement loop closes"* — is currently unfalsifiable. Captures land in three substrates: `/kiln:kiln-mistake` writes to `.kiln/mistakes/`, shelf's manifest-improvement subroutine files proposals in Obsidian's `@inbox/open/` (graduating to `@inbox/applied/`), and manifest edits show up as commits in `git log` with conventional patterns (e.g., `chore(claude-md):`, `pi-apply:`). The data exists in three places; nothing reads them longitudinally as a single timeline. Without a longitudinal view, the maintainer can't tell whether the loop is closing — whether captured mistakes are leading to applied proposals, whether applied proposals are reducing recurrence, whether the system is actually self-improving or just accumulating capture artifacts.

Recently the roadmap surfaced this item in the **10-self-optimization** phase: `2026-04-24-manifest-evolution-ledger` (feature). Its sibling observability features — `2026-04-24-escalation-audit` (shipped via PR #189) and `2026-04-24-retro-quality-auditor` (shipped/stale per state field) — established the pattern that observability features can be standalone skills rather than a unified observability framework. This PRD adopts that pattern: ship the ledger as its own skill, defer the unified-observability-layer question to a future cross-cutting PRD if/when a third or fourth observability feature surfaces.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Manifest-evolution ledger — close the self-improvement loop](../../../.kiln/roadmap/items/2026-04-24-manifest-evolution-ledger.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |

## Problem Statement

Three concrete frictions:

1. **Captures pile up; nothing reads them.** `.kiln/mistakes/` accumulates one file per `/kiln:kiln-mistake` invocation. `@inbox/open/` accumulates manifest-improvement proposals. Manifest edits land as commits. Each substrate is queryable on its own — `ls`, MCP read, `git log` — but no view stitches them into a single chronological timeline. The maintainer who wants to ask "what's been happening to the manifests this week?" has no answer surface.

2. **The "did the proposal land?" question is manual.** A proposal in `@inbox/open/` graduates (or doesn't). When it graduates, the corresponding manifest edit lands as a commit. Without a ledger, the maintainer has to manually trace each `@inbox/applied/` entry back to the commit that applied it. The trace is doable but slow — a per-proposal grep — and the friction discourages doing it at all.

3. **Recurrence is invisible.** Even when a proposal lands, the maintainer can't easily check whether the same mistake class recurs after the edit. Did the auto-flip-on-merge proposal actually stop the manual flip-after-merge mistake? The data is there (in `.kiln/mistakes/` after-the-fact captures), but the comparison is manual and the cognitive cost discourages running it.

V1 of the ledger addresses problems 1 and 2 directly: chronological view + per-event source links. Problem 3 (recurrence detection) is explicitly deferred to V2 — see Non-Goals — because semantically fingerprinting "the same mistake class" requires a design we don't have yet (LLM call per mistake? schema-tagged class field? embedding-based clustering?). The roadmap item itself flags this: *"Mistake fingerprinting — and the broader question of whether this is one feature or part of a larger 'kiln observability' workstream"* is the hardest part. V1 makes the loop visible; V2 (separate PRD) can add fingerprinting once we have a month of V1 use to sharpen the requirements.

## Goals

- **Make the loop visible**: a single chronological view that shows mistakes, proposals, and manifest edits as a unified timeline.
- **Make the trace cheap**: per-event source links + commit hashes so the maintainer can drill from "this proposal" to "this edit" in one click.
- **Stay observation-only**: V1 reads, doesn't write. No auto-proposals, no recurrence flagging, no nudges.
- **Ship the cheaper version explicitly**: the roadmap item's own "Cheaper version" section is the V1 scope. V2 is a separate PRD.
- **Survive missing substrates gracefully**: if shelf MCP is unavailable or `.kiln/mistakes/` is empty, the ledger still emits — partial views are valid views.

## Non-Goals

- **NOT recurrence detection**. Whether mistake X recurred after proposal Y landed is V2. V1 lists events; the maintainer eyeballs.
- **NOT auto-proposal generation**. The closed-loop "if recurrence persists, generate a new proposal" path is V2's autonomous promise; V1 is reported-only.
- **NOT a unified observability layer**. Escalation-audit and retro-quality-auditor shipped as standalone skills; this ledger does the same. The cross-cutting "observability framework" abstraction is deferred indefinitely — wait until a fourth observability feature surfaces before generalizing.
- **NOT a stored ledger artifact**. V1 computes the view at read time from existing substrates (`.kiln/mistakes/*.md`, shelf MCP, `git log`). No `.kiln/ledger/*.md` write-back. File-based-state principle wins; if performance matters in V2, revisit.
- **NOT a `/kiln:kiln-next` integration**. Standalone `/kiln:kiln-ledger` only in V1; surfacing the ledger inside session-pickup is V2 once we know how the report is actually used.
- **NOT a shelf-write-back dependency**. The ledger reads shelf state via MCP if available; if MCP is down, shelf-sourced rows are marked `(shelf unavailable)` and the ledger still emits. No hard dep.

## Requirements

### Functional Requirements

- **FR-001** (from: `2026-04-24-manifest-evolution-ledger.md`): A new skill `/kiln:kiln-ledger` MUST walk three substrates and emit a chronological timeline:
  - `.kiln/mistakes/*.md` — one row per `/kiln:kiln-mistake` capture
  - Shelf `@inbox/open/*.md` AND `@inbox/applied/*.md` (read via Obsidian MCP) — one row per manifest-improvement proposal
  - Git log filtered to commits matching configured manifest-edit patterns — one row per landed edit

- **FR-002** (from: `2026-04-24-manifest-evolution-ledger.md`): The timeline MUST emit a tabular report with columns: `date | type (mistake / proposal-open / proposal-applied / edit) | source-link | summary | resolution-link`. The `resolution-link` column is empty for `mistake` and `proposal-open` rows; for `proposal-applied` rows it links to the commit that landed the edit; for `edit` rows it back-links to the proposal (if any) the edit references in its commit body.

- **FR-003** (from: `2026-04-24-manifest-evolution-ledger.md`): The skill MUST accept these filter flags:
  - `--since <YYYY-MM-DD>` — restrict timeline to events on/after the date (default: 30 days ago)
  - `--type <mistake|proposal|edit|all>` — filter by event type (default: all)
  - `--substrate <mistakes|proposals|edits|all>` — opt out of a substrate (e.g., `--substrate mistakes,edits` skips proposals when shelf MCP is broken)
  Filters are AND-combined.

- **FR-004** (from: `2026-04-24-manifest-evolution-ledger.md`): The skill MUST write the report to BOTH stdout AND `.kiln/logs/ledger-<YYYY-MM-DD-HHMMSS>.md`. The log file is the audit trail; stdout is the user-facing surface.

- **FR-005** (from: `2026-04-24-manifest-evolution-ledger.md`): The skill MUST degrade gracefully when a substrate cannot be read:
  - `.kiln/mistakes/` missing or empty → no mistake rows, no error
  - Obsidian MCP unavailable → no proposal rows, single warning row in the report: `(shelf unavailable — proposals omitted)`
  - Git log returns nothing matching → no edit rows, no error
  Skill exits 0 in all degraded cases. Error-only (exit 1) is reserved for malformed flags.

- **FR-006** (from: `2026-04-24-manifest-evolution-ledger.md`): The skill MUST be implemented as an orchestrator script + per-substrate readers under `plugin-kiln/scripts/ledger/`:
  - `read-mistakes.sh` — emits NDJSON rows from `.kiln/mistakes/*.md`
  - `read-proposals.sh` — emits NDJSON rows from `@inbox/open/` + `@inbox/applied/` via shelf MCP
  - `read-edits.sh` — emits NDJSON rows from `git log` filtered by manifest-edit patterns
  - `render-timeline.sh` — sorts the unified NDJSON by date and emits the markdown table
  This makes adding/swapping substrates a per-reader PR rather than a skill rewrite (same architectural pattern as `extract-signal-<a..h>.sh` shipped via PR #193's Theme D).

- **FR-007** (from: `2026-04-24-manifest-evolution-ledger.md`): Manifest-edit pattern detection MUST be configured in a single shell list constant inside `read-edits.sh` (initially: `chore(claude-md):`, `pi-apply:`, `chore(roadmap):`, `chore: apply manifest improvement`). Adding patterns is a one-line edit; the configuration MUST be discoverable via `grep MANIFEST_EDIT_PATTERNS plugin-kiln/scripts/ledger/`.

### Non-Functional Requirements

- **NFR-001** (determinism): Same `--since` + `--substrate` against unchanged repo state MUST produce byte-identical output. Sort key is event date (descending) with stable tiebreak on source path. The render path MUST run under `LC_ALL=C` for cross-platform byte-identity.

- **NFR-002** (graceful degrade is observable): When a substrate is omitted via degradation (FR-005), the report MUST surface that fact in a single-line section above the table: `Substrates included: mistakes, edits — (shelf unavailable, proposals omitted)`. Silent omission is a contract violation.

- **NFR-003** (shell-only V1): Implementation is bash + jq + git. No Python, no Node. Same substrate as `plugin-kiln/scripts/metrics/` (PR #193 Theme D) — pure-shell run.sh fixtures dominate.

- **NFR-004** (coverage gate): ≥80% coverage on new code, or per-test-substrate-hierarchy convention from PR #189 — count assertion blocks for shell-only fixtures (run.sh-only pattern; kiln-test harness can't discover these — known substrate gap).

- **NFR-005** (back-compat): No existing skill or script changes behavior. The ledger is purely additive; absence of the new skill leaves the prior session pickup, distill, build-prd flows byte-identical.

## User Stories

- **As the maintainer monthly**, I run `/kiln:kiln-ledger --since 2026-04-01` and get a chronological timeline of every manifest-related event in April. I see mistakes captured, proposals filed, edits landed — and which proposal each edit traces back to. The loop is visible.

- **As the maintainer after a `/kiln:kiln-pi-apply` run**, I run `/kiln:kiln-ledger --type edit --since <last week>` and verify which of the proposed edits actually landed. The trace is one click per row, not a per-proposal manual grep.

- **As the maintainer with a flaky shelf MCP**, I run `/kiln:kiln-ledger --substrate mistakes,edits` and get a partial timeline that skips proposals entirely. The skill degrades cleanly — no MCP error spam, no blocked output.

## Success Criteria

- **SC-001** (V1 chronological emission): Running `/kiln:kiln-ledger` against this repo on the day the PRD ships emits a non-empty markdown table with at least one row from each substrate currently populated (mistakes, proposals, edits). Verified by running the skill and inspecting `.kiln/logs/ledger-<timestamp>.md`.

- **SC-002** (filter shape): `/kiln:kiln-ledger --since 2026-04-01 --type mistake` emits ONLY rows where `type == mistake` AND `date >= 2026-04-01`. Verified via `awk` over the emitted log file.

- **SC-003** (degraded-substrate graceful exit): Running with a deliberately broken Obsidian MCP config (or `MCP_SHELF_DISABLED=1` env var) emits a partial report with the verbatim degraded-substrate banner (NFR-002) and exits 0. Verified via fixture that stubs `read-proposals.sh` to fail.

- **SC-004** (back-compat): A regression fixture asserts that the absence of the new skill leaves the prior session-pickup + distill + build-prd flows byte-identical (no shared script touched). Captured via fixture: pre-PRD `/kiln:kiln-next` output vs post-PRD on the same fixture project.

- **SC-005** (proposal-edit linking): When an edit commit body references a proposal id (e.g., `applies inbox/open/2026-04-15-foo.md`), the ledger's `proposal-applied` row's `resolution-link` column points to the commit hash AND the edit row's `resolution-link` back-points to the proposal. Verified via fixture with a synthetic commit + proposal pair.

- **SC-006** (orchestrator-reader split): Adding a new substrate (e.g., `read-feedback-resolutions.sh`) requires editing only the orchestrator's substrate-list constant and adding the new reader script. No render-pipeline changes needed. Verified by spec inspection (FR-006 scaffolding survives a `git diff --stat` after a hypothetical reader-add patch).

## Tech Stack

Inherited from parent PRD. No additions. Implementation is bash + jq + git, plus Obsidian MCP read calls for the proposals substrate (same shelf MCP substrate that `/kiln:kiln-mistake` and `shelf-propose-manifest-improvement` already use). The orchestrator + per-substrate reader pattern reuses the architectural template established by `plugin-kiln/scripts/metrics/` in PR #193.

## Risks & Open Questions

- **R-1** (proposal-edit linkage heuristic): FR-007 + SC-005 assume edit commits reference their source proposal in the commit body. In practice, `pi-apply:` commits do; `chore(claude-md):` and ad-hoc manifest edits often don't. Mitigation: when no link is detectable, the edit row's `resolution-link` column is `—`. The ledger surfaces the missing-link rate in the degraded-substrate banner: `12 edits found, 4 lacked proposal back-references`. This becomes a V2 input — if the missing-link rate is high, future commits should adopt a stricter convention.

- **R-2** (shelf MCP brittleness in CI/headless): The `read-proposals.sh` reader depends on Obsidian MCP being available in the calling session. CI runs and headless smoke tests don't have MCP. Mitigation: the `--substrate` flag (FR-003) explicitly supports opting out; CI/smoke tests pass `--substrate mistakes,edits`. The skill never hard-fails on MCP absence.

- **R-3** (V2 fingerprinting design uncertainty): Recurrence detection is the highest-value V2 feature but requires a design choice (LLM call per mistake / schema tag / embedding cluster). Mitigation: V1 ships without it. After 30 days of V1 use, write a separate PRD with concrete recurrence-detection requirements informed by the actual mistake corpus.

- **OQ-1** (manifest-edit pattern set): The initial pattern set in FR-007 (`chore(claude-md):`, `pi-apply:`, `chore(roadmap):`, `chore: apply manifest improvement`) is best-guess. Some real manifest edits will use other prefixes. Spec.md should anchor on the pattern table and call out the maintenance contract: pattern additions require a per-reader PR, NOT a skill rewrite.

- **OQ-2** (edit-row deduplication): If a single commit lands multiple manifest edits (e.g., a pi-apply commit that touches CLAUDE.md AND a SKILL.md), should the ledger emit one row per file or one row per commit? Defer to specifier — both shapes are valid. Suggest one row per commit, with the affected-files listed in the `summary` column; per-file granularity is a V2 ergonomic if asked for.

- **OQ-3** (ledger-as-file vs derived view): Non-Goals explicitly forbid V1 from writing a `.kiln/ledger/*.md` artifact — file-based-state principle pulls toward derived. Performance has not been profiled. If V1 use surfaces "this report takes 30+ seconds to render," V2 should revisit; but V1 ships pure-derived to avoid premature optimization.

---

## Dependency note

This PRD assumes:
- PR #189 (escalation-audit) has shipped its observability-as-standalone-skill pattern — adopted here.
- PR #193 (vision-tooling) has shipped the orchestrator + per-extractor-script architecture — reused as the FR-006 template.

Both are MERGED (PR #189) or PENDING-MERGE (PR #193). The PRD does NOT block on either — it can ship at any time after both PRs are in.
