# Implementation Plan — kiln autonomous rearchitecture

> Companion to `MASTER_PLAN.md` (the design) and `HANDOFF.md` (the brief).
> This document sequences the *build* and reconciles the design against the
> **actual** wheel runtime, which differs materially from what the plan assumes.
> Read `MASTER_PLAN.md` for the full JSON/agent bodies; read this for the order
> of operations, the capability gaps, and the decisions that need sign-off.

Date: 2026-06-24 · Author: handoff implementation pass

---

## 0. TL;DR — what changed since the design was written

Two facts on the ground invalidate parts of the handoff:

1. **`plugin-wheel` is now a git submodule** (`github.com/yoshisada/wheel.git`,
   pinned at `main`). Any wheel-runtime change is a **separate-repo PR + submodule
   pointer bump**, not an in-tree edit. Per explicit direction: **wheel changes
   require a strong reason, explicit approval, and thorough testing.** This plan
   treats wheel as frozen and routes around it wherever possible.

2. **Wheel's real capabilities are narrower than the MASTER_PLAN assumes.** I
   audited the wheel TS runtime. The plan's two largest steps (`implement`,
   `audit`) and several cross-cutting fields (`model_tier`, `on_failure`,
   `on: always`) use a schema wheel does not implement. The capability gap — not
   the file count — is the real work. See §2.

The design intent is sound and stays. The *encoding* of that intent into wheel
JSON must be rewritten against the schema in §2.

---

## 1. Current state snapshot

- **Branch:** `build/wheel-submodule-extraction-20260622` (mid-extraction). Start
  this work on a fresh branch off `main`, e.g. `build/kiln-autonomous-phase0-<date>`.
- **Implemented from the plan:** nothing. Only pre-existing `kiln-mistake.json`
  and `kiln-report-issue.json` workflows are on disk.
- **Existing agents (13):** match the "do not recreate" list. New agents to add:
  `precedent-reader`, `risk-classifier`, `build-summary`.
- **Existing hooks (4):** `require-spec`, `block-env-commit`, `require-feature-branch`,
  `version-increment`. New hooks to add: `coverage-gate`, `untraced-test-gate`,
  `merge-bar`.
- **Note on this repo's own gates:** the `require-spec.sh` gate fires on `src/`
  edits only. Plugin authoring (`plugin-kiln/{skills,agents,hooks,workflows,scaffold}`)
  is **not** `src/`, so it is not spec-gated here. The senior-engineer-merge bar
  still applies by convention.

---

## 2. Wheel capability gap matrix (the load-bearing section)

Audited against the wheel submodule TS runtime (`src/lib/*.ts`, `src/shared/state.ts`,
team fixtures). "Verified present/absent" = grepped the runtime, not the docs.

