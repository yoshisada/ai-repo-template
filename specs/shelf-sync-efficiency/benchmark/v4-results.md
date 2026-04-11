# v4 Results — Summary

See `specs/shelf-sync-efficiency/benchmark-results.md` for the full
hard-gate scorecard.

## Evidence index

| Artifact | Path |
|---|---|
| Hard-gate scorecard + methodology | `benchmark-results.md` |
| Token cost analysis | `benchmark/v4-token-cost.md` |
| Parity result (deferred) | `benchmark/parity-result.md` |
| Large-vault result (deferred) | `benchmark/large-vault-result.md` |
| Caller smoke (PASS by construction) | `benchmark/caller-smoke.md` |
| Summary shape check (PASS) | `benchmark/summary-shape-check.md` |
| v3 baseline workflow | `baseline/shelf-full-sync-v3.json` |
| v3 token cost baseline | `baseline/v3-token-cost.md` |
| v4 workflow (the deliverable) | `../../plugin-shelf/workflows/shelf-full-sync.json` |
| compute-work-list.sh | `../../plugin-shelf/scripts/compute-work-list.sh` |
| generate-sync-summary.sh | `../../plugin-shelf/scripts/generate-sync-summary.sh` |
| Snapshot capture | `../../plugin-shelf/scripts/obsidian-snapshot-capture.sh` |
| Snapshot diff | `../../plugin-shelf/scripts/obsidian-snapshot-diff.sh` |

## v3 vs v4 at a glance

|  | v3 | v4 |
|---|---|---|
| Agent steps | 4 | **2** |
| Command steps | 7 | 8 |
| Total steps | 11 | 10 |
| Schema version | 3.0.0 | **4.0.0** |
| Token cost on benchmark repo | 64.5k (memory, 2026-04-07) | ~37k (structural estimate; needs live confirmation) |
| Dashboard read-modify-write | 2 separate agents | 1 inside obsidian-apply |
| Diff logic location | inside agent prompts | command step (`compute-work-list.sh`) |
| Raw upstream JSON injected into agents | yes (dominant cost driver) | no (agents only see pre-filtered work list) |

## What the auditor should do next

1. Run one live `/wheel-run shelf-full-sync` on the pinned benchmark repo
   to confirm SC-001.
2. If SC-001 passes, run v3 + v4 against a frozen fixture and diff the
   snapshots for SC-003.
3. If SC-003 reveals semantic diffs (expected — see caveat in
   benchmark-results.md risk #3), decide whether to relax the parity
   gate or tighten v4's rendering.
4. Mark Phase 4 tasks complete (or flag a blocker) and proceed to PR
   creation.
