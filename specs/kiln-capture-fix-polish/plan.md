# Implementation Plan: Kiln Capture-and-Fix Loop Polish

**Spec**: [spec.md](./spec.md)
**Date**: 2026-04-22

## Tech stack

Inherited from parent product — no additions:

- Markdown (skill definitions)
- Bash 5.x (inline Step 7 flow + existing helpers under `plugin-kiln/scripts/fix-recording/`)
- Obsidian MCP: `mcp__claude_ai_obsidian-projects__create_file` (fix notes), `mcp__claude_ai_obsidian-manifest__create_file` (reflect proposals)
- `jq` for JSON parsing (already assumed)
- `gh` CLI for optional repo-URL detection in `/kiln:kiln-feedback`

## Architectural approach

Four coherent areas, implementable in two parallel tracks after this plan lands:

- **Track 1 (impl-fix-polish)** owns Phases A and B — surgical edits to `plugin-kiln/skills/kiln-fix/SKILL.md` + deletions of two briefs + one helper.
- **Track 2 (impl-feedback-distill)** owns Phases C, D, and E — new skill, `git mv` rename + teach distill to read both sources, cross-reference sweep.
- **Track 3 (whichever implementer lands last)** owns Phase F — smoke-test documentation update.

Phases A, B, C, D, E touch disjoint file sets (see tasks.md); no cross-track file contention.

## Locked decisions

### Decision 1 — Reflect gate rule (spec FR-003)

**Decision: deterministic file-path gate, not inline judgment.**

Rationale: predictable token cost (NFR-003 caps at ~2k tokens), reproducible behavior, no flakiness from model mood. False negatives are acceptable — the maintainer can still propose a manifest improvement manually via `/shelf:shelf-propose-manifest-improvement` when the gate misses.

**Exact gate predicate** (main chat evaluates this against the composed envelope):

> Reflect fires if ANY of the following are true, else skip silently:
>
> 1. Any element of `envelope.files_changed` matches the glob `plugin-*/templates/*` OR `plugin-*/skills/*/SKILL.md`.
> 2. `envelope.issue` OR `envelope.root_cause` contains (case-insensitive) the substring `@manifest/` OR `manifest/types/`.
> 3. `envelope.fix_summary` names a template file by path (matches the same glob as condition 1 OR contains the literal substring `templates/`).

Implementers MAY express this as a single bash predicate. A reference implementation:

```bash
reflect_fires() {
  local env="$1"
  # Condition 1: template or SKILL.md touched
  if jq -e '.files_changed[]? | select(test("^plugin-[^/]+/(templates/|skills/[^/]+/SKILL\\.md$)"))' "$env" >/dev/null 2>&1; then
    return 0
  fi
  # Condition 2: @manifest/ or manifest/types/ named in issue/root_cause
  if jq -e '(.issue, .root_cause) | test("@manifest/|manifest/types/"; "i")' "$env" >/dev/null 2>&1; then
    return 0
  fi
  # Condition 3: fix_summary names a template path
  if jq -e '.fix_summary | test("plugin-[^/]+/templates/|(^|[^a-zA-Z])templates/")' "$env" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
```

Implementers MAY simplify or equivalently rewrite this predicate; any rewrite MUST preserve the three conditions above.

### Decision 2 — New skill name (spec FR-010)

**Decision: `/kiln:kiln-distill`.**

Rationale: grep across `plugin-kiln/`, `plugin-shelf/`, `plugin-clay/`, `plugin-trim/`, `plugin-wheel/`, and `workflows/` returned zero hits for `distill` or `kiln-distill`. No collision. The name is short, covers "bundle issues + feedback into a PRD" without overclaiming, and fits the `kiln-<verb>` convention used by `kiln-report-issue`, `kiln-mistake`, `kiln-fix`.

Directory: `plugin-kiln/skills/kiln-distill/SKILL.md`. Name in frontmatter: `kiln-distill`. The skill is `git mv`-renamed, not copied-then-deleted, to preserve git history.

### Decision 3 — Feedback frontmatter schema (spec FR-009)

**Decision: locked schema below.** Confirms the PRD's proposed taxonomy — no alternate values introduced.

```yaml
---
id: <YYYY-MM-DD>-<slug>                 # required; matches filename without .md extension
title: <human-readable one-line title>  # required
type: feedback                          # required; literal, not user-picked
date: <YYYY-MM-DD>                      # required; UTC date of creation
status: open                            # required on create; lifecycle: open → prd-created → completed
severity: low | medium | high | critical # required; four-value ordinal
area: mission | scope | ergonomics | architecture | other # required; five-value enum
repo: <URL> | null                      # required key; null when gh unavailable or no remote
prd: <path>                             # OPTIONAL; added by /kiln:kiln-distill when status flips to prd-created
files:                                  # OPTIONAL; array of detected file paths from the description; omitted when none
  - <path>
  - <path>
---

<free-form markdown body — the feedback description>
```

Comparison to `.kiln/issues/*.md` schema: matches the shape exactly, swapping `category: <free-form>` for `area: <enum>` and `priority: <blocking|high|...>` for `severity: <low|medium|high|critical>`. This keeps feedback visually distinct from issues while allowing distill to treat both as a uniform "backlog item" iterator.

Why keep distinct (not unify with issues): the PRD's "weight feedback higher" requirement (FR-012) is easier to implement against a literal `type: feedback` vs `type: issue` discriminator than against a blended schema. Per the PRD's own risk note on schema drift, prefer distinct until a second feedback-adjacent surface exists.

## Phase breakdown (implementer-owned)

