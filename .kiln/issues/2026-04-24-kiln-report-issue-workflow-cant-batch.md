---
id: 2026-04-24-kiln-report-issue-workflow-cant-batch
title: "kiln-report-issue wheel workflow has no batching support — N issues = N wheel invocations, encouraging skill-bypass for reflective filings"
type: improvement
date: 2026-04-24
status: open
severity: medium
area: kiln
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-report-issue/SKILL.md
  - plugin-kiln/workflows/kiln-report-issue.json
  - plugin-shelf/workflows/shelf-write-issue-note.json
  - plugin-shelf/scripts/shelf-counter.sh
  - specs/report-issue-speedup/spec.md
---

## Summary

`/kiln:kiln-report-issue`'s SKILL.md says: "If the user reports multiple issues at once, run the workflow once per issue." The workflow JSON (`plugin-kiln/workflows/kiln-report-issue.json`) is one-issue-per-invocation by design — its 4 steps (`check-existing-issues` → `create-issue` → `write-issue-note` → `dispatch-background-sync`) all assume a single issue description in context.

This breaks down for **reflective batch filings**: post-audit reflections, retrospective triages, multi-issue feedback bundles. In this session, after a CLAUDE.md audit produced 7 distinct findings worth tracking, the natural ask was "fill multiple issues" — and the only ways to do that were:

- **Strict adherence**: invoke the wheel workflow 7 times sequentially. Each spawns a wheel-runner agent, each does its own dedup + create + Obsidian write + counter increment. Heavy on tokens, time, and agent surface.
- **Skill bypass**: write the issue files directly with proper frontmatter, skip the wheel workflow entirely, rely on the next `/shelf:shelf-sync` to mirror. Fast but bypasses the dedup check, the per-issue Obsidian write, and the counter logic.

I chose the bypass path. That's a tell — when the canonical skill makes the user's actual workflow impractical, they bypass it. Bypassing means losing the dedup check (real risk: file a duplicate of an existing issue under a slightly different slug) and losing the immediate Obsidian mirror (acceptable, but a regression on the FR-001 lean-path contract).

## Concrete pain

- 7 wheel invocations to file 7 related issues = 7× the agent dispatch overhead, plus 7× the bg sub-agent spawns, plus a counter that ticks 7 times against a threshold designed around per-session pacing (default 10 → 7 issues nearly trips a full reconciliation in one batch).
- The `check-existing-issues` step runs against the same `.kiln/issues/` directory state for all 7 issues — it's repeated work that could be a single dedup pass.
- The `write-issue-note` step writes 7 separate Obsidian notes via 7 MCP `create_file` calls. A batch variant could pack them into one shelf-side traversal.
- The foreground summary FR-010 (issue path / Obsidian path / counter status) emits 7 times — N copies of mostly-redundant output.
- The "skip the workflow when batching" pattern is exactly the kind of skill-bypass the system's design tries to discourage. It's pragmatic but defeats the dedup + mirror invariants.

## Proposed direction

Three options, increasing in scope:

### (A) Add `--batch <file>` flag accepting a manifest of issues

Caller passes a manifest path (markdown or JSON) listing N issues. Each entry has the same shape as the single-issue input (description, optional severity, optional area). Workflow processes them in one invocation:

```bash
/kiln:kiln-report-issue --batch .kiln/inbox/2026-04-24-claude-audit-batch.md
```

Workflow steps re-shape:

1. **`check-existing-issues`** — runs once against the union of all N descriptions; emits a per-issue dedup verdict.
2. **`create-issue-batch`** — classifies and writes all N files in `.kiln/issues/` in one pass.
3. **`write-issue-note-batch`** — single shelf workflow call that writes all N Obsidian notes (requires sibling improvement to `shelf:shelf-write-issue-note` to accept a list).
4. **`dispatch-background-sync`** — counter increments by **N**, not 1 (so threshold semantics stay honest); single bg sub-agent spawn handles the full reconciliation if rolled over.

Foreground summary aggregates: "filed N issues at <paths>; counter <before>→<after>/<threshold>."

### (B) Add a sibling `kiln-report-issue-batch` skill

Same idea but a separate skill so the single-issue path stays untouched. Trade-off: two skills to maintain, easier rollback if batch behavior has bugs.

### (C) Make batching the default behavior

`/kiln:kiln-report-issue` accepts either a single description OR a list. The skill detects the shape and routes accordingly. Most ergonomic but largest blast radius — every existing call site needs verification.

(A) is the right shape — explicit flag, single skill, single workflow JSON, no surprise behavior change.

## Counter semantics under batching

The `shelf_full_sync_counter` was designed around per-invocation pacing (per `specs/report-issue-speedup/spec.md` FR-006). Batching N issues in one invocation creates a question: does the counter tick by 1 (the invocation) or N (the issues)?

Recommend: **counter ticks by N**. Rationale: the counter exists to gate full Obsidian reconciliation cadence. The cadence is "every K issues filed," not "every K times the user typed a command." Sub-agents own the counter RMW under flock; they can apply a `+N` increment atomically per invocation.

Edge case: batch crossing the threshold mid-list. E.g. counter at 8, threshold 10, user files 5 issues in one batch → counter would land at 13, past the threshold. Two options:

- **Apply +N, run reconciliation if final value ≥ threshold, reset to `final_value mod threshold`.** Cleanest. Counter lands at 3 after the batch.
- **Cap the increment at the threshold, run reconciliation, reset to 0, then continue with leftover increment from 0.** More complex but ensures exactly one reconciliation per N-issue batch when the threshold is crossed.

First option is simpler and matches the existing "approximately every K" framing.

## Proposed acceptance

- `/kiln:kiln-report-issue --batch <manifest>` accepts a markdown or JSON manifest with N issue entries; workflow runs all 4 steps once with N-aware semantics.
- Per-issue dedup still runs against the existing `.kiln/issues/` directory; the dedup verdict per issue surfaces in the foreground summary.
- Single Obsidian-write call covers all N notes (sibling improvement to `shelf:shelf-write-issue-note`).
- Counter increments by N atomically; reconciliation fires once if the threshold is crossed.
- Foreground summary aggregates: list of paths, dedup verdicts, counter delta.
- Test fixture under `plugin-kiln/tests/kiln-report-issue-batch/` with N=3 (under threshold), N=10 (exactly threshold), N=15 (crosses threshold).

## Why medium-severity

The skill works for single-issue use, which is the common case. Batch use is friction-revealing — the user CAN bypass the skill, and bypass produces correct files (we verified in this session), so nothing is broken today. But every bypass is a missed opportunity for the dedup check to catch a duplicate slug, and every reflective batch filing pushes the user toward the bypass pattern.

The `claude-audit-no-depth-tier-or-reaudit-support` issue and this issue share a root cause: skills designed for the single-call common case don't degrade gracefully when the actual ergonomic call is N at once.

## Pipeline guidance

Medium. Workflow JSON edit + skill body update + sibling shelf workflow batch variant + counter helper update + test fixture. Could fit in a `/kiln:kiln-fix` if the existing `report-issue-speedup` spec accommodates batching as a follow-on FR; otherwise full PRD via `/kiln:kiln-distill --kind feature` (likely bundled with the claude-audit-evolution theme since both surface from the same session).
