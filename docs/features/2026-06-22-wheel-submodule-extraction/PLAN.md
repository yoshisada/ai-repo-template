# Next Phase Plan — Wheel Submodule Extraction

**Date:** 2026-06-22
**Branch:** `build/wheel-submodule-extraction-20260622`
**Status:** Phases 1–2 landed; Phase 3 (the actual repo split) gated on user go-ahead.

## Context

`wheel` is being separated into its own source-of-truth GitHub repo, consumed back
into this monorepo as a **git submodule**, so wheel can be developed essentially
independently. This document records what already landed, what is gated, and the
forward work the extraction sets up but does not finish.

### Already done (this branch)

- **Phase 1 — decoupling (committed `59bae04`).** Relocated the kiln-driven research
  harness (`research-runner.sh` + 7 helpers) and the agent-prompt composer
  (`compose-context.sh`) out of `plugin-wheel/scripts/` into `plugin-kiln/scripts/`.
  This fixes the documented "wheel must stay plugin-agnostic" violation and is a hard
  prerequisite for a clean submodule (a submodule *is* the `plugin-wheel/` directory —
  kiln-coupled scripts cannot be "excluded," they must physically move). Shared generic
  helpers (`scratch-create.sh`, `claude-invoke.sh`) and the `verbs/` index stay in
  wheel and are referenced cross-plugin. Verified: wheel build + 185 wheel tests pass;
  compose-context + research-helper tests pass from kiln; live surface clean of old paths.
- **Phase 2 — MiniMax M3 matrix runner (committed `377524a`).**
  `plugin-wheel/scripts/harness/minimax-matrix-runner.sh` sweeps each id in
  `BIFROST_MODEL_IDS` across the 7 `bifrost-minimax-*` fixtures, strictly serial with
  pacing, so the gateway is never rate-limited. M3 tests alongside M2.7 with no fixture
  duplication. Verified live against the LAN gateway (M2.7 session init confirmed).

## Phase 3 — The submodule split (GATED, outward-facing)

1. **History-preserving export.** `git subtree split --prefix=plugin-wheel -b wheel-export`
   (replays the ~210 wheel-touching commits) → push to a new `github.com/yoshisada/wheel`
   created via `gh repo create`.
2. **Convert to submodule.** `git rm -r plugin-wheel` → `git submodule add … plugin-wheel`.
   Adds `.gitmodules`. Clones then need `--recursive`.
3. **Repoint metadata** in the wheel repo: `package.json` `repository` (drop
   `directory: plugin-wheel`), `marketplace.json` `repository`/`homepage`, README.
4. **CI:** set monorepo `actions/checkout` `submodules: true`; mirror the wheel test job
   into the new repo.

## Forward work (the next phase proper)

### A. Two-repo CI + release/versioning
- Split `.github/workflows/wheel-tests.yml`: the wheel-internal jobs (TS build, hook
  invariants, preprocessor bats) move to the **wheel repo**; the monorepo keeps only the
  cross-plugin guards (e.g. the NFR-G-6 atomic-migration guard referencing
  `plugin-kiln/workflows/kiln-report-issue.json`).
- Decide the versioning story: the monorepo's `release.feature.pr.edit` scheme + the
  auto-increment edit hook currently bump `plugin-wheel/package.json` in-tree. As a
  submodule, wheel owns its own version — reconcile the two (likely: wheel self-versions;
  monorepo pins a submodule SHA, not a version string).

### B. npm + marketplace
- Republish `@yoshisada/wheel` from the new repo (`scripts/` stays out of `files`, as today).
- Decide marketplace listing (`marketplace.json` is currently `listed: false`).

### C. Generalize the matrix runner beyond MiniMax
- `.env.example` already stubs Bedrock / Vertex / OpenRouter provider blocks. Generalize
  `minimax-matrix-runner.sh` into a provider-agnostic `model-matrix-runner.sh` that takes
  a provider + model-list, so the same sequential/paced sweep covers any
  Anthropic-compatible gateway. Confirm the exact **MiniMax M3 route id** the Bifrost
  deployment exposes (Phase 2 assumes `minimax/MiniMax-M3` in `.env.test`; correct if
  the gateway names it differently).

### D. Submodule developer ergonomics
- Short doc + README note: `git clone --recursive`, `git submodule update --remote`,
  and the publish flow (commit in submodule → bump pin in monorepo). Update `CLAUDE.md`'s
  "What This Repo Is" to describe the submodule layout.

### E. Residual hardening surfaced during this work
- **Test isolation gap (real, worth fixing):** the `bifrost-minimax-*` fixtures run the
  `claude` subprocess with `bypassPermissions`. During Phase 2's live run, MiniMax M2.7
  went off-script and **wrote a workflow JSON into the real repo** at
  `plugin-wheel/workflows/minimax-smoke.json` (removed). The subprocess cwd is a scratch
  dir, but a model can still write absolute paths into the repo. Harden the fixture
  substrate (sandbox the writable root, or assert no repo mutations post-run).
- **MiniMax workflow-protocol compliance:** that same run shows M2.7 did not write the
  declared agent-step output (`.wheel/outputs/minimax-haiku.md`) — it authored a workflow
  instead. This is exactly the cross-model behavior the bifrost fixtures exist to catch;
  track whether M2.7/M3 reliably honor wheel's agent-step output contract.
- **Pre-existing test mismatch:** `research-runner-axis-direction-pass` fails on a
  renderer format assertion (`5.0/4.5` expected vs `5/4.5` rendered by the unchanged
  `render-research-report.sh`). Independent of this work; fix the test or the renderer's
  trailing-zero formatting.

## Verification (live, on the LAN)

```bash
# Both models, all 7 fixtures, strictly serial + paced:
BIFROST_MODEL_IDS="minimax/MiniMax-M2.7,minimax/MiniMax-M3" \
  bash plugin-wheel/scripts/harness/minimax-matrix-runner.sh
# or: cd plugin-wheel && npm run test:minimax-matrix
```
