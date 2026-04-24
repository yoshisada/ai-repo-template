# Roadmap Backfill Methodology

**Goal**: seed `.kiln/roadmap/` with items representing already-completed product work, so the roadmap system has real history to compare against from day one. Designed to become a skill / task / subagent (`/kiln:kiln-roadmap-backfill`) in the future.

**Session that produced this doc**: 2026-04-24 design chat that created the `2026-04-23-structured-roadmap` PRD.

## Principles

1. **Minimize reads.** Don't open every PRD body. Use directory names, slugs, and git-log commit subjects as the primary signal source. Feature PRDs are pre-structured; their directory slug is usually enough to classify.
2. **Plugin structure + feature dirs beat deep reads.** `ls plugin-*/` tells you what exists now; `ls docs/features/` tells you what was intentionally planned; `git log --oneline --no-merges` tells you what shipped. Union of those three is the backfill source.
3. **Retro phasing is clustering, not planning.** Don't try to reconstruct "what was the plan at the time" — group by observed theme + date window and give each cluster a clear name.
4. **Ship defaults before perfection.** Hand-write the minimum frontmatter to be schema-correct; leave detail slots (`implementation_hints`, `addresses`, `depends_on`) empty for backfilled items unless they're obvious from the slug.
5. **Generate, don't hand-type.** 40+ feature dirs × by-hand frontmatter is a day's work. Templated bash generation is the right tool.

## Source-of-truth priority

1. `docs/features/<YYYY-MM-DD>-<slug>/` — one directory ≈ one roadmap item. Use the date prefix and slug as item `id` + `title` seed.
2. `git log --oneline --no-merges` — determines `status` (shipped vs in-flight). A feature dir whose slug appears in a `feat(` or `fix(` commit subject (or in a `(#<number>)` PR reference) is `status: shipped`. No matching commit → `status: in-progress`.
3. `plugin-*/` directories — validates that the plugin exists and confirms multi-plugin features. Doesn't generate items directly.
4. `.kiln/issues/completed/` — NOT consulted in the backfill. Completed issues map to items only when they directly correspond to a feature dir; otherwise they're tactical fixes that don't belong in the roadmap layer.

## Clustering into phases

Cluster feature slugs by theme + date window. Good phase names describe the dominant theme, not the timeframe. Typical first-pass clusters for this repo (2026-03-31 through 2026-04-24):

- **foundations-kiln-core** — initial kiln skills, pipeline, QA templates, rebrand. Late March through early April.
- **wheel-engine** — wheel plugin creation + hardening. Early-to-mid April.
- **shelf-obsidian** — shelf plugin, shelf-config, sync iterations. Early-to-mid April.
- **plugin-clay** — clay plugin and idea flow. Mid April.
- **plugin-trim** — trim plugin, Penpot integration. Mid April.
- **developer-ergonomics** — cross-cutting tooling polish, plugin naming, mistake capture, fix-recording. Mid-to-late April.
- **feedback-loop-observability** — capture-surface skills, report-issue speedup, self-maintenance, hygiene audits. Late April.
- **in-flight** — PRDs written but not yet shipped. Current frontier.

## Item frontmatter shape (backfill-specific defaults)

```yaml
---
id: <YYYY-MM-DD>-<slug>                    # matches feature dir name
title: <slug humanized>                    # kebab-to-spaces, capitalize
kind: feature                              # overwhelmingly true for backfill
date: <YYYY-MM-DD>                         # from feature dir prefix
status: shipped | in-progress              # shipped if git-log shows a matching commit
state: shipped | distilled | specced       # shipped unless still in-flight
phase: <phase-slug>
blast_radius: feature                      # default for backfill; override if obviously infra
review_cost: moderate                      # default for backfill
context_cost: "1-3 sessions"               # default placeholder — no attempt to backfill accurate costs
source: backfill                           # marker that this item wasn't captured via the normal flow
---

Backfilled from docs/features/<YYYY-MM-DD>-<slug>/ on <backfill-date>.
```

Body is intentionally minimal: a one-liner pointing back at the feature dir. The PRD itself is the richer artifact; the roadmap item is a pointer.

## Explicit omissions for backfill

- **No `addresses:`** — historical items don't retroactively link to critiques; the critique system ships with v1 and applies forward.
- **No `depends_on:`** — reconstructing historical dependency graphs from slugs is error-prone; leave empty.
- **No `implementation_hints:`** — the PRD already contains them; backfilled items point at the PRD rather than duplicate.
- **No individual AI-native sizing estimates** — defaults only. Real sizing is a capture-time discipline; it can't be retrofitted honestly.

## Phase file shape (backfill)

```yaml
---
name: <phase-slug>
status: complete                           # for all historical phases
order: <integer>                           # chronological ordering across phases
started: <earliest-item-date>
completed: <latest-item-date>
---

<one-line phase description>

Items:
- <item-id>
- <item-id>
...
```

For the one currently-active phase (`in-flight`), `status: in-progress`, `completed` omitted, and items include the PRDs that are currently in-flight.

## Execution order (the backfill script's real algorithm)

1. List `docs/features/*/` directories. Sort by date prefix.
2. Grep `git log --oneline --no-merges` for each slug. Record `shipped` vs `in-progress`.
3. Propose phase clusters (this is the human-judgment step — the rest is mechanical). Document proposed phases inline.
4. Generate `.kiln/roadmap/phases/<phase>.md` files from the phase proposals.
5. Generate `.kiln/roadmap/items/<id>.md` files from the feature dir list using the frontmatter template above. One file per feature dir.
6. Hand-edit any items where the defaults are obviously wrong (e.g., infra features get `blast_radius: infra`).

## What to automate in the future skill

When this becomes `/kiln:kiln-roadmap-backfill`, these steps are mechanical and should be fully scripted:

- Feature-dir enumeration
- Git-log lookup per slug for status
- Item-file generation from template
- Phase-file skeleton creation

These should remain human-in-the-loop:

- Phase naming and clustering (propose + confirm)
- Outlier detection (items that don't fit any phase — surface for user judgment)
- Overrides for obvious defaults (blast_radius, review_cost, kind if not feature)

## Known limitations

- Features that shipped as part of a bundled commit (no dedicated slug in commit subject) may be mis-marked as `in-progress`. Review is cheap.
- Items dated by feature dir creation rather than merge date will be slightly off. Acceptable for retro phasing.
- Slug-to-title humanization is naive; sometimes produces awkward titles. Manual polish after generation is fine.