| Plan feature | Wheel reality | Status | Resolution |
|---|---|---|---|
| `type: "team"` single step w/ `members[]` | Team model is 4 step types: `team-create` → N×`teammate` → `team-wait` → `team-delete`. Each `teammate` is a **static slot** running a sub-`workflow` with an `assign{}` block. | **Absent (different shape)** | Rewrite `implement`/`audit` as the 4-step sequence. See §2.1. |
| `per: item / from / field` dynamic fan-out (N implementers per story) | No fan-out primitive. Teammate count is fixed at author time. | **Absent** | Decision required — §2.1, options A/B/C. |
| `isolation: "worktree"` per teammate | Zero references in runtime. | **Absent** | Only matters under parallel implementers. Tied to §2.1 decision. |
| `merge_after` / `merge_conflict_handler` | Zero references. | **Absent** | Tied to §2.1 decision. Single-tree authoring avoids the need. |
| `model_tier` (config-resolved tiers) | Steps carry a direct `model` field only (e.g. `"model":"haiku"`). No tier lookup. | **Absent** | §2.2 — author with concrete `model`; defer config-driven tiers. |
| `on_failure: "skip"` | No `on_failure` handling in runtime. | **Absent** | §2.3 — author steps to exit 0 with a fallback payload (most plan steps already do `\|\| echo …`). |
| `on_failure: { route: "kiln:debugger" }` | Absent. But `branch` with `if_zero`/`if_nonzero` exit-code routing **is** present. | **Workaround exists** | §2.3 — express routing via a `branch` step. |
| `on: "always"` (run build-summary even on failure) | Absent. | **Absent** | §2.3 — make summary the terminal step and keep upstream steps non-halting. |
| `context_from: [...]` | Present — collects named upstream outputs into context.json. | **Present** | Use as-is. |
| `type: "workflow"` native sub-workflow | Present (`dispatch.ts case 'workflow'`). | **Present** | Prefer over `command`-calls-`wheel-run` for `kiln-precedent`/`kiln-mistake-record`. |
| `type: "approval"` (pause for human) | Present — pauses via `awaiting_user_input`. | **Present** | This is the real **checkpoint** primitive. The plan models checkpoints as `command` steps that emit `{action:"pause"}`, but a `command` cannot actually halt the run. Use a `branch` (checkpoint-needed?) → `approval` pair. See §2.4. |
| `next` / `branch` explicit sequencing | Present (`if_zero`/`if_nonzero`, `next`). | **Present** | Use for conditional checkpoints and debugger routing. |

**Bottom line:** ~80% of the plan is buildable on frozen wheel with *defensive
authoring* (steps that exit 0 with fallbacks, `branch`+`approval` for pauses,
native `workflow` steps). Exactly **one** designed capability — parallel,
worktree-isolated, auto-merged implementers — cannot be reproduced at full
fidelity without a wheel change. That is the one approval gate. Everything else
degrades gracefully.

### 2.1 The `implement`/`audit` team reconciliation — DECISION REQUIRED

The plan's `implement` step wants: *one implementer per user story, each in its own
git worktree, auto-merged after, with a spec-enforcer + qa-engineer watching.*
Wheel gives static teammate slots running sub-workflows, no worktree, no merge.

Three ways forward:

- **Option A — single implementer teammate, stories sequential (no wheel change).**
  One `teammate` slot runs an `implement-story` sub-workflow that loops over the
  story list in `implement-dispatch.json`. `spec-enforcer` and `qa-engineer` are
  two more static teammate slots. `team-wait` barriers; `team-delete` tears down.
  No worktrees (single tree, sequential = no merge conflicts). **Loses
  parallelism; keeps correctness and the multi-role team shape.** Ships now.
  *Recommended for v1.*

- **Option B — fixed N parallel implementer slots (no wheel change).** Declare a
  capped pool (e.g. `implementer-1..3`) as static teammate slots; `dispatch-implement`
  writes one assign file per slot, round-robining stories; empty slots no-op.
  Parallel within a shared tree → **real merge-conflict risk with no merge
  handler.** Fragile; only safe if stories touch disjoint files (not guaranteable).
  Not recommended.

- **Option C — wheel change: add fan-out + worktree isolation + merge to `teammate`
  (needs approval + thorough testing).** Faithful to the design. Cross-repo PR in
  the wheel submodule: dynamic teammate expansion from an array, `isolation:
  "worktree"`, post-`team-wait` merge with conflict routing. Largest effort;
  highest risk; full fidelity. Defer until v1 (Option A) proves the pipeline.

**Recommendation:** ship Phase 2 on **Option A**. Treat parallel worktree
implementers as a *later, deliberate* wheel feature (Option C) with its own spec
and test suite — exactly the kind of change the wheel-change policy is meant to
gate. The journal-as-state design makes a later upgrade non-breaking.

### 2.2 `model_tier` → direct `model`

Author every agent/teammate step with a concrete `"model"` (`validator`→`haiku`,
everything else→`sonnet`), matching the tier table in MASTER_PLAN §Model Tier Table.
Keep the `models{}` block in `config.json` as **documentation of intent** and the
seam for a future wheel `model_tier` resolver. Document in the workflow header that
changing a tier today means editing the `model` field, not config. (A config-driven
resolver is a clean, low-risk wheel change to propose later if tier-swapping becomes
a real workflow.)

