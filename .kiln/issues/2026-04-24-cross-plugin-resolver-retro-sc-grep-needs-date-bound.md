---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: medium
suggested_command: /kiln:kiln-fix
tags: [retro, prompt-template, success-criteria]
---

# Spec-template grep-style success criteria need a date-bound qualifier or they auto-flag historical noise

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; impl-migration-perf friction note §T055 + auditor friction note §"SC-F-6 archive-grep caveat"

## Description

SC-F-6 was authored as:

> `git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json`
> Expected: empty.

The post-PRD substantive assertion (new archives produced after the migration have zero matches) is correct and passes via `consumer-install-sim.sh` assertion (e). But the literal spec-text formulation returns **71 matches** across pre-PRD historical archives — every auditor that runs the grep verbatim has to spend time chasing why "the SC fails" before realizing it's historical noise.

impl-migration-perf documented the date-bound formulation that excludes pre-cfe0f11 archives. The spec text never adopted it.

## Proposed prompt rewrite

**File**: `plugin-kiln/templates/spec-template.md` (Success Criteria authoring guidance)

**Current**: No guidance on grep-style success criteria; authors write the simplest formulation, which auto-flags historical noise on long-lived projects.

**Proposed**: Add an authoring note + recipe to the spec template:

```markdown
> **Authoring note — grep-style success criteria**: a `git grep` SC against
> a directory with historical state (`.wheel/history/`, `archive/`,
> `migrations/`, etc.) must include a date or commit cutoff or auditors will
> auto-flag pre-PRD matches. Recipe:
>
>     # Files modified since the PRD landed:
>     git log --name-only --pretty='' --since='YYYY-MM-DD' \
>         -- '<glob>' \
>       | sort -u \
>       | xargs -I{} git grep -lE '<pattern>' -- {}
>     # Expected: empty.
>
> Or, prefer to express the SC against a fresh artifact produced by a
> consumer-install simulation (the substantive assertion) rather than a
> directory-wide scan of historical state.
```

**Why**: This was the same friction surfaced by auditor + impl-migration-perf independently. Codifying the recipe in the template prevents the next PRD from re-discovering it.

## Forwarding action

- Patch `plugin-kiln/templates/spec-template.md` per above.
- Re-state SC-F-6 in this PRD's spec.md with the date-bound formulation (or point at `consumer-install-sim.sh` assertion (e) as the canonical assertion).
