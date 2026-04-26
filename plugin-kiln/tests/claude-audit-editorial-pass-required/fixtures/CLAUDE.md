# CLAUDE.md (fixture — claude-audit-editorial-pass-required)

This fixture deliberately paraphrases an article from
`fixtures/.specify/memory/constitution.md` so the audit's
`duplicated-in-constitution` rule fires. The paraphrase is the same
substantive claim as Article IV's "4 Gates" — written in the prose
shape a real-world drift produces.

## What This Repo Is

A toy project used to verify the editorial-pass-required contract.

## Hooks Enforcement (4 Gates)

We use four hook gates to enforce the workflow. Hooks run before every
file edit and block writes when prerequisites aren't met. The gates are:

1. A spec must exist at `specs/<feature>/spec.md` before any code edit.
2. A plan must exist at `specs/<feature>/plan.md` before code edits.
3. A tasks file must exist at `specs/<feature>/tasks.md` before code edits.
4. At least one task in `tasks.md` must be marked `[X]` before code edits.

If a hook blocks you, complete the missing artifact first.

## Build & Development

```bash
npm install
npm test
```

The `## Hooks Enforcement (4 Gates)` section above is the same content
as Article IV of the constitution — paraphrased rather than cited. The
audit's editorial pass should detect the duplication and propose
replacing the section with a one-line pointer to Article IV.