### 2.3 Failure handling without `on_failure`/`on: always`

- **Graceful degradation (`on_failure: "skip"`)** — write the step so failure is
  *normal output*, not a non-zero exit. `command` steps: end with `|| echo '<fallback-json>'`
  and never `exit 1` on the soft path (the plan's Obsidian/precedent/design-sync
  steps already do this). `agent` steps: instruct the agent to emit a clean
  `{ok:false, …}` payload and stop rather than error.
- **Debugger routing (`on_failure: {route}`)** — after a step that can hard-fail
  (e.g. `verify` tests), add a `branch` step keyed on the exit code: `if_nonzero`
  → a `debugger` step, `if_zero` → continue. Cap attempts with a `loop` guard.
- **`on: always` build-summary** — keep every upstream step non-halting (exit 0
  with a status payload) so the terminal `build-summary` step is always reached.
  Summary reads the status payloads and reports failure honestly.

### 2.4 Checkpoints — `branch` + `approval`, not `command`

The plan models each checkpoint as a `command` that prints `{action:"pause"|"skip"}`.
A `command` step **cannot pause the run** — it just prints. Real pausing is the
`approval` step. Encode each checkpoint as a pair:

1. `command` (`checkpoint-<name>-decide`): reads `review_checkpoints[]` + upstream
   severity, sets exit 0 (skip) or exit 1 (pause needed).
2. `branch`: `if_nonzero` → an `approval` step ("Review post-spec output. Continue?");
   `if_zero` → next real step.

`auto_*` config keys collapse the decision to "always skip" by forcing exit 0.

---

## 3. Approval gates (do not proceed past these without sign-off)

| Gate | Where | Why it needs sign-off |
|---|---|---|
| **G1 — Phase 2 team strategy** | Before writing `kiln-build-prd.json` `implement`/`audit` | Picks Option A/B/C (§2.1). A ≠ C in behavior; C is a wheel change. |
| **G2 — any wheel submodule edit** | Anytime a step "needs wheel" | Policy: strong reason + explicit approval + thorough testing + submodule bump. |
| **G3 — `search_vault` MCP tool** | Before Phase 1 precedent ships | Open Q#1. Verify the Obsidian MCP exposes it; if not, build it or document fallback. |
| **G4 — L2 chip API** | Phase 3 | Open Q#2. Until the task-chip API exists, surface L2 proposals as text. |

---

## 4. Phase-by-phase build

Order is **0 → 1 → 2 → 3 → (4 ∥ 5)**. Each phase ends green (its artifacts exist,
parse, and a smoke check passes) before the next starts.

### Phase 0 — Config Foundation  *(unblocked, all in-tree, start here)*

**Goal:** every project declares standards + review prefs; `kiln-init` scaffolds them.

Create:
- `plugin-kiln/scaffold/standards-template.md` (MASTER_PLAN §Phase 0 `.kiln/standards.md`)
- `plugin-kiln/scaffold/config-schema.json` — the `config.json` template (§Phase 0). Add
  `config_version` and the `models{}` + `notifications{}` blocks verbatim.
- `plugin-kiln/scaffold/doctor-manifest.json` (§Phase 0, version-keyed)
- `plugin-kiln/scaffold/test-strategy-template.json` — `{coverage_gate, test, smoke{start,ready,probe,teardown}, design_verify}`

Modify:
- `plugin-kiln/skills/kiln-init/SKILL.md` — scaffold the three config files; add wizard
  steps **3b** (vision interview, skippable, idempotent vs existing `vision.md`),
  **5b** (`design_first`), **5c** (branching style + create integration branch if gitflow).
- `plugin-kiln/skills/kiln-next/SKILL.md` — read `config.json` on entry; surface
  `review_mode` + pending checkpoint state; implement the 8-level priority stack
  (MASTER_PLAN §kiln-next).
