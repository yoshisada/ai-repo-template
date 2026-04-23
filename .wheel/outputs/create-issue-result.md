---
step: create-issue
status: complete
issue_path: .kiln/issues/2026-04-23-build-prd-step4b-still-broken-post-pr144.md
issue_id: 2026-04-23-build-prd-step4b-still-broken-post-pr144
title: /kiln:kiln-build-prd Step 4b still broken after PR #144 — two more pipelines leaked prd-created items
severity: high
area: workflow
duplicate_found: false
---

Created new backlog issue at `.kiln/issues/2026-04-23-build-prd-step4b-still-broken-post-pr144.md`.

Duplicate check: the adjacent `2026-04-23-stale-prd-created-issues-not-archived.md` is already archived as completed (PR #144 shipped its Part B safety net). This new issue covers Part A (root-cause Step 4b), which remained open and now has fresh evidence from pipelines #141 and #144 both leaking.

Classification:
- severity: high — 100% reproduction rate, every /kiln:kiln-build-prd run leaves stale items
- category: workflow — Step 4b of the build-prd skill
- 4 concrete fix vectors captured (diagnostic logging, path normalization, feedback-side scan, smoke test)
