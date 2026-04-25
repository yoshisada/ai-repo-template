---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: medium
suggested_command: /kiln:kiln-fix
tags: [retro, prompt-template, nfr-language]
---

# NFR-atomic-commit phrasing is ambiguous between "single feature-branch commit" and "single squash-merge to main"

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; auditor friction note (`agent-notes/auditor.md` §"NFR-F-7 atomic-migration deviation")

## Description

NFR-F-7 in this PRD's spec read:

> FR-F5's migration of `kiln-report-issue.json` lands in the same commit as the resolver/registry/preprocessor implementation. No half-state where the workflow declares `requires_plugins` but the resolver isn't running yet.

The actual landing was **3 commits** on the feature branch (`cfe0f11` → `138f20c` → `7643e61`), with the migration last. The dangerous half-state never materialized because the migration was the last commit — but the strict-reading audit had to spend time arguing why the deviation was acceptable. Both the auditor and impl-migration-perf flagged the ambiguity for the retro.

The team-lead's coordination protocol almost certainly meant "single squash-merge to main" (which the PR achieves), not "single commit on the feature branch." But the spec text reads as the latter.

## Proposed prompt rewrite

**File**: `plugin-kiln/templates/spec-template.md` (NFR section / authoring guidance)

**Current**: NFR template has no explicit guidance on atomic-landing language; PRD authors free-form "lands in the same commit," which is ambiguous.

**Proposed**: Add an authoring note to the NFR section of the spec template:

```markdown
> **Authoring note — atomic-landing NFRs**: when the invariant you're guarding
> is "no half-state across the change set," prefer the phrase "lands in a
> single squash-merge to main" rather than "single commit." Feature-branch
> work-in-progress commits are not the half-state that matters; the half-state
> that matters is what lands on `main` for downstream consumers. If you
> genuinely need feature-branch commit-by-commit safety (e.g. bisectability),
> say "every intermediate commit on the feature branch must be runnable" and
> add a CI check.
```

**Why**: The current language pushed the auditor to write a multi-paragraph "deviation, not blocking" justification. A clearer template prevents the cycle where every architectural-feature PRD re-litigates the same ambiguity.

## Forwarding action

- Patch `plugin-kiln/templates/spec-template.md` per above.
- Re-state the spec text for `cross-plugin-resolver-and-preflight-registry` NFR-F-7 retroactively (single-line edit) so the spec record matches the realized intent.