- `plugin-kiln/scripts/agents/compose-context.sh` — add `--standards` flag that
  prepends `.kiln/standards.md` as a `## Coding Standards` block.
- **`kiln-report-issue` issue-numbering race** (Open Q#2 in handoff) — make ID
  allocation atomic (reuse the `.shelf-config.lock` flock pattern; accept ±1 drift
  on lock-less macOS per existing FR-006 precedent).
- **shelf counter on all 4 capture surfaces** (Open Q#3) — increment in
  `kiln-feedback`, `kiln-roadmap`, `kiln-mistake`, not just `kiln-report-issue`.

Test: `node plugin-kiln/bin/init.mjs init` in a temp dir → assert the three config
files land, parse as JSON/MD, and a second `init` is idempotent. Run `kiln-doctor`
against the scaffold → table renders, required checks pass.

Definition of done: temp-dir scaffold produces valid config; `kiln-init` wizard runs
3b/5b/5c; `kiln-next` reads config without error; report-issue numbering has no
duplicate IDs under a tight loop.

### Phase 1 — Ledger + Precedent System

**Prereq:** G3 (`search_vault`).

Create:
- `plugin-kiln/workflows/kiln-precedent.json` (§Phase 1) — 2 steps, as written; the
  `search-mistakes` agent step gets `model: "haiku"` and a defensive "no results →
  empty block, exit clean" instruction (replaces `on_failure: skip`).
- `plugin-kiln/workflows/kiln-mistake-record.json` (§kiln-mistake-record.json) — 3
  steps. `sync-to-obsidian` written to emit `{synced:false}` on MCP failure instead
  of erroring (replaces `on_failure: skip`).
- `plugin-kiln/agents/precedent-reader.md`, `plugin-kiln/agents/risk-classifier.md`
  (§Phase 1, model fields concrete).
- `.kiln/ledger/` schema docs (entry + proposals + run manifest schemas live in
  scaffold docs; dirs created on first write).
- New skill `kiln-ledger` (read-only history view) + `kiln-init` creates `.kiln/ledger/`.

Modify:
- `kiln-report-issue` bg sub-agent → on AI-class issue, write `mistake-data.json` and
  invoke `kiln-mistake-record` (prefer native `type:"workflow"` step over `wheel-run`
  shell-out where the caller is itself a workflow).
- `shelf-sync.json` → add a `ledger-mirror` step.

Test: feed a synthetic `mistake-data.json` → `kiln-mistake-record` writes
`.kiln/mistakes/<id>.md` + `.kiln/ledger/<id>.json` with stable ID/tags; run twice →
no dup, deterministic slug. `kiln-precedent` with Obsidian down → emits the empty
precedent block and exits 0.

### Phase 2 — Build Pipeline as Wheel Workflow  *(largest; gated by G1)*

**Prereq:** G1 decision (Option A recommended). Build everything below against the
chosen team shape.

Create:
- `plugin-kiln/workflows/kiln-distill.json` (§kiln-distill.json, 7 steps) — `sync-designs`,
  `vision-filter`, `invoke-build` written non-halting.
- `plugin-kiln/workflows/kiln-fix.json` (§kiln-fix.json) — replace `on_failure:{route}`
  on `fix`/`verify` with `branch`→`debugger` pairs; add `init-run-manifest` first step.
- `plugin-kiln/workflows/kiln-build-prd.json` (§kiln-build-prd.json) — the 26-step
  pipeline, **with these rewrites**:
  - `implement` (was `type:"team"`+members+per-item+worktree) → **Option A**: `team-create`
    → `teammate(implement-story sub-wf, loops stories)` + `teammate(spec-enforcer)` +
    `teammate(qa-engineer)` → `team-wait` → `team-delete`.
  - `audit` (was `type:"team"`) → `team-create` → 3 `teammate` slots (`prd-auditor`,
    `spec-enforcer`, `quality-judge`) → `team-wait` → `team-delete`.
  - all 4 checkpoints → `command`(decide, exit code) + `branch` → `approval` (§2.4).
  - all `model_tier` → concrete `model` (§2.2).
  - `fix-blocking` `on_failure:route` → `branch`→`debugger`.
  - `build-summary` `on:always` → terminal step + non-halting upstream (§2.3).
  - `quality-judge` agent: needs creating if absent — confirm vs existing
    `output-quality-judge.md` (likely rename/alias, not a new file).
- `plugin-kiln/agents/build-summary.md` (§build-summary.md, `model: haiku`).
- Scaffold templates: `retro-template.md`, `smoke-report-template.md`,
  `precedent-block-template.md`, `run-manifest-template.json`.
- A small `implement-story` sub-workflow (Option A) under `plugin-kiln/workflows/`.

Modify (skills → thin wrappers writing `.wheel/inputs/` then `wheel-run`):
- `kiln-build-prd/SKILL.md` (+`--resume`), `kiln-fix/SKILL.md`, `kiln-distill/SKILL.md`,
  `kiln-resume/SKILL.md` (reads `.kiln/runs/*/manifest.json` cursor).

Test: run `kiln-distill` on a temp repo with synthetic captures → PRD drafted,
captures marked processed. Run `kiln-build-prd` on a trivial PRD end-to-end under the
isolated-session recipe (CLAUDE.md "Testing wheel workflows live") → spec/plan/tasks
land, team step dispatches all members, `team-wait` collects, summary prints, manifest
cursor advances. Kill mid-run → `--resume` continues from cursor.

### Phase 3 — Self-Improvement Loop  *(gated by G4 for L2)*

Create: `plugin-kiln/workflows/kiln-self-improve.json` (§Phase 3) — `apply-l1-patches`
agent restricted to config files; `surface-l2-chips` emits text until the chip API
exists (G4); `sync-to-obsidian` non-halting.

Modify: `kiln-pi-apply/SKILL.md` → wrapper for `wheel-run kiln:kiln-self-improve`;
add `kiln-improve` as the new-name alias.

Test: seed `.kiln/ledger/proposals/` with a low-risk (config-target) and a high-risk
(hook-target) stub → L1 auto-applies the config edit + commits; L2 surfaces the hook
proposal as text; risk classification matches the rules.

### Phase 4 — New Hooks + Gates  *(parallel with 5)*

Create `coverage-gate.sh`, `untraced-test-gate.sh`, `merge-bar.sh` (§Phase 4) and wire
into `plugin-kiln/hooks/hooks.json` alongside the existing four.

Test: in a temp repo, coverage below gate → `coverage-gate` exits 1; a test file with
no `// FR-` → `untraced-test-gate` blocks; `gh pr create` with audit <80% → `merge-bar`
blocks. Confirm the existing four hooks still fire (no ordering regressions).

### Phase 5 — Observability + Vision Layer  *(parallel with 4)*

- Extend `wheel-view` skill to stream from `.kiln/runs/<id>/journal` during active runs.
  **This touches the wheel-view skill, which lives in the wheel submodule — confirm
  ownership before editing; if it's a wheel-side skill, this is G2.**
- `vision-verify`: confirm the `smoke-review` agent's `design_verify` path is wired
  (no new file; verify logic).
- `vision-drift-check`: add a drift check to the audit agents.
- Trim `sync-designs`: already in `kiln-distill.json` (Phase 2) under `design_first`.

Test: a run with `design_verify:true` + a mockup → smoke produces a fidelity score; a
deliberately drifted impl → audit emits a `kind:drift` finding.

---

## 5. Milestones

- **M0** — Phase 0 merged: any repo can carry kiln config; doctor + next read it. *(in-tree, fast)*
- **M1** — Phase 1 merged: precedent injects before builds; mistakes hit the ledger. *(needs G3)*
- **M2** — Phase 2 merged on Option A: `kiln-build-prd` runs as a resumable wheel
  workflow end-to-end. *(needs G1; the big one)*
- **M3** — Phase 3 merged: friction closes into L1 patches / L2 chips.
- **M4** — Phases 4+5 merged: gates enforced; runs observable. *(Phase 5 may hit G2)*
- **M5 (optional, deferred)** — Option C wheel change: true parallel worktree
  implementers. Separate wheel-repo spec + test suite + submodule bump. *(G2)*

---

## 6. Dogfood testing protocol (NON-NEGOTIABLE)

JSON-parses-and-validates is **not** "tested." Every workflow and skill in this build
is validated by **driving it live as the user would** — a fresh, isolated Claude
subprocess building and iterating on a real project through the loop. I act as the
solo builder, not the implementer admiring my own diff. Two stances are mandatory and
both are pass/fail criteria, not nice-to-haves:

1. **Output is opinionated-good** — this is the pass/fail bar. Did the workflow produce
   something a senior engineer would accept? Real spec/plan/code, not plausible-looking
   filler. If the output is weak, the workflow fails the test even if every step "succeeded."
2. **Cost is noted, then reviewed — not gated.** Absolute spend scales with feature size,
   so there's no hard budget. Record tokens + USD on every run, then do a post-run
   efficiency pass: was there a step that spent disproportionate time/tokens for what it
   produced? That specific waste is the finding — not the total.

### 6.1 The harness

Use the **env-wipe + unique session_id + separate cwd** recipe (CLAUDE.md "Testing
wheel workflows live") — never a bare `claude --print` from inside this session (it
inherits `CLAUDECODE`/`CLAUDE_CODE_*` and pollutes parent state). Each test:

- fresh `/tmp/kiln-dogfood-<uuid>` cwd, real `git init`, real `kiln-init`
- `env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH`
- unique `--session-id`, `--max-budget-usd <cap>`, `--output-format text` (or `json`
  to scrape token/cost), pipe the "as-the-user" prompt on stdin
- capture the run's token + cost totals into a per-test row

Build a thin reusable runner early — **Phase 0 deliverable**:
`plugin-kiln/tests/dogfood/run-scenario.sh <scenario.md> <budget-usd>` → spins the
isolated subprocess, runs the scenario, writes `.kiln/logs/dogfood-<scenario>-<ts>.md`
with `{tokens_in, tokens_out, usd, steps_run, verdict, notes}`. Stable scenarios graduate
to `plugin-kiln/tests/<name>/` fixtures so `wheel-test-runner.sh` covers them in CI.

### 6.2 Cadence — test very frequently

- **After every workflow/skill edit:** at minimum a validation pass + one targeted live
  step. Do not stack three unverified edits.
- **After every phase:** a full as-the-user loop touching that phase's surface, end to end.
- **Continuous loop building:** maintain ≥1 throwaway demo project (e.g. a tiny CLI or
  TODO API) and keep pushing it through capture → distill → build → improve as new
  workflows come online. The product is the loop; the loop is only real if it runs.

### 6.3 Cost: record, then review for waste (not a gate)

Total spend depends on feature size — a 12-FR build legitimately costs more than a typo
fix, so there is **no pass/fail budget**. The discipline is two steps, in order:

1. **Record** tokens + USD on every run into the dogfood log (`{tokens_in, tokens_out, usd}`),
   plus a rough per-step breakdown when the harness can scrape it.
2. **Review for disproportionate spend.** After accuracy is confirmed, look for the step
   that cost far more than its output was worth, e.g.:
   - re-reading the same large file across multiple steps
   - redundant or overlapping agent spawns
   - oversized `context_from` dragging huge outputs into a cheap step
   - sonnet where a haiku validator-tier step would have sufficed
   - a retry/debug loop that churned

   The *specific wasteful step* is the finding and gets fixed. The total is just context.

Reference point (not a target): `report-issue-and-sync` = **64.5k tokens** via wheel-runner.
Worth a glance if a capture surface lands wildly above that for similar work — but a higher
number on a bigger task is fine.

### 6.4 Output quality rubric (the senior-engineer-merge bar)

Score each live run's artifacts, not just its exit codes:

- **Spec/plan/tasks:** FRs are real and testable; plan has actual interface contracts;
  tasks are dependency-ordered. Reject boilerplate that restates the PRD.
- **Code:** follows `.kiln/standards.md` (naming, function size, FR comments); not stubbed.
- **Tests:** reference their FR; assert behavior, not existence.
- **PR/summary:** the 5-table summary is accurate and useful; cost row present.
- **Retro:** contains an actual insight (`insight_score`), not "went well, ship it."
- **Model rightsizing:** validator-tier work ran on haiku, not sonnet. Flag misuse.

### 6.5 Act-as-user scenario matrix (minimum live coverage)

| Phase | Scenario I drive as the user |
|---|---|
| 0 | `git init` → `kiln-init` a fresh repo; answer the wizard (vision, design_first, branching); `kiln-doctor`; `kiln-next` on an empty repo |
| 1 | capture an AI-class issue → confirm it lands in the ledger + a `kiln-precedent` run surfaces it on the next build; Obsidian-down path stays clean |
| 2 | full loop on a real toy project: `kiln-distill` synthetic captures → `kiln-build-prd` → land a PR; then **kill mid-run and `--resume`** |
| 3 | seed a low-risk + high-risk proposal → `kiln-self-improve` auto-applies L1, surfaces L2 |
| 4 | trip each gate intentionally (coverage <gate, untraced test, audit <80% PR) → confirm block; confirm existing 4 hooks still fire |
| 5 | a `design_verify:true` run → fidelity score; a drifted impl → `kind:drift` finding |

### 6.6 Mechanical checks (still required, but not sufficient)

- **Workflow JSON**: passes `wheel-list`/validation (name + steps + per-step type/id).
- **Scaffold**: `node plugin-kiln/bin/init.mjs init` in a temp dir — files land, valid,
  idempotent on second run.
- **Portability**: no `plugin-<name>/scripts/...` repo-relative paths in command steps —
  use `${WORKFLOW_PLUGIN_DIR}` (cross-plugin reach: `${WORKFLOW_PLUGIN_DIR}/../plugin-kiln/...`).
- **Agent-spawn rules**: plugin-prefixed `subagent_type`; per-spawn vars in `assign{}`/prompt,
  never agent.md (CLAUDE.md Architectural Rules 1–6).

---

## 7. Open questions carried forward

1. **`search_vault` (G3)** — verify the Obsidian MCP exposes it before Phase 1 precedent
   ships. Fallback: tag-grep over a local mirror, or empty precedent block.
2. **L2 chip API (G4)** — surface high-risk proposals as text until the task-chip API
   lands. Non-blocking.
3. **Option C wheel change (G1/G2)** — parallel worktree implementers. Deferred by
   default; revisit after M2 proves the pipeline on Option A.
4. **`wheel-view` ownership (Phase 5/G2)** — confirm whether the live-stream extension
   edits a kiln-side or wheel-side skill before touching it.

---

## 8. Recommended next action

1. **Build the dogfood harness first** (`plugin-kiln/tests/dogfood/run-scenario.sh`, §6.1)
   — nothing is "done" until it can be driven live as the user, so the harness is the
   prerequisite for verifying Phase 0 itself.
2. **Then Phase 0** — fully in-tree, unblocked, the foundation everything else reads
   (`config.json`, `standards.md`, `test-strategy.json`). No wheel changes, no open-question
   resolution. Verify it by *running* `kiln-init` + `kiln-doctor` + `kiln-next` in a fresh
   isolated subprocess (§6.5 row 0), not just by inspecting scaffold output.
3. **Resolve G1** (team strategy) in parallel so Phase 2 is unblocked when Phase 0/1 land.

Throughout: test after every edit, keep a throwaway demo project moving through the loop.
Accuracy is the bar — a weak-output run is a finding. Record cost on every run, then review
it for any step that spent disproportionately for what it produced (§6.2–6.4).