### Phase A — `/kiln:kiln-fix` Step 7 inline refactor (impl-fix-polish)

Edits `plugin-kiln/skills/kiln-fix/SKILL.md` to replace Steps 7.5–7.9 with inline MCP calls. Deletes `team-briefs/` dir and `render-team-brief.sh`. Preserves `compose-envelope.sh`, `write-local-record.sh`, `resolve-project-name.sh`, `strip-credentials.sh`, `unique-filename.sh`.

### Phase B — `/kiln:kiln-fix` "What's Next?" (impl-fix-polish)

Adds a new "Step 8: What's Next?" section to `plugin-kiln/skills/kiln-fix/SKILL.md` and updates Step 5 / Step 6 / FR-006 fallback report template to emit the block on every terminal path. Uses the dynamic selection logic from Decision 1 of FR-008 (UI-adjacent → qa-final; escalation → report-issue; else → kiln-next).

### Phase C — `/kiln:kiln-feedback` skill (impl-feedback-distill)

Creates `plugin-kiln/skills/kiln-feedback/SKILL.md` parallel in shape to `plugin-kiln/skills/kiln-report-issue/SKILL.md` (much simpler — no wheel workflow, no background sync, just write the file). Follows the locked schema from Decision 3.

### Phase D — Distill rename + dual-source read (impl-feedback-distill)

`git mv plugin-kiln/skills/kiln-issue-to-prd plugin-kiln/skills/kiln-distill`. Update `name:` frontmatter. Teach Step 1 to read both `.kiln/issues/*.md` and `.kiln/feedback/*.md`. Teach Step 2 (theme grouping) to separate feedback vs issue themes. Teach Step 4 (PRD generation) to lead with feedback themes (FR-012). Teach Step 5 (status update) to update both sources.

### Phase E — Cross-reference sweep (impl-feedback-distill)

Update live references from `kiln-issue-to-prd` to `kiln-distill`. Known files (confirmed via grep): `plugin-kiln/agents/continuance.md:69`, `plugin-kiln/skills/kiln-next/SKILL.md:248` and `:342`, `docs/architecture.md:37,187,269`. Re-grep in the task body to catch anything added between now and implementation.

### Phase F — Smoke-test documentation (last implementer)

Append a short "Smoke test" note to `specs/kiln-capture-fix-polish/` or update the closing section of each changed skill with the SC-001/SC-002/SC-003/SC-004/SC-005/SC-006 smoke commands. Documentation-only — no code.

## Phase order & parallelism

- Phases A and B share the same file (`kiln-fix/SKILL.md`); run A first, then B, both by impl-fix-polish.
- Phases C, D, E run in order on the same track (impl-feedback-distill) because D's rename influences E's sweep targets.
- Tracks 1 (A+B) and 2 (C+D+E) run in parallel.
- Phase F runs last, assigned to whichever track finishes first (or the auditor if both finish together).

## File ownership (no cross-track writes)

| File                                                                       | Track |
|----------------------------------------------------------------------------|-------|
| `plugin-kiln/skills/kiln-fix/SKILL.md`                                     | 1     |
| `plugin-kiln/skills/kiln-fix/team-briefs/` (deleted)                       | 1     |
| `plugin-kiln/scripts/fix-recording/render-team-brief.sh` (deleted)         | 1     |
| `plugin-kiln/skills/kiln-feedback/SKILL.md` (new)                          | 2     |
| `plugin-kiln/skills/kiln-issue-to-prd/` → `plugin-kiln/skills/kiln-distill/` | 2     |
| `plugin-kiln/agents/continuance.md`                                        | 2     |
| `plugin-kiln/skills/kiln-next/SKILL.md`                                    | 2     |
| `docs/architecture.md`                                                     | 2     |
| `specs/kiln-capture-fix-polish/*.md` (tests/smoke notes)                   | Last  |

## Risks addressed in plan

- **Token budget (NFR-003)**: Decision 1's deterministic gate removes the "inline judgment" token cost. Expected delta vs current Step 7: −1k to −2k tokens (team-brief rendering removed), +~300 tokens (gate predicate + fallback phrasing). Net negative ✓.
- **Rename collision (FR-010)**: Decision 2 confirms zero collisions via pre-grep.
- **Schema drift (FR-009)**: Decision 3 keeps feedback schema distinct from issues. A future `/kiln:kiln-mistake` unification can happen in its own feature if a second use case emerges.
- **FR-012 "override" language softened**: spec.md phrases this as "feedback-shaped theme with issues as tactical FRs" — a highlight-first model rather than hard override. Matches the PRD's risk note that recommends softer framing.

## Smoke test plan (Phase F)

- **SC-001**: `grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md` → zero hits.
- **SC-003**: Run `/kiln:kiln-fix` on a trivial bug; assert the final report contains the literal header `## What's Next?`.
- **SC-004**: Run `/kiln:kiln-feedback "smoke test feedback"`; assert `.kiln/feedback/<YYYY-MM-DD>-smoke-test-feedback.md` exists with all required frontmatter keys non-empty.
- **SC-005**: Seed one fake feedback + one fake issue with `status: open`; run `/kiln:kiln-distill`; assert the generated PRD's `## Background` mentions the feedback before the issue.
- **SC-006**: `grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/architecture.md docs/features/2026-04-22-kiln-capture-fix-polish/` → only historical hits inside `docs/features/2026-04-22-kiln-capture-fix-polish/` (PRD text) and spec bodies. Zero hits in live skill/agent/docs files (except `docs/architecture.md` after the sweep should be updated too).
