# Interface Contracts: Kiln Capture-and-Fix Loop Polish

**Spec**: [../spec.md](../spec.md)
**Plan**: [../plan.md](../plan.md)

This feature is skill-authoring work (Markdown + inline Bash). There are no new exported functions to define. The contracts below pin three behavioral surfaces that MUST match across implementers.

## Contract 1 — Feedback frontmatter schema

Every file written to `.kiln/feedback/<YYYY-MM-DD>-<slug>.md` by `/kiln:kiln-feedback` (spec FR-009) MUST have this YAML frontmatter shape:

```yaml
---
id: <YYYY-MM-DD>-<slug>                  # REQUIRED. Matches filename without .md.
title: <one-line human-readable title>    # REQUIRED. Non-empty.
type: feedback                            # REQUIRED. Literal string, not user-picked.
date: <YYYY-MM-DD>                        # REQUIRED. UTC date of creation.
status: open                              # REQUIRED on create. Lifecycle: open → prd-created → completed.
severity: low | medium | high | critical  # REQUIRED. Exactly one of these four values.
area: mission | scope | ergonomics | architecture | other # REQUIRED. Exactly one of these five.
repo: <URL> | null                        # REQUIRED KEY. Value is URL string or literal null.
prd: <path>                               # OPTIONAL. Added by distill when status flips to prd-created.
files:                                    # OPTIONAL. Omit entirely when none detected.
  - <path>
---
```

**Validation rule (for distill and test code)**: a feedback file is considered valid if and only if all seven REQUIRED keys are present and the enum-typed fields (`severity`, `area`) match one of the allowed values. Any other value is an error.

**Body**: freeform markdown. No required structure.

## Contract 2 — Reflect gate predicate

`/kiln:kiln-fix` Step 7 (spec FR-003) MUST evaluate the reflect gate against the composed envelope using this predicate (or any equivalent that preserves the three conditions):

> **Gate fires (proposal is written)** if ANY of:
>
> 1. Any element of `envelope.files_changed` matches regex `^plugin-[^/]+/(templates/|skills/[^/]+/SKILL\.md$)` — i.e. a template file or a skill definition was touched.
> 2. `envelope.issue` OR `envelope.root_cause` contains (case-insensitive) substring `@manifest/` OR `manifest/types/`.
> 3. `envelope.fix_summary` contains a template path — regex `plugin-[^/]+/templates/` OR whole-word `templates/` preceded by `^` or a non-alphanumeric.
>
> **Otherwise gate does NOT fire** (main chat skips reflect silently; no proposal is written, no user-visible error).

Reference implementation in `plan.md` §Decision 1. Implementers may rewrite but MUST preserve all three conditions.

**Observable behavior**: on a gate-miss, `Manifest proposal: none (no gap identified)` appears in the final report (unchanged from current text).

## Contract 3 — Distill dual-source read behavior

`/kiln:kiln-distill` Step 1 (spec FR-011) MUST read from both sources in this order:

```
# Pseudocode — reference shape
feedback_files = glob(".kiln/feedback/*.md") with frontmatter.status == "open"
issue_files    = glob(".kiln/issues/*.md", top-level only) with frontmatter.status == "open"
all_items = feedback_files + issue_files    # feedback first — preserves FR-012 ordering through the rest of the flow

if empty(all_items):
    report "No open backlog or feedback items."
    stop
```

Each item carries a `type` tag derived from its source directory (`feedback` vs `issue`) that persists through grouping and into the generated PRD.

### PRD-rendering rule (spec FR-012)

When generating the PRD in Step 4, the distill skill MUST:

1. Group items into themes as today. When a theme contains mixed types, it is a "feedback-shaped" theme.
2. Emit the `## Background` section by citing feedback themes first (before issue-only themes). If there are no feedback items in the run, fall back to today's behavior.
3. Emit the `## Problem Statement` in the same feedback-first order.
4. Emit the `## Goals` bullets keyed off feedback themes where any exist; issue-only themes contribute goal bullets beneath.
5. In `## Requirements`, place feedback-derived FRs before issue-derived FRs within each theme.
6. In the `### Source Issues` table, add a `Type` column with values `feedback` or `issue`, and sort rows so feedback appears first.

### Status-update rule (spec FR-013)

In Step 5, both feedback and issue files get the same frontmatter update:

- `status: open` → `status: prd-created`
- Append `prd: docs/features/<date>-<slug>/PRD.md`

Source type is irrelevant to the update — same protocol for both.

## Contract 4 — `/kiln:kiln-fix` "What's Next?" block

Every terminal path (spec FR-007) MUST end the final report with this structural shape:

```markdown
## What's Next?

- `<command-or-instruction-1>`
- `<command-or-instruction-2>`
- [optional] `<command-or-instruction-3>`
- [optional] `<command-or-instruction-4>`
```

- Minimum 2 bullets, maximum 4.
- Each bullet's primary command (or action phrase) MUST come from the allowed set:
  - `/kiln:kiln-next`
  - `/kiln:kiln-qa-final`
  - `/kiln:kiln-report-issue <follow-up>`
  - `review and ship the PR` (only when this run created a PR)
  - `nothing urgent — you're done`
- Selection policy (dynamic — plan Decision):
  - UI-adjacent fix (files_changed includes `.tsx|.jsx|.vue|.svelte|.css` or path matches `components/|pages/|views/|layouts/|app/`): `/kiln:kiln-qa-final` appears FIRST.
  - Escalation path (status=escalated): `/kiln:kiln-report-issue <follow-up>` appears FIRST.
  - Obsidian-skipped path: include a bullet noting the skip — e.g. `/kiln:kiln-fix` (retry after MCP reconnect) OR `nothing urgent — you're done`.
  - Default: `/kiln:kiln-next` appears FIRST.

## Out of contract

These are explicitly NOT pinned here (implementation discretion):

- Exact wording/casing of suggestion bullets beyond the command names.
- Whether the feedback skill prompts interactively for severity/area vs parses from `$ARGUMENTS` (spec FR-009 allows either; ASK on ambiguity is the only hard rule).
- Internal slug derivation algorithm (must match `/kiln:kiln-report-issue`'s behavior but the shared helper is unspecified).
- Exact MCP tool invocation argument shape — follow the MCP server's documented shape for `create_file`.
