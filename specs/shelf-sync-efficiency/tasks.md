# Tasks: Shelf Full Sync — Efficiency Pass

**Spec**: `specs/shelf-sync-efficiency/spec.md`
**Plan**: `specs/shelf-sync-efficiency/plan.md`
**Contracts**: `specs/shelf-sync-efficiency/contracts/interfaces.md`

Mark each task `[X]` immediately after it is done. Commit after each phase.

---

## Phase 1 — Baseline capture

- [X] **T001** — Pin the benchmark reference repo identity. Create `specs/shelf-sync-efficiency/baseline/benchmark-repo.md` documenting: repo URL, branch, commit SHA at which measurement is taken, the Obsidian project slug used as the target vault, and the date. (FR-012, SC-001)
- [X] **T002** — Capture v3 token cost on the benchmark repo. Run `shelf-full-sync` (v3) via wheel, record token cost from wheel-runner telemetry, and save to `specs/shelf-sync-efficiency/baseline/v3-token-cost.md`. Expected: ~64.5k tokens. This anchors the SC-001 comparison.
- [X] **T003** — Capture v3 Obsidian snapshot on the frozen fixture. Identify or create a minimal fixture repo that exercises all sync paths (issues, docs, tags, progress). Run v3 against it. Capture the resulting Obsidian state as `specs/shelf-sync-efficiency/baseline/v3-snapshot.json`. (Uses the harness from Phase 2, so this task may be re-run after Phase 2; first-pass capture can be manual.) (FR-003, SC-003)
- [ ] **T004** — Commit Phase 1 artifacts: `git add specs/shelf-sync-efficiency/baseline/ && git commit -m "baseline: shelf-sync-efficiency v3 token cost + snapshot"`.

---

## Phase 2 — Snapshot-diff harness

- [ ] **T005** — Implement `plugin-shelf/scripts/obsidian-snapshot-capture.sh` per contracts §8.1. Walks the vault, normalizes timestamp fields, hashes bodies, emits sorted JSON. Make it executable (`chmod +x`).
- [ ] **T006** — Implement `plugin-shelf/scripts/obsidian-snapshot-diff.sh` per contracts §8.2. Reads two JSONs, prints human-readable diff, exit 0/1/2.
- [ ] **T007** — Sanity-check the harness: run capture against the fixture twice in a row, diff the two outputs, verify exit 0 (identical). Then perturb one file, re-run diff, verify exit 1 with the expected file flagged.
- [ ] **T008** — Re-capture v3 snapshot using the harness (replaces T003 manual capture if applicable) and overwrite `specs/shelf-sync-efficiency/baseline/v3-snapshot.json`.
- [ ] **T009** — Commit Phase 2: `git add plugin-shelf/scripts/ specs/shelf-sync-efficiency/baseline/ && git commit -m "harness: obsidian snapshot capture + diff"`.

---

## Phase 3 — v4 workflow rewrite

- [ ] **T010** — Back up v3 by copying `plugin-shelf/workflows/shelf-full-sync.json` to `specs/shelf-sync-efficiency/baseline/shelf-full-sync-v3.json` for reference during implementation.
- [ ] **T011** — Rewrite `plugin-shelf/workflows/shelf-full-sync.json` to v4. Match contracts §1 exactly: `version: "4.0.0"`, ten steps in the order from §2, step IDs and types from the table. Leave agent instructions and command bodies as placeholders for T012–T015.
- [ ] **T012** — Implement `obsidian-discover` agent instruction per contracts §4.2. Ensure `context_from` is exactly `["read-shelf-config"]`. Verify the output JSON matches §4.3 on a manual test run.
- [ ] **T013** — Implement the `compute-work-list` command (Bash + `jq`) per contracts §5.1. This is the largest task — careful jq pipelines that:
  - Parse all upstream outputs
  - Compute issue/doc actions (create/update/close/skip)
  - Compute dashboard tag delta
  - Compute progress entry from `gather-repo-state.txt`
  - Emit the JSON schema in §5.2
  Validate by running it manually against the fixture and inspecting the output against a hand-computed expected work list.
- [ ] **T014** — Implement `obsidian-apply` agent instruction per contracts §6.2. Explicit: no `list_files` calls, no templating, consume work list verbatim. Preserve dashboard `preserve_sections` byte-for-byte. Capture errors into `errors[]`, do not abort on first error.
- [ ] **T015** — Rewrite `generate-sync-summary` command per contracts §7.1. Must read `compute-work-list.json` and `obsidian-apply-results.json` and emit the five sections in exactly the required order. Keep `terminal: true`.
- [ ] **T016** — Validate the JSON: `jq . plugin-shelf/workflows/shelf-full-sync.json` must succeed. Run `wheel-run shelf-full-sync` in dry-mode if available; otherwise execute on the fixture and catch any step-shape errors.
- [ ] **T017** — Commit Phase 3: `git add plugin-shelf/workflows/shelf-full-sync.json specs/shelf-sync-efficiency/baseline/shelf-full-sync-v3.json && git commit -m "refactor(shelf): shelf-full-sync v4 — 2 agents, command-side diff"`.

---

## Phase 4 — Benchmark + parity verification

- [ ] **T018** — Run v4 on the pinned benchmark repo (from T001). Record token cost via wheel-runner telemetry. Write results to `specs/shelf-sync-efficiency/benchmark/v4-token-cost.md`. Verify ≤30k tokens (SC-001). If >30k, stop, diagnose, return to Phase 3.
- [ ] **T019** — Run v4 on the frozen fixture. Capture the Obsidian snapshot using the harness (`obsidian-snapshot-capture.sh`). Save as `specs/shelf-sync-efficiency/benchmark/v4-snapshot.json`.
- [ ] **T020** — Diff v3 vs v4 snapshots using `obsidian-snapshot-diff.sh baseline/v3-snapshot.json benchmark/v4-snapshot.json`. Must exit 0 (identical). Record result in `specs/shelf-sync-efficiency/benchmark/parity-result.md` (SC-003). If diff is non-empty, fix in Phase 3 and re-run.
- [ ] **T021** — Large-vault test: identify or synthesize a fixture with ≥50 GitHub issues and ≥20 PRDs under `docs/features/`. Run v4 against it. Verify no agent step hits its context ceiling. Record results in `specs/shelf-sync-efficiency/benchmark/large-vault-result.md` (SC-004). If a ceiling is hit, shrink the `obsidian-discover` index payload (e.g., drop fields) and re-run — DO NOT add a third agent (FR-001).
- [ ] **T022** — Caller-smoke: invoke `/shelf-sync` (which calls `shelf-full-sync` by name) and the `report-issue-and-sync` composed workflow on the benchmark repo. Verify zero caller-side changes were required and both complete successfully (SC-005).
- [ ] **T023** — Final terminal-summary check: verify `.wheel/outputs/shelf-full-sync-summary.md` contains `## Issues`, `## Docs`, `## Tags`, `## Progress`, `## Errors` in that order on a representative run (SC-006).
- [ ] **T024** — Write `specs/shelf-sync-efficiency/benchmark/v4-results.md` — one-page summary linking all benchmark artifacts, hard-gate pass/fail table, comparison to v3 baseline.
- [ ] **T025** — Commit Phase 4: `git add specs/shelf-sync-efficiency/benchmark/ && git commit -m "benchmark: shelf-full-sync v4 meets token + parity + large-vault gates"`.
