---
id: 2026-04-24-precedent-reader-helper
title: "precedent-reader — internal precedent-lookup helper for agents and skills"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: moderate
context_cost: ~2 sessions
---

# precedent-reader — internal precedent-lookup helper for agents and skills

## Intent

An internal primitive (not a slash command) that any skill or agent can call to query accumulated user-decision precedent before escalating a choice to the human. Fills the infrastructure gap behind the vision's "context-informed autonomy" principle — today that principle is philosophy, not infrastructure.

## Hardest part

Defining *what counts as precedent* and with what weight. `.kiln/feedback/` is explicit; `.kiln/mistakes/` is corrective; an approved manifest-improvement proposal is a template-level precedent; a declined non-goal is a hard "no." These have different shapes and different decay rules — a naive aggregator would either dilute strong signals (treating everything equally) or miss signals entirely (ignoring non-file-based context).

## Assumptions

- The existing project-context reader (`plugin-kiln/scripts/context/read-project-context.sh`) is the right architectural template: deterministic JSON, `LC_ALL=C`, path/name-sorted output, no hidden state.
- Precedent sources live in files already: `.kiln/feedback/`, `.kiln/mistakes/`, `.kiln/roadmap/items/` (for `kind: non-goal` and `kind: critique`), approved-proposal records. No new capture surface needed.
- Consumers are willing to pass a "query context" string to scope the lookup — callers know what they're asking about; the helper doesn't need to do NLP magic.

## Architecture

- Location: `plugin-kiln/scripts/precedent/`
- Entry: `read-precedent.sh <query-context>` → emits deterministic JSON
- Helpers: one reader per source (`read-feedback.sh`, `read-mistakes.sh`, `read-declined-non-goals.sh`, `read-approved-proposals.sh`)
- Output schema (sketch):
  ```
  {
    schema_version: 1,
    query: "<echoed context>",
    precedent: {
      feedback: [{ path, summary, relevance_hint }],
      mistakes: [{ path, lesson, relevance_hint }],
      non_goals: [{ id, rationale, hard_boundary: bool }],
      approved_proposals: [{ path, what_was_approved }]
    },
    summary: { has_precedent: bool, strong_signals: int, conflicts: [...] }
  }
  ```

## Consumers

- build-prd implementers — check before hardcoding an assumption that might contradict past feedback
- auditors — check before flagging a "violation" that the human has previously explicitly approved as an exception
- roadmap / vision interviews — pre-answer questions the user has already answered, skip them
- self-improvement loop (shelf-propose-manifest-improvement) — suppress proposals that restate already-approved precedent
- roadmap routing (kiln-roadmap Step 2) — check whether the user has already declined this framing before re-asking

## Dependencies

- The project-context reader is the architectural model, not a runtime dependency.
- Depends on the existing capture surfaces continuing to live at predictable paths (`.kiln/feedback/`, `.kiln/mistakes/`, etc.) — if those move, the precedent reader breaks. Worth noting in manifest if/when paths are formalized.

## Failure modes to avoid

- **Over-broad matches that trigger false precedent.** If the query "add a new skill" matches every feedback note mentioning skills, the consumer will drown in noise and stop using the reader. Relevance hint / scoring matters.
- **Stale precedent.** Feedback from 6 months ago on a shipped feature should weigh less than feedback from last week on an in-flight PRD. Recency + status awareness needed.
- **Silent non-lookup.** A consumer that *should* have checked precedent but didn't (because the skill author forgot) is worse than no helper at all — it violates the vision claim while appearing to honor it. Worth a linter/hook check over time that flags "escalation-prone agent call without precedent read."

## Success signal

When a skill or agent calls `read-precedent.sh` and the output changes its behavior — skips an interview question, suppresses a proposal, flags a violation, or surfaces a conflict — the infrastructure is doing its job. Absent such measurable behavior change, the helper is decorative.
