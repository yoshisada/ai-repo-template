# Research Notes: Coach-Driven Capture Ergonomics

**Feature Branch**: `build/coach-driven-capture-ergonomics-20260424`
**Date**: 2026-04-24

Short, implementation-shaping notes. Full rationale lives in spec.md Clarifications; this file captures how each clarification lands in code.

## 1. Fixture approach for `/kiln:kiln-test`

- Reuse `plugin-kiln/tests/` substrate (already in place — see `plugin-kiln/tests/kiln-distill-basic/` + `kiln-hygiene-backfill-idempotent/`).
- Each feature area gets **one happy-path** fixture + **one edge-case** fixture:
  - `project-context-reader-determinism/` — happy path: populated repo, run reader twice, diff stdout. Edge case: missing vision + empty roadmap.
  - `roadmap-coached-interview-basic/` — happy path: orientation + accept-all completes item. Edge case: empty snapshot → graceful `[suggestion: —]` placeholders.
  - `roadmap-vision-first-run/` — happy path: draft all four sections. Edge case: partial snapshot (no items) — annotate missing-evidence.
  - `roadmap-vision-re-run/` — happy path: per-section diff + `last_updated:` bump. Edge case: no drift → prints "no drift detected" + no bump.
  - `claude-audit-project-context/` — happy path: phase-drift cited. Edge case: cache >30 days old → staleness flag.
  - `distill-multi-theme/` — happy path: 2 themes → 2 PRDs + run-plan. Edge case: slug collision → numeric suffix.
- Fixtures live under `plugin-kiln/tests/<test-name>/fixture/` with a `run.sh` + `expected/` tree (matching existing harness convention).

## 2. JSON parsing strategy in skill bodies

- All parsing uses `jq` inline in SKILL.md code blocks. No helper functions beyond those in contracts/interfaces.md.
- Exact `jq` queries are specified in the contract's "Call Sites" section so all three implementers use identical queries. This pins the field names and prevents drift.
- Where a skill needs multiple field extractions, chain one `jq` per line (readability over perf — reader output is already in memory).

## 3. External best-practices cache strategy

- Single Markdown file: `plugin-kiln/rubrics/claude-md-best-practices.md`.
- Frontmatter carries `source_url:`, `fetched:`, and `cache_ttl_days:`.
- Initial population: impl-vision-audit commits a hand-curated snapshot with `fetched: 2026-04-24`. Live fetch is opportunistic — on every `/kiln:kiln-claude-audit` invocation, the skill `WebFetch`es the URL; on success, rewrites the cache; on failure, uses existing cache and logs `cache used, network unreachable`.
- Staleness threshold: 30 days. Flagged in the preview log but does not block the audit.
- **Offline-first default**: tests and normal operation MUST NOT require network access. The `WebFetch` branch is best-effort.

## 4. Slug disambiguation algorithm (FR-017)

Given selection order (preserved from user input) and `<date>`:

```
seen = {}
collision_counts = {}
for slug in selection:
    key = f"{date}-{slug}"
    if key not in seen:
        # check docs/features/ for pre-existing directory too
        if os.path.isdir(f"docs/features/{key}"):
            # collision with committed PRD — skip to numeric suffix
            collision_counts[slug] = collision_counts.get(slug, 1) + 1
            emit(f"{key}-{collision_counts[slug]}")
        else:
            seen[key] = True
            collision_counts[slug] = 1
            emit(key)
    else:
        collision_counts[slug] += 1
        emit(f"{key}-{collision_counts[slug]}")
```

Implementation is in Bash — see `disambiguate-slug.sh` contract. Output preserves input order so the loop consuming directories stays aligned with the `SELECTED` list.

## 5. Per-section vision diff grouping (spec Clarification #2)

- Four vision sections: `## Mission`, `## What we are building`, `## What we are not building`, `## Current phase`.
- Re-run diff builds a list of proposed edits scoped per section.
- Prompt format (per section):
  ```
  ### Section: <name> (N proposed edits)
  [a] accept all edits in this section
  [r] reject all edits in this section
  [s] step through edits one-by-one
  ```
- Global shortcuts: `A` (accept all sections), `R` (reject all sections), `Q` (quit, discard pending edits).
- `last_updated:` bumps iff ≥1 edit was accepted anywhere (FR-010).

## 6. Tone rewrite scope (FR-007 / PRD FR-006)

- Only the `/kiln:kiln-roadmap` item-capture prompt text (non-`--quick`, non-`--vision`, non-`--check`, non-`--reclassify` paths) is rewritten.
- Specifically: the question headers and the inter-question transitions get collaborative framing ("Here's what I think — tell me if I'm off"; "Skip or tweak — whichever is faster").
- Validation: PRD audit review of the SKILL.md diff. Not a unit test.

## 7. Why three implementer tracks, not one

- The reader is the load-bearing dependency, but the consuming SKILL.md edits are independent markdown rewrites with no shared code paths.
- Tracks B and C can stub `CTX_JSON` with a fixture file locally until Track A lands the real script.
- Sync happens at the interface contract boundary — not through shared code.

## 8. Hook safety (NFR-006)

- Existing PreToolUse hooks (`require-spec.sh`, `version-increment.sh`, `block-env-commit.sh`, `require-feature-branch.sh`) are unchanged.
- New scripts under `plugin-kiln/scripts/context/` are called only from skill bodies — never from hooks. This keeps hook overhead flat.

## 9. Dependencies confirmed

- `jq` 1.6+ already required by plugin-kiln — no new system dependency.
- `WebFetch` is optional at runtime (FR-015 cache fallback always available).
- `plugin-kiln/scripts/roadmap/` helpers are used read-only by the new reader.
