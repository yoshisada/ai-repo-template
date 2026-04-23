# Phase R — CLAUDE.md reference inventory

**Date**: 2026-04-23
**Owner**: impl-claude-audit
**Purpose**: Catalog the places across this repo that cite `CLAUDE.md` by name or by section header so the `load-bearing-section` rubric rule has a concrete set to protect. Scratch-only — not shipped in the plugin.

## Method

```
grep -rln "CLAUDE\\.md\\|CLAUDE_MD" plugin-kiln/skills plugin-kiln/agents plugin-kiln/hooks plugin-kiln/workflows
grep -rln "CLAUDE\\.md\\|CLAUDE_MD" plugin-shelf plugin-clay plugin-trim plugin-wheel
grep -rln "CLAUDE\\.md" templates/
grep -n  "CLAUDE\\.md" <every-hit>
```

## Direct filename citations

| File | Line | Context | Load-bearing? |
|---|---|---|---|
| `plugin-kiln/skills/kiln-fix/SKILL.md` | 289 | "Hardcoding a repo-relative shelf path is a portability bug per `CLAUDE.md`." | **YES** — cites the "Plugin workflow portability" section. |
| `plugin-kiln/skills/kiln-init/SKILL.md` | 27, 65, 139, 143, 161 | Detects / writes / lists `CLAUDE.md` as a scaffold artifact. | **YES** — filename-level, not section-level. |
| `plugin-kiln/hooks/version-increment.sh` | 27 | Filename allow-list for edits that don't bump VERSION. | No — treats filename as a glob pattern only. |
| `plugin-kiln/hooks/require-spec.sh` | 73 | Same — always-allow edit pattern. | No — glob only. |
| `plugin-clay/skills/clay-create-repo/SKILL.md` | 199, 273 | Instructs the scaffold step to create a `CLAUDE.md`. | No — creation-side reference, not content citation. |
| `plugin-shelf/docs/PRD.md` | 350 | Idea note ("Auto-run `/shelf-feedback` at session start"). | No — not a content dependency. |

## Section-header citations (load-bearing set)

Searched for the current `## ...` headings in CLAUDE.md across plugin files. None of the section headers (`What This Repo Is`, `Quick Start`, `Build & Development`, `Architecture`, `Mandatory Workflow`, `Hooks Enforcement`, `Available Commands`, `Recent Changes`, `Active Technologies`, `Implementation Rules`, `Versioning`, `Security`, `Plugin workflow portability`) are grep-cited by name from anywhere under `plugin-*/skills`, `plugin-*/agents`, `plugin-*/hooks`, or `plugin-*/workflows`.

**Interpretation**: the only section in the source-repo `CLAUDE.md` that is cited by name in-repo is "Plugin workflow portability" (cited by `kiln-fix/SKILL.md` via the phrase "portability bug per `CLAUDE.md`"). Everything else is narrative-only — no skill reads the section, no hook greps for it.

## Load-bearing set (final — protected by rubric rule `load-bearing-section`)

- `## Plugin workflow portability (NON-NEGOTIABLE)` — cited by `plugin-kiln/skills/kiln-fix/SKILL.md:289`.
- `## Security` — cited structurally by the `.env`-blocking hook policy (not by name, but the content is enforced elsewhere; including it defensively because its removal would strip user-visible guidance even if nothing greps it).

Everything else in the current CLAUDE.md is prose-only and fair game for the other rubric rules (freshness, duplication, editorial).

## Discovery from non-skill files (NFR-004)

```
grep -rn plugin-kiln/rubrics/claude-md-usefulness.md specs/ plugin-*/ docs/
```

Expected hits (as of Phase R completion): `specs/kiln-self-maintenance/spec.md`, `specs/kiln-self-maintenance/plan.md`, `specs/kiln-self-maintenance/contracts/interfaces.md`, `specs/kiln-self-maintenance/tasks.md`. Recorded in T003.

**T003 result (2026-04-23)**: 16 hits, spanning `specs/kiln-self-maintenance/{spec.md,plan.md,tasks.md,contracts/interfaces.md}` and `docs/features/2026-04-23-kiln-self-maintenance/PRD.md`, plus the inventory note itself. NFR-004 (grep-discoverable from non-skill files) is satisfied — 5+ references outside `plugin-kiln/skills/`.
