# Structural Hygiene Audit — 2026-04-23 16:18:26

**Audited repo**: /Users/ryansuematsu/Documents/github/personal/ai-repo-template
**Rubric**: plugin-kiln/rubrics/structural-hygiene.md (+ .kiln/structural-hygiene.config if present)
**gh availability**: available
**Result**: 4 signals

## Signal Summary

| rule_id | signal_type | cost | action | path | count |
|---|---|---|---|---|---|
| merged-prd-not-archived | editorial | editorial | archive-candidate | .kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md | 1 |
| merged-prd-not-archived | editorial | editorial | archive-candidate | .kiln/feedback/2026-04-23-feedback-should-interview-me-about.md | 1 |
| merged-prd-not-archived | editorial | editorial | archive-candidate | .kiln/feedback/2026-04-23-i-think-we-need-to.md | 1 |
| merged-prd-not-archived | editorial | editorial | archive-candidate | .kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md | 1 |

## Bundled: merged-prd-not-archived (4 items)

> **Accept or reject as a unit.** Per-item cherry-pick is out of scope for v1 — if the `merged-prd-not-archived` invariant holds for one item, it holds for all. To exclude a specific item, move it to `status: in-progress` manually and re-run the audit.

```diff
# rule_id: merged-prd-not-archived — PR #141 merged 2026-04-23
diff --git a/.kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md b/.kiln/feedback/completed/2026-04-23-claude-md-should-be-refreshed-audited.md
rename from .kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md
rename to .kiln/feedback/completed/2026-04-23-claude-md-should-be-refreshed-audited.md
--- a/.kiln/feedback/2026-04-23-claude-md-should-be-refreshed-audited.md
+++ b/.kiln/feedback/completed/2026-04-23-claude-md-should-be-refreshed-audited.md
@@ <frontmatter> @@
-status: prd-created
+status: completed
+completed_date: 2026-04-23
+pr: #141
# rule_id: merged-prd-not-archived — PR #141 merged 2026-04-23
diff --git a/.kiln/feedback/2026-04-23-feedback-should-interview-me-about.md b/.kiln/feedback/completed/2026-04-23-feedback-should-interview-me-about.md
rename from .kiln/feedback/2026-04-23-feedback-should-interview-me-about.md
rename to .kiln/feedback/completed/2026-04-23-feedback-should-interview-me-about.md
--- a/.kiln/feedback/2026-04-23-feedback-should-interview-me-about.md
+++ b/.kiln/feedback/completed/2026-04-23-feedback-should-interview-me-about.md
@@ <frontmatter> @@
-status: prd-created
+status: completed
+completed_date: 2026-04-23
+pr: #141
# rule_id: merged-prd-not-archived — PR #144 merged 2026-04-23
diff --git a/.kiln/feedback/2026-04-23-i-think-we-need-to.md b/.kiln/feedback/completed/2026-04-23-i-think-we-need-to.md
rename from .kiln/feedback/2026-04-23-i-think-we-need-to.md
rename to .kiln/feedback/completed/2026-04-23-i-think-we-need-to.md
--- a/.kiln/feedback/2026-04-23-i-think-we-need-to.md
+++ b/.kiln/feedback/completed/2026-04-23-i-think-we-need-to.md
@@ <frontmatter> @@
-status: prd-created
+status: completed
+completed_date: 2026-04-23
+pr: #144
# rule_id: merged-prd-not-archived — PR #144 merged 2026-04-23
diff --git a/.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md b/.kiln/issues/completed/2026-04-23-stale-prd-created-issues-not-archived.md
rename from .kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md
rename to .kiln/issues/completed/2026-04-23-stale-prd-created-issues-not-archived.md
--- a/.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md
+++ b/.kiln/issues/completed/2026-04-23-stale-prd-created-issues-not-archived.md
@@ <frontmatter> @@
-status: prd-created
+status: completed
+completed_date: 2026-04-23
+pr: #144
```

## Notes

- No notes.
- Override rules applied: none
