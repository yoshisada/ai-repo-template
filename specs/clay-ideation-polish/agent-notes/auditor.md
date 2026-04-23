# Auditor Notes — Clay Ideation Polish

**Date**: 2026-04-22
**Model**: Opus 4.7 (team auditor agent)
**Branch**: `build/clay-ideation-polish-20260422`
**Stacked on**: `build/kiln-capture-fix-polish-20260422` (open PR #135)

## Audit verdict

PASS. 12/12 FRs + 3/3 NFRs + 6/6 SCs traced from PRD → spec → skill-body code. Zero blockers. No gaps to document in `blockers.md`.

Tasks.md: 25/25 `[X]` after I mark the "PRD audit run after Phase E (auditor task #3)" line. Implementer left it unchecked by design — it was mine to flip.

## Hard gates (team-lead mandated greps)

| Gate | Command | Expected | Result |
|------|---------|----------|--------|
| FR-001 no `--intent` flag | `grep -nE '\-\-intent' plugin-clay/skills/clay-idea/SKILL.md` | zero hits | **PASS** — zero hits |
| FR-012 `--parent` flag exists | `grep -nE '\-\-parent' plugin-clay/skills/clay-new-product/SKILL.md` | ≥1 hit | **PASS** — 6 hits at lines 18, 20, 22, 29, 35, 38 |

## Cross-skill consistency checks

- **Decision 2 fallback (missing intent → `marketable`)** — implemented identically in:
  - `clay-new-product/SKILL.md:123-127` (`case ... *) INTENT="marketable" ;; esac`)
  - `clay-idea-research/SKILL.md:51-56` (same idiom)
  Both match plan.md Decision 2 and contracts §1's validation rule. PASS.

- **`is_parent_product()` predicate** inlined in `clay-idea/SKILL.md:162-175` and `clay-list/SKILL.md:28-39`. Identical to contracts §3. PASS.

- **`list_sub_ideas()` predicate** inlined in `clay-list/SKILL.md:42-51` and referenced in `clay-create-repo/SKILL.md` Step 1 (for SIBLING_COUNT). Identical to contracts §4. PASS.

- **Feature-PRD path (FR-011)** — `clay-create-repo/SKILL.md:214` writes `<local-path>/docs/features/${TODAY}-${SUB_SLUG}/PRD.md`. Matches contracts §6 AND the kiln feature-PRD convention (`docs/features/2026-04-22-clay-ideation-polish/PRD.md` itself). PASS.

## NFR-002 backwards-compat

Every nested/sub-idea branch is explicitly gated:

- `clay-list/SKILL.md:69` — "renders exactly as today (NFR-002)"
- `clay-create-repo/SKILL.md` — all nested logic under `$IS_SUB_IDEA=true && $PARENT_HAS_SIBLINGS=true`; flat products hit the unchanged flat branches
- `clay-idea/SKILL.md` Step 2.7 — `is_parent_product` returns false for flat products (no `about.md` OR no qualifying sub-folder), so the collision prompt never fires
- `clay-new-product/SKILL.md` Step 0a — without `--parent=`, `IS_SUB_IDEA=false`, and the original flat-product flow runs untouched

The only user-visible behavior change on a pre-existing flat product is the intent prompt in `/clay:clay-idea` (always fires per FR-001 / NFR-003) — this is spec'd and accepted.

## Implementer's 4 flagged items — auditor rulings

The implementer surfaced 4 UX judgment calls. None are FR violations; all are deferrable polish. My calls:

1. **Parent-row Status/Artifacts show `—`** (implementer note §1). **ACCEPT.** Contracts §7 says parent status is derived from children, not direct PRD files. A parent folder has no `research.md`/`naming.md`/`PRD.md` of its own, so `—` is accurate. Showing a synthetic "aggregate" status across children would be a new feature — file as follow-on if desired, not a pre-merge blocker.

2. **"Sibling parent" in Step 2.7 → brand-new flat slug** (implementer note §5). **ACCEPT.** Plan.md doesn't pin semantics, and "start over with a new top-level slug" is the natural reading of "different top-level slug". The alternative reading ("create another parent next to the existing one") is also valid but requires more scaffolding (when would you add sub-ideas to this newly-birthed parent?). The implementer's simpler interpretation is the right default; if users report friction, it's a 1-commit follow-on.

3. **Parent `about.md` carries no `intent:`** (implementer note / Decision 3). **ACCEPT** and reinforce. Plan Decision 3 says `intent:` is required on sub-ideas and prompted fresh per sub-idea (so a parent `automations` can host one `internal` and one `marketable` sibling). Putting `intent:` on the parent would either (a) shadow the sub-idea's value (which Decision 3 explicitly rejects) or (b) sit unused. Correct to omit.

4. **`clay-create-repo` body density after 4 branches** (implementer note §"Cross-skill coupling"). **ACCEPT as-is; file follow-on.** The skill works and every branch is clearly commented with its governing FR. Refactoring into a preamble helper is a follow-on PRD candidate — not a pre-merge concern.

## Version bump

`./scripts/version-bump.sh pr` → `000.001.003.015` → `000.001.004.000`. Propagated to all 5 `plugin-*/package.json` + 5 `plugin-*/.claude-plugin/plugin.json` + root `VERSION`. Committed separately.

## Friction notes for retrospective

- **Pipeline shape worked as advertised.** Specifier → implementer → auditor with per-phase commits made audit trivially traceable — I could jump straight to "does phase-D's commit match FR-010/011?" without rereading the full skill body each time.
- **Contracts/interfaces.md was the MVP** per the implementer's own note. It's the only place I needed to cross-reference when verifying that `is_parent_product` and `list_sub_ideas` were bit-identical across skills.
- **Smoke-results.md as a static walkthrough is the right shape for clay.** There's no test runner, and live slash-command invocation isn't available inside an agent session. The walkthrough document plus SMOKE.md runbook for the human is a sustainable pattern for other skill-only PRDs.
- **Minor friction**: when I ran `ls -la plugin-*/package.json` I realized there's no root `package.json` — the version-bump script handles this, but the status listing surprised me. Not a problem to fix, just a note.
- **One observation about stacking**: this branch is stacked on `build/kiln-capture-fix-polish-20260422` (open PR #135). The PR I open will show commits from both branches until #135 merges. I'm documenting this explicitly in the PR body (`## Dependency` section) per team-lead brief. If the retrospective agent is looking at pipeline ergonomics, stacked-branch workflow in wheel-coordinated teams is worth a note — it works, but the "what commits am I actually reviewing?" question depends on whether the base PR has landed yet.

## Handoff to retrospective

All 25 tasks [X]. Audit clean. PR opened with `build-prd` label. Four pre-merge gates (DG-1..DG-4) documented as `- [ ]` in PR body for the human operator since agents can't run live slash commands. Dependency note calls out PR #135 as the base.

Nothing blocked. Ready for retrospective (Task #4).
