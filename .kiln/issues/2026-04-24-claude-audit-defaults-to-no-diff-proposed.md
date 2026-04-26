---
id: 2026-04-24-claude-audit-defaults-to-no-diff-proposed
title: "claude-audit findings default to 'no diff proposed pending maintainer call' instead of producing actual unified diffs"
type: improvement
date: 2026-04-24
severity: high
area: kiln
category: design
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-claude-audit-emit-real-diffs.md
---

## Summary

The skill's `## Proposed Diff` output convention is "git-diff-shaped proposal" — the maintainer reviews and applies. In practice, when a finding fires that is harder to mechanize (long-prose compression, structural recommendation, "consider trimming this section"), the audit punts with comment-only diff hunks like:

```
# rule_id: external/length-density — file is 252 lines vs the ~200-line guidance
# Most-trimmable target: ## Available Commands (lines 160–217, 58 lines).
# ...
# No diff proposed for this finding directly — it is a structural recommendation rather than
# a mechanical edit. See "Notes" for the suggested follow-up.
```

That defeats the audit. The maintainer's job is to APPROVE or REJECT a proposed change. The audit's job is to PROPOSE one. "No diff proposed pending maintainer call" pushes the work back to the human who invoked the audit to get the work done.

In this session, the user had to challenge the audit ("isn't it your job to actually propose the new file?") before the audit produced concrete one-liner replacements, a relocation diff for the `.shelf-config` subsections, and an actual `## Testing` block addition. None of that was hard to draft — the audit just defaulted to deferring instead of doing.

## Concrete pain

- 3 of the 5 best-practices deltas in the first audit run were filed with "No diff proposed pending the maintainer call" or "No mechanical diff proposed pending the maintainer call on whether to compress or rewrite this section wholesale."
- The maintainer then has to hand-author the diffs that the audit could have authored — duplicated effort.
- "Inconclusive" is reserved for editorial LLM failures (timeout, parse failure). Punting on a structural finding is a different mode that the rubric doesn't surface, so the maintainer can't tell what the audit *tried* vs what it *gave up on*.

## Proposed direction

Add Step 3.5 to `kiln-claude-audit/SKILL.md`: **every fired signal MUST produce one of three artifacts**:

1. **A concrete unified diff** — git-apply-shaped, hunk-by-hunk, with rule_id annotation. This is the default expectation for any fired signal.
2. **An explicit `inconclusive` row** — with a stated reason in the Notes section (e.g. "constitution body not loaded into context for editorial pass — re-run with `--load-constitution` to fire this rule"). `inconclusive` is the only legitimate non-diff bucket.
3. **`keep` / `keep (load-bearing)`** — for rules that explicitly only ever emit `keep` (the `load-bearing-section` rule) or are demoted by reconciliation.

There is **no fourth bucket**. Comment-only diff hunks ("structural recommendation, no diff proposed") are forbidden. If a finding fires, it produces a diff or an `inconclusive` with a reason — never both, never neither.

Add a test fixture under `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` that runs the audit against a CLAUDE.md known to fire the length-density rule and asserts the output contains zero `# ... No diff proposed` lines.

## Pipeline guidance

High severity. The audit's contract IS to propose; stripping the punt-bucket is a one-skill-body edit + one test fixture. Good `/kiln:kiln-fix` candidate (existing spec at `specs/kiln-self-maintenance/` may already accommodate, otherwise full pipeline).
