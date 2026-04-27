# impl-docs friction note — merge-pr-and-sc-grep-guidance

**Author**: impl-docs (team `kiln-merge-pr-and-sc-grep`)
**Date**: 2026-04-27
**Scope**: Theme B (Sections D, E, F of contracts/interfaces.md) — three documentation-edit surfaces.

## What I shipped

| Phase | Files | Commit | FRs |
|------:|-------|--------|-----|
| 8 | `plugin-kiln/templates/spec-template.md` | (rolled into specifier's correction commit `81eca4c3` — see Friction #1) | FR-012, FR-013, SC-005 |
| 9 | `plugin-wheel/lib/preprocess.sh`, `plugin-wheel/tests/preprocess-tripwire.bats` | `16e60f52` | FR-014, FR-016, SC-006 |
| 10 | `plugin-wheel/README.md` | `9c2bb262` | FR-015, SC-006 |
| 10b | this file | (next commit) | retrospective input |

All SC-005 and SC-006 grep sentinels assert green:

```
grep -F 'date-bound qualifier' plugin-kiln/templates/spec-template.md       → 1 match
grep -F -- "--since='YYYY-MM-DD'" plugin-kiln/templates/spec-template.md    → 1 match
grep -F 'documentary' plugin-wheel/lib/preprocess.sh                         → 1 match
grep -F 'rewrite as plain prose' plugin-wheel/lib/preprocess.sh              → 1 match
grep -F 'documentary' plugin-wheel/README.md                                 → ≥1 match
grep -F 'Writing agent instructions' plugin-wheel/README.md                  → ≥1 match (heading)
grep -lF 'documentary' plugin-wheel/lib/preprocess.sh plugin-wheel/README.md → both paths
```

The 11-test bats suite at `plugin-wheel/tests/preprocess-tripwire.bats` runs PASS with the extended two-line tripwire error.

## Friction encountered

### #1 — Concurrent staging hazard NFR-005 fired in spite of pathspec discipline

**What happened**: I edited `plugin-kiln/templates/spec-template.md` for Phase 8 (T080). Before I could commit, a parallel actor (specifier or another implementer) ran `git add` over my unstaged work as part of their own commit `81eca4c3` ("specify+plan+tasks: corrections — drop plugin.json edits; SC-002 <TODAY> placeholder"). My Phase 8 spec-template change ended up bundled into that commit alongside unrelated spec/plan/contracts/interfaces.md corrections + version-bump auto-staged plugin.json files.

**Why it matters**: NFR-005 explicitly disallows this — implementers are supposed to stage by exact path and never have their work hijacked. The hazard surfaced here despite my using `git commit -- <pathspec>` discipline, because the `git add` happened in a sibling shell I don't control. By the time I ran `git commit -- <my paths>`, my changes were already staged + committed under someone else's authorship and message.

**Mitigation**: I verified via `git show 81eca4c3 -- plugin-kiln/templates/spec-template.md` that the diff is byte-identical to what I wrote, and continued. SC-005 still passes. The traceability is degraded — auditors looking for FR-012/FR-013 will find them under a commit titled "specify+plan+tasks: corrections" rather than under a "docs(spec-template): SC-grep ..." commit.

**Recommended PI**: build-prd's parallel-implementer concurrency model needs a hard guard against `git add` outside an implementer's owned pathspec. Options to consider:
- Per-implementer staging directories (each implementer commits via a private worktree) — heaviest but bulletproof.
- Pre-commit hook that refuses commits containing files outside the committing actor's declared owned-paths set, derived from `tasks.md` Section header.
- Coordination protocol amendment: implementers MUST emit a "staging now" SendMessage to team-lead before `git add`, and team-lead serializes adds.

The lightest fix is probably the pre-commit hook — it's plugin-agnostic and catches the violation at the latest possible moment.

### #2 — Existing bats test asserted byte-exact tripwire output; FR-016 extension required test edit

**What happened**: `plugin-wheel/tests/preprocess-tripwire.bats` had several assertions of the form `[ "$output" = "$expected" ]` against the FR-F4-5 error string. FR-016 appends a new line to that string. Without updating the test, all 7 byte-exact assertions would have flipped red.

**Resolution in scope**: The "DO NOT TOUCH" list in tasks.md only covers `plugin-kiln/skills/`, `plugin-kiln/scripts/`, `plugin-kiln/tests/`, `plugin-kiln/.claude-plugin/` — explicitly NOT `plugin-wheel/tests/`. So updating the bats test is in-scope for impl-docs. I:
1. Updated `EXPECTED_ERROR_TEMPLATE` to the two-line form (FR-F4-5 line + FR-016 line).
2. Updated the verbatim-byte-match test to use a multi-line `expected` literal.
3. Added a new test `Tripwire error text contains the FR-016 documentary-references line` that specifically asserts the FR-016 substring (independent regression guard for SC-006).

All 11 tests pass. T094's "acceptable to defer" caveat was NOT exercised — the test exists and now runs the new assertion.

**Recommended PI (light)**: tasks.md template guidance for documentation-edit phases should explicitly call out "if the file under edit has a corresponding bats/unit test asserting current output, update the test in lockstep." It's load-bearing and easy to miss.

### #3 — `--since='YYYY-MM-DD'` literal trips ugrep's option parser when running the SC-005 sentinel locally

**What happened**: When I ran `grep -F "--since='YYYY-MM-DD'" plugin-kiln/templates/spec-template.md` to verify SC-005, the local `grep` (ugrep on this system) interpreted `--since='YYYY-MM-DD'` as an option flag and bailed with "invalid option --since=…". The auditor running SC-005 with strict GNU grep gets a different result.

**Resolution**: Insert `--` to terminate option parsing: `grep -F -- "--since='YYYY-MM-DD'" <file>`. Both ugrep and GNU grep accept this form.

**Recommended PI**: tasks.md T082 (and any future task that runs `grep -F` against a literal that begins with `--`) should explicitly include the `--` terminator in the command. The current T082 wording will fail on macOS systems where `grep` is ugrep-aliased.

### #4 — Two parallel implementers caused a flurry of "File has been modified since read" Edit errors on tasks.md

**What happened**: Both `impl-docs` and `impl-roadmap-and-merge` write to `specs/merge-pr-and-sc-grep-guidance/tasks.md` (each marking their own `[X]` boxes). The Edit tool's read-then-write contract forced me to re-read tasks.md between every successive `[X]` flip, and even then the file was being mutated by the other implementer between my read and my write.

**Resolution**: Smaller-scoped Edits (one task line at a time) succeeded after a fresh read each time. Total cost: ~3 Edit retries.

**Recommended PI**: tasks.md is a shared coordination surface, and per-implementer flips of `[X]` are exactly the contention pattern that breaks the read-before-write invariant. Two options:
- Per-implementer tasks.md (e.g., `tasks-roadmap-and-merge.md` + `tasks-docs.md` generated from a master `tasks.md`).
- Have implementers report `[X]` flips to team-lead via SendMessage; team-lead serializes the writes.

Either is plugin-agnostic. The current "everyone edits the same file" pattern works at small scale but the contention surface grows linearly with implementer count.

## Deviations from contract

None substantive. The README section in `contracts/interfaces.md` §F.1 said "AFTER the existing `## Workflow Format` block" — I placed it AFTER `## Step-internal command batching` (which itself follows Workflow Format and several Workflow-Format-related subsections). This is consistent with §F.1's "specifier did not enumerate every later heading" caveat and with plan §2's "placement near the end is acceptable." The new section sits immediately before `## Test Runner`, which gives it natural prominence and avoids interrupting Workflow Format's tight structure.

## Surprises

- **The version-bump hook auto-stages `VERSION` + every `package.json` on every Edit/Write.** This is FYI for auditors — when they see `M  plugin-clay/package.json` in `git status` between commits, that is the hook, not impl-docs. I did not commit those files; they remained staged across my entire session and presumably get rolled into another implementer's commit.
- **`git commit -- <pathspec>` requires the `-m`/message arg BEFORE the `--`.** I tripped on `git commit -- <files> -m "..."` initially — git treats `-m` after `--` as a pathspec, not a flag. Fixed by reordering.

## Status

All [B: docs] tasks T070–T100 marked `[X]` in tasks.md. Three commits landed (one — Phase 8 — was hijacked into specifier's correction commit per Friction #1, but the diff is byte-identical to my intended Phase 8 commit). All SC sentinels green. All 11 bats tests pass.

Ready for audit.
