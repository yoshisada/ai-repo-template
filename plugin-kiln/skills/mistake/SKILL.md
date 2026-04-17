---
name: mistake
description: Capture an AI-made mistake (wrong assumption, bad tool call, missed context) as a schema-conformant note in .kiln/mistakes/. Shelf picks it up on the next sync and files a proposal in @inbox/open/ for human review. Use as "/kiln:mistake <free-form description>" or "/kiln:mistake" (skill will prompt for one).
---

# Mistake — Capture an AI Mistake for Future Agents

Log a specific AI error — a wrong assumption, a bad tool call, a misread of context — as a schema-conformant note in `.kiln/mistakes/`. The `shelf-full-sync` sub-workflow runs next and files a review proposal in `@inbox/open/`. On acceptance, the maintainer moves the note into the project's `mistakes/` folder where it becomes training data for future AI agents working on a similar stack.

This skill delegates to the `report-mistake-and-sync` wheel workflow. All structured collection, linting, and file writes happen inside the workflow's `create-mistake` agent step — this skill's job is to invoke the workflow with the user's description.

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate Input

If `$ARGUMENTS` is empty, ask the user: "What was the mistake? Describe the wrong assumption and the correction." Wait for a reply before starting the workflow.

Otherwise, confirm the mistake description is in the conversation context — the workflow's `create-mistake` agent step will read the activation context and pull the description from there.

## Step 2: LLM Guardrails (read-only reference)

These rules are enforced by the workflow's `create-mistake` agent step. They are quoted here so the invoking agent enters the workflow primed with the honesty principle and tagging expectations. Source: `@manifest/types/mistake.md`.

### The honesty principle

Write every mistake field in the first person, past or present tense as specified, **unhedged**. Mistake notes are useful *only* if they're honest. Hedged language ("a minor judgment call that could have been better") is noise — it trains future agents to hedge in turn.

- The `assumption` field states the false belief as a plain sentence, first person past tense. "I assumed the visible tool list was complete." Not "I may have underestimated the available tool surface."
- The `correction` field states the right understanding, equally plain. "The visible tool list is partial by design; tool_search loads deferred tools on demand."

A mistake note is not an apology. It is a warning label with evidence. Do NOT soften language to protect the model.

### Severity calibrates to outcome, not effort

- **`minor`** — wasted time, created noise, small rework. No lasting artifact.
- **`moderate`** — produced an artifact that had to be undone or rewritten. Shipped a bug users encountered but didn't lose data.
- **`major`** — caused data loss, security exposure, or blocked progress for others. Also covers sustained pattern errors.

A typo fixed in 30 seconds may be **major** if it corrupted data. A 2-hour debug session may be **minor** if the only cost was time. Calibrate to outcome.

### Do not write mistake notes about the human

Mistakes capture AI errors. A user changing direction mid-conversation is not an AI mistake — it's the user exercising judgment. If the user "corrected" an AI's assumption, that's a mistake; if the user changed what they wanted, that's not.

### The filename slug names the trap

The workflow derives the filename slug from the `assumption` field, not the `correction`. The slug names the trap future agents should watch for — not the action taken to escape it. Example: `2026-04-16-assumed-tool-list-complete.md` is correct; `2026-04-16-ran-tool-search.md` describes the fix, not the trap.

### Three-axis tagging is load-bearing

Every mistake note MUST carry tags on three axes. The workflow's tag lint enforces this. An under-tagged mistake is not discoverable by the queries future agents will run, so it isn't training data.

1. **Exactly one `mistake/*` tag** — the class: `mistake/assumption`, `mistake/tool-use`, `mistake/scope`, `mistake/context`, `mistake/fabrication`, `mistake/premature-action`, or `mistake/communication`.
2. **At least one `topic/*` tag** — what the mistake was about.
3. **At least one stack tag** — `language/*`, `framework/*`, `lib/*`, `infra/*`, `testing/*`, or `blockchain/*`.

## Step 3: Run Workflow

Run `/wheel-run kiln:report-mistake-and-sync` to start the workflow. It will:

1. List existing mistake files (for duplicate detection).
2. Collect the 7 required frontmatter fields + 5 body sections, apply the honesty lint and three-axis tag lint, derive the filename slug from the assumption, and write `.kiln/mistakes/YYYY-MM-DD-<slug>.md`.
3. Hand off to `shelf:shelf-full-sync`, which files a proposal in `@inbox/open/` for human review.

The user's description (from `$ARGUMENTS`) is already in the conversation context — the workflow's agent step will pull it from activation context.

## Rules

- If the user reports multiple mistakes at once, run the workflow once per mistake.
- If `$ARGUMENTS` is empty, ask before starting the workflow — don't start it with no description.
- Do NOT prompt the user for `severity`, `tags`, `status`, `made_by`, `assumption`, `correction`, or body sections. Those are owned by the workflow's `create-mistake` agent step.
- Do NOT run the honesty lint or tag lint here. Those are owned by the workflow.
- Do NOT write any file. File writes are owned by the workflow.
