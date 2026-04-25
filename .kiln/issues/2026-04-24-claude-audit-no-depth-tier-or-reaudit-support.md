---
id: 2026-04-24-claude-audit-no-depth-tier-or-reaudit-support
title: "claude-audit has no concept of 'first pass was thin, do a deeper pass' — substance findings only emerged after three explicit user challenges"
type: improvement
date: 2026-04-24
status: open
severity: medium
area: kiln
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
---

## Summary

The skill is invoked as `/kiln:kiln-claude-audit` (no flags). It runs the rubric + best-practices pass once and writes a single audit log. There is no notion of "first pass was rubric-only — re-run for substance" or `--depth=full`.

In this session, the first audit pass was rubric-mechanical: stale-section, length-density, excluded-category-drift, included-category-gap. The output looked complete. The user had to challenge it three times before substance findings emerged:

1. "isn't it your job to actually propose the new file?" — surfaced that "no diff proposed pending maintainer call" was the wrong default.
2. "we need to do a full fledged audit on this. 1. did you add anything about vision? 2. did we say anything about the loop? 3. did you read anything about the project?" — surfaced that the audit had loaded vision into context but not evaluated against it.
3. "do we still talk about those specify commands?" — surfaced the 44-line stale Mandatory Workflow section that the rubric did not flag.

Each challenge produced a *better* audit — but the user shouldn't need to issue them. The skill should produce the deeper audit on the first run, OR offer an explicit two-tier mode where the cheap pass produces a quick-look report and the substance pass produces a full one.

## Concrete pain

- A user who runs `/kiln:kiln-claude-audit` once and reads the output gets the rubric-mechanical version. They don't know to challenge it.
- The audit has no "depth indicator" — there's no field in the output that says "this audit ran rubric only, did NOT evaluate project-context grounding." So a thin audit looks the same as a deep one.
- The skill's `## Step` structure leads with project-context loading (Step 1), then rubric application (Step 3), then external best-practices (Step 3b). Substance evaluation isn't a step — it's implicit at best.
- The current output structure ranks rubric findings first; if substance findings exist they have to be retrofitted as additional rows. The maintainer reading top-to-bottom sees rubric concerns before substance concerns.

## Proposed direction

Three options, increasing in scope:

### (A) Reorder the default audit to lead with substance

Move the substance pass (currently nonexistent — see sibling issue `claude-audit-rubric-missing-substance-rules`) to Step 2, before the cheap rubric rules. Output ordering: substance findings first, rubric findings second, external best-practices third. This is the lowest-friction option once the substance rules exist.

### (B) Add `--depth` flag with two tiers

```
/kiln:kiln-claude-audit            # default: depth=substance — full audit
/kiln:kiln-claude-audit --depth=cheap   # rubric only, fast, for kiln-doctor subcheck
/kiln:kiln-claude-audit --depth=full    # substance + rubric + best-practices (alias for default)
```

The cheap mode is what `kiln-doctor` already invokes (per skill rationale: "Editorial LLM calls have no latency target for this skill"). Make the explicit flag visible.

### (C) Add an "audit-the-audit" / re-audit mode

`/kiln:kiln-claude-audit --re-audit` reads the latest `claude-md-audit-*.md` log and asks: did this audit evaluate the file against project-context (vision, roadmap, plugin suite)? Did every fired signal produce a concrete diff? Did any rules silently fall through to inconclusive? Emits a "audit quality" report. Useful for the kind of multi-turn challenge cycle this session went through.

(C) is most ambitious and probably outside the immediate scope; (A) is the right default; (B) makes the depth tradeoff explicit.

## Why medium-severity

The audit ultimately produced the right output, but only after multiple manual challenges. Users who don't push back will accept thin audits as complete. (A) alone fixes most of this. Pairs naturally with the high-severity substance-rules issue — same PRD.

## Pipeline guidance

Medium. (A) is a SKILL.md reorder + output-ordering change; cheap. (B) is a flag-handling addition. (C) is a separate skill or skill mode. File these as one issue but split the implementation by option in the resulting PRD.
