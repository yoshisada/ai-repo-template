# v3 Token Cost Baseline

**Workflow**: `shelf-full-sync` v3.0.0
**Measured via**: `report-issue-and-sync` composed workflow under a wheel-runner agent
**Date**: 2026-04-07
**Source**: `project_workflow_token_usage` auto-memory entry

## Headline number

**64,500 tokens** per single wheel-runner agent run on the benchmark repo.

## Composition

The 64.5k figure covers 13 steps total (3 parent + 10 child), which includes
all of `shelf-full-sync`'s 11 steps plus the outer `report-issue-and-sync`
steps that wrap it. The dominant cost driver inside `shelf-full-sync` is the
four agent steps: `sync-issues-to-obsidian`, `sync-docs-to-obsidian`,
`update-dashboard-tags`, `push-progress-update` — each pays agent spawn +
MCP registration + `context_from` injection on its own turn budget.

## Why this figure anchors SC-001

SC-001 requires v4 ≤30k tokens on this same benchmark repo. v3's 64.5k is
the "before" number the comparison is against. v4's target cut is
approximately 53% (34.5k token reduction) by consolidating 4 agents → 2 and
moving diff logic into command steps.

## Reproduction methodology

1. Check out `yoshisada/ai-repo-template` at commit
   `2973dedb4a0b3cfa8f8235bc30b369830af73e07`.
2. Ensure `.shelf-config` maps to slug=`ai-repo-template`, base_path=`projects`.
3. Under a wheel-runner agent, invoke `/wheel-run report-issue-and-sync`
   (or `/wheel-run shelf-full-sync` alone for a lower-bound figure).
4. Read per-agent token totals from the wheel-runner telemetry.

## Notes / caveats

- The 64.5k figure is for the composed workflow. A standalone
  `shelf-full-sync` run costs somewhat less because it omits the outer
  report-issue wrapper; the absolute delta is unmeasured but the four agent
  steps inside remain the dominant cost.
- v4 comparison MUST use the same invocation shape (composed via
  `report-issue-and-sync`) to be apples-to-apples with this baseline, OR
  must measure v3 and v4 both standalone — the implementer and auditor MUST
  agree on one methodology and apply it consistently.
- This feature is a workflow-file-only change: no wheel engine, no MCP
  surface, no prompt-caching regression expected between runs.

## Deferred direct re-measurement

A fresh end-to-end v3 run in this session is impractical (high cost, and we
are trying to avoid spending ~64.5k tokens to prove a number we already
have). If the auditor requires a fresh v3 number, it can be captured
alongside v4 in Phase 4 using the same methodology above.
