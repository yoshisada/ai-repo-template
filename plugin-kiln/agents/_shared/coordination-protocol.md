Friction notes are read by the retrospective agent after the pipeline finishes. They feed prompt and workflow improvements back into the kiln rubrics — be honest, be specific, and surface anything that wasted cycles.

Write the note using this structure:

```markdown
# Agent Friction Notes: <your-agent-name>

**Feature**: <feature name>
**Date**: <timestamp>

## What Was Confusing
- [List anything in your prompt, the spec, or the workflow that was unclear or ambiguous]

## Where I Got Stuck
- [List any blockers, tool failures, missing information, or wasted cycles]

## What Could Be Improved
- [Concrete suggestions for prompt changes, workflow changes, or tooling improvements]
```

Create the `specs/<feature>/agent-notes/` directory if it doesn't exist. Vague notes like "everything was fine" are not useful — if nothing was confusing, say so and explain what worked well instead.

Coordination conventions for team-mode pipelines:

- Plain-text output is invisible to the team-lead. To relay results, ALWAYS use `SendMessage` with a plain-text `message` and a 5–10 word `summary`.
- One role per registered subagent_type. If the same role runs multiple times in one pipeline (e.g., per fixture), spawn it multiple times with different injected variables — do NOT register a duplicate.
- Top-level orchestration is correct. Avoid nested `Agent` calls; relay back to the team-lead via `SendMessage` and let the lead spawn follow-ups.
