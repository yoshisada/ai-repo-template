# Handoff: kiln autonomous rearchitecture → implementation

## What this is

We spent ~2 sessions designing a complete rearchitecture of the `kiln` plugin into a fully autonomous build system. The design is finalized and ready to implement. The artifacts are:

- **`docs/features/2026-06-22-kiln-autonomous-rearchitecture/MASTER_PLAN.md`** — 2100+ line authoritative design doc (all workflow JSON, agent definitions, config schemas, phase breakdown)
- **`docs/features/2026-06-22-kiln-autonomous-rearchitecture/MASTER_PLAN.html`** — visual companion with wf-block diagrams, upgrade tables, step badges

**Read the MASTER_PLAN.md first** before touching any file. The full workflow JSON for every new workflow is in there. Do not invent structure — implement exactly what's written.

---

## Architecture decisions locked in

These were debated and decided. Do not re-open them.

**Workflow runtime:** All major skills become thin wrappers that write `.wheel/inputs/` then call `wheel-run kiln:<workflow>`. The logic lives in wheel workflow JSON files, not in SKILL.md.

**Team steps:** `implement` and `audit` in `kiln-build-prd.json` are `type: "team"` — wheel dispatches the declared members in parallel. The skill never calls `Agent()` directly for these (CLAUDE.md rule 4: agents don't spawn agents).

**Checkpoints:** `type: "command"` only. Two triggers: (1) checkpoint name in `review_checkpoints[]` in config, (2) upstream step emitted `severity: blocking`. No AI reasoning mid-run. Config is set during `kiln-init`.

**Two-track model (issues vs captures):** Issues → always fix-priority (`kiln-fix` if small batch, `kiln-build-prd` if large batch). Feedback + roadmap items → `kiln-distill` → PRD. These never mix.

**Journal as state:** `.kiln/runs/<run-id>/journal.md` is the orchestrator's source of truth for what happened. Auto-compact is safe because the workflow reads disk, not session context.

**Agent notes path:** `.kiln/runs/<run-id>/agent-notes/<story-id>.md` (run artifacts, not spec artifacts).

**Mistake record input contract:** Caller writes `{summary, assumption, correction, source}` to `.wheel/inputs/mistake-data.json`; the workflow generates ID and tags internally.

---

## Phase breakdown (implement in this order)

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 + Phase 5 (parallel)
```

### Phase 0 — Config Foundation
**Goal:** Every project can declare coding standards and review preferences. `kiln-init` scaffolds them.

Files to create/modify:
- `plugin-kiln/scaffold/standards-template.md` — new scaffold file
- `plugin-kiln/scaffold/config-schema.json` — version-keyed config keys
- `plugin-kiln/scaffold/doctor-manifest.json` — health check definitions
- `plugin-kiln/scaffold/test-strategy-template.json` — new scaffold file
- Update `plugin-kiln/skills/kiln-init/SKILL.md` — add wizard steps 3b (vision interview), 5b (design_first), 5c (branching style)
- Update `plugin-kiln/skills/kiln-next/SKILL.md` — implement 8-level priority stack (see MASTER_PLAN.md §kiln-next)
- Fix `kiln-report-issue` issue numbering race condition (Open Question #2)
- Update shelf counter to increment on all 4 capture surfaces, not just report-issue (Open Question #3)

Config template (write to scaffold):
```json
{
  "config_version": "1.0.0",
  "review_mode": "standard",
  "review_checkpoints": ["post-spec", "pre-pr"],
  "auto_build": false,
  "auto_pr": false,
  "auto_merge": false,
  "pi_apply_threshold": "none",
  "issue_batch_threshold": 5,
  "distill_threshold": 3,
  "standards": ".kiln/standards.md",
  "design_first": false,
  "branching": {"style": "github-flow", "per_feature": true},
  "models": {
    "validator": "claude-haiku-4-5-20251001",
    "researcher": "claude-sonnet-4-6",
    "implementer": "claude-sonnet-4-6",
    "auditor": "claude-sonnet-4-6",
    "oracle": "claude-sonnet-4-6"
  }
}
```

### Phase 1 — Ledger + Precedent System
**Goal:** Past mistakes from all projects are queryable before any new build.

Files to create:
- `plugin-kiln/workflows/kiln-precedent.json` — exact JSON in MASTER_PLAN.md §Phase 1
- `plugin-kiln/workflows/kiln-mistake-record.json` — exact JSON in MASTER_PLAN.md §kiln-mistake-record.json
- `plugin-kiln/agents/precedent-reader.md` — exact definition in MASTER_PLAN.md §precedent-reader.md
- `.kiln/ledger/` directory schema documented in MASTER_PLAN.md §Phase 1
- Update `kiln-report-issue` background sub-agent to call `kiln-mistake-record` when issue is AI-class
- Add `ledger-mirror` step to `shelf-sync.json`

### Phase 2 — Build Pipeline as Wheel Workflow
**Goal:** `kiln-build-prd` becomes a resumable wheel workflow. This is the largest phase.

Files to create:
- `plugin-kiln/workflows/kiln-build-prd.json` — **26 steps** — full JSON in MASTER_PLAN.md §kiln-build-prd.json
- `plugin-kiln/workflows/kiln-fix.json` — exact JSON in MASTER_PLAN.md §kiln-fix.json
- `plugin-kiln/workflows/kiln-distill.json` — **7 steps** — exact JSON in MASTER_PLAN.md §kiln-distill.json
- `plugin-kiln/agents/build-summary.md` — exact definition in MASTER_PLAN.md §build-summary.md
- `plugin-kiln/scaffold/retro-template.md`
- `plugin-kiln/scaffold/smoke-report-template.md`
- `plugin-kiln/scaffold/precedent-block-template.md`
- `plugin-kiln/scaffold/run-manifest-template.json`

Files to modify:
- `plugin-kiln/skills/kiln-build-prd/SKILL.md` → thin wrapper: write `.wheel/inputs/prd-slug.txt`, call `wheel-run kiln:kiln-build-prd`; add `--resume` flag
- `plugin-kiln/skills/kiln-fix/SKILL.md` → thin wrapper: write `.wheel/inputs/issue.txt`, call `wheel-run kiln:kiln-fix`
- `plugin-kiln/skills/kiln-distill/SKILL.md` → thin wrapper: call `wheel-run kiln:kiln-distill`
- `plugin-kiln/skills/kiln-resume/SKILL.md` → reads `.kiln/runs/*/manifest.json`, surfaces cursor, calls `wheel-run --resume`

Key workflow details (do not deviate):
- `implement` step: `type: "team"`, members: `kiln:implementer` (per story from dispatch manifest, worktree isolation), `kiln:spec-enforcer` (singleton watch), `kiln:qa-engineer` (singleton checkpoint), `merge_after: true`
- `audit` step: `type: "team"`, members: `kiln:prd-auditor`, `kiln:spec-enforcer`, `kiln:quality-judge`
- All 4 checkpoint steps: `type: "command"` — pause if name in `review_checkpoints[]` OR upstream `severity: blocking`
- `build-summary` step: `"on": "always"` — runs even if pipeline failed
- `create-pr` step reads `branching.style` → sets `--base main` (github-flow/trunk) or `--base <integration_branch>` (gitflow)
- `audit-synthesize` step: `model_tier: "validator"` (haiku) — merges panel verdicts
- `fix-blocking` step: `"on_failure": "route:kiln:debugger"`

### Phase 3 — Self-Improvement Loop
**Goal:** Build friction automatically closes into config patches (L1) or skill-edit chips (L2).

Files to create:
- `plugin-kiln/workflows/kiln-self-improve.json` — exact JSON in MASTER_PLAN.md §kiln-self-improve.json
- `plugin-kiln/agents/risk-classifier.md` — exact definition in MASTER_PLAN.md §risk-classifier.md

Files to modify:
- `plugin-kiln/skills/kiln-pi-apply/SKILL.md` → rename/redirect to `kiln-improve`, thin wrapper for `wheel-run kiln:kiln-self-improve`

### Phase 4 — New Hooks + Gates
Files to create:
- `plugin-kiln/hooks/coverage-gate.sh` — exact script in MASTER_PLAN.md §Phase 4
- `plugin-kiln/hooks/untraced-test-gate.sh` — exact script in MASTER_PLAN.md §Phase 4
- `plugin-kiln/hooks/merge-bar.sh` — exact script in MASTER_PLAN.md §Phase 4

### Phase 5 — Observability + Vision Layer
- Extend `wheel-view` skill to stream live from `.kiln/runs/<id>/journal` during active runs
- `smoke-review` agent gains `vision-verify` path when `design_verify: true` (already in agent instruction — no new file needed, just verify the logic is wired)
- Add trim integration: `sync-designs` step in `kiln-distill.json` already calls `trim-pull` when `design_first: true`

---

## What already exists (do not recreate)

- `plugin-kiln/workflows/kiln-mistake.json` — exists, not being replaced
- `plugin-kiln/workflows/kiln-report-issue.json` — exists, being modified (not replaced)
- All 13 existing agents in `plugin-kiln/agents/` — keep them; only 3 new ones are added
- All existing hooks in `plugin-kiln/hooks/` — keep them; 3 new ones are added

---

## Key invariants (enforced by existing hooks — do not break)

- Every `src/` edit requires spec + plan + tasks + ≥1 `[X]` task (`require-spec.sh`)
- `.env` files never committed (`block-env-commit.sh`)
- Feature branch naming enforced (`require-feature-branch.sh`)
- VERSION 4th segment auto-increments on every file edit (`version-increment.sh`)

---

## Open questions (carry forward, non-blocking for Phases 0-2)

1. **search_vault MCP tool** — `precedent-reader` agent calls `mcp__obsidian-projects__search_vault`. Verify this tool is implemented in the Obsidian MCP before Phase 1 ships. If not, implement it or document the fallback behavior.
2. **L2 chip UI** — high-risk improvement proposals need a one-click apply UX. Depends on Claude Code task chip API. Non-blocking for Phase 3 — the chip can be surfaced as text until the API is available.
3. **Wheel `type: "team"` support** — the `implement` and `audit` steps declare `type: "team"` with a `members` array. Verify wheel's runtime supports this step type and the declared schema before Phase 2 ships. If not, this is a wheel feature to build first.

---

## Repo context

- Working directory: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template`
- Branch: `build/wheel-viewer-definition-quality-20260509` (or create a new feature branch for this work)
- The MASTER_PLAN.md is the single source of truth — if something is unclear, read it before asking
- Plugin source lives in `plugin-kiln/`, `plugin-wheel/`, `plugin-shelf/`, `plugin-trim/`, `plugin-clay/`
- Consumer projects don't live here — this is the plugin source repo
- `kiln-init` scaffolds consumer projects; test scaffold changes with `node plugin-kiln/bin/init.mjs init` in a temp dir
