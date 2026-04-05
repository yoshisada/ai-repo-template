# Auditor Friction Notes: Wheel Session Guard

**Agent**: auditor
**Date**: 2026-04-05

## What went well

- Implementation was clean and consistent across all 6 hooks. The guard integration pattern was identical in every hook, making auditing straightforward.
- The contracts/interfaces.md was precise enough that verifying compliance was mechanical — function signatures, exit codes, and pass-through responses all matched exactly.
- Smoke testing guard_check in isolation was simple because it only depends on jq and a state.json file — no engine startup needed.
- The first-hook stamping design (FR-004) elegantly sidesteps the problem of /wheel-run not having hook input context.

## What was confusing

- I was initially assigned while Task #1 (specifier) was still in_progress. The task dependency system correctly blocked me, but I had to message the team lead and wait. A clearer "you will be notified when unblocked" signal would reduce back-and-forth.
- The FR numbering in the session-guard spec (FR-001 through FR-007) overlaps with FR numbers in the original wheel spec (also FR-001, FR-002, etc.). During audit I had to be careful about which FR-002 was being referenced — the wheel one (state persistence) or the session-guard one (hook guard calls). Namespacing FRs per feature would help.

## Suggestions for improvement

- A lightweight shell test harness (even just a test.sh that sources guard.sh and runs assertions) would make smoke testing repeatable and CI-friendly rather than relying on manual verification each audit.
- The blockers.md artifact feels unnecessary when there are zero blockers. Consider making it optional — only create when blockers exist.
