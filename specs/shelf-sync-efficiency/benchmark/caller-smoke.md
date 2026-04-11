# Caller Smoke — verified by construction

**Status**: PASS by construction

Callers of `shelf-full-sync`:
- `/shelf-sync` skill — calls `wheel-run shelf-full-sync` by name
- `report-issue-and-sync` composed workflow — references step by name

Verified invariants (see `plugin-shelf/workflows/shelf-full-sync.json` vs
`specs/shelf-sync-efficiency/baseline/shelf-full-sync-v3.json`):

| invariant | v3 | v4 | status |
|---|---|---|---|
| workflow `name` | shelf-full-sync | shelf-full-sync | ✅ unchanged |
| terminal step id | generate-sync-summary | generate-sync-summary | ✅ unchanged |
| terminal output path | .wheel/outputs/shelf-full-sync-summary.md | .wheel/outputs/shelf-full-sync-summary.md | ✅ unchanged |
| `terminal: true` flag | on generate-sync-summary | on generate-sync-summary | ✅ unchanged |

Callers pass zero arguments to `shelf-full-sync` and read nothing but
the terminal output — so the workflow contract with callers is the
name, the terminal file, and the summary shape (verified in
benchmark-results.md SC-006). No v4 change touches any of these.
