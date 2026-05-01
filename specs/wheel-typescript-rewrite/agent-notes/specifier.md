# Agent Friction Notes: spec-enforcer

**Feature**: wheel-typescript-rewrite
**Date**: 2026-04-29

## What Was Confusing

- **Spec directory naming mismatch**: The team-lead message said `specs/002-wheel-ts-rewrite/` but the actual directory on disk (committed in prior session) was `specs/wheel-typescript-rewrite/`. The `/specify` skill resolved `specs/002-wheel-ts-rewrite/` via `check-prerequisites.sh`, but the Write tool wrote to the pre-existing `specs/wheel-typescript-rewrite/` path. The `git add` then failed with "No such file or directory" because I tried to add `specs/002-wheel-ts-rewrite/spec.md` instead of the correct path. Resolution: `git log --oneline main..HEAD` showed the correct commit, confirming the spec artifacts were already in the right place.

- **Phase 1.5 research-first agents**: The `/plan` skill has complex Phase 1.5 logic for `fixture_corpus: synthesized` / `empirical_quality[]` axes that spawn fixture-synthesizer and output-quality-judge agents. For this PRD (which has neither), the skip-path runs but the probe script path `$WORKFLOW_PLUGIN_DIR` was not available in my context. I fell back to a `grep -E` on the PRD which showed no matches — confirming skip-path. This was fine but the resolution was ad-hoc.

- **Shell shim vs native node question**: The PRD leaves open whether Claude Code natively invokes `node` binaries or requires shell. I flagged this as "Phase 1 fallback" in the plan but there was no way to test it during spec creation. It's marked T019/T020 in tasks, which is the right approach.

## Where I Got Stuck

- **git commit failure**: Trying to `git add specs/002-wheel-ts-rewrite/spec.md` failed because the files were at `specs/wheel-typescript-rewrite/`. The `check-prerequisites.sh` output with `FEATURE_DIR="/Users/.../specs/002-wheel-ts-rewrite"` was misleading — the scripts created a phantom directory path that didn't exist on disk. The actual files were in the pre-existing `specs/wheel-typescript-rewrite/` directory from an earlier session. The fix was to read `git log main..HEAD` to discover the correct commit and path.

- **WORKFLOW_PLUGIN_DIR not available**: The `/plan` skill Phase 1.5 instructions reference `$WORKFLOW_PLUGIN_DIR` but this env var is only set during wheel workflow execution. It was unavailable in my specifier context, so I had to find the probe script via `find /Users/ryansuematsu/.claude/plugins -name "probe-plan-time-agents.sh"` — which worked but was circuitous.

## What Could Be Improved

- **check-prerequisites.sh should resolve actual disk path**: The script outputs `FEATURE_DIR="/Users/.../specs/002-wheel-ts-rewrite"` but if that directory doesn't exist on disk, the Write tool creates files there. Meanwhile a pre-existing `specs/wheel-typescript-rewrite/` directory exists from a prior session. The script should check which path actually exists on disk before reporting `FEATURE_DIR`. Alternatively, the team-lead message should specify the exact spec directory path to avoid ambiguity.

- **FR numbering should be consistent across artifacts**: The spec has FR-001–FR-020. The contracts/interfaces.md has section numbers (§1–§18) but also references FRs like `FR-016`, `FR-G2-3`, etc. that don't map cleanly to the spec's FR numbers. During implementation, the implementer will need to cross-reference two numbering schemes. Consider either: (a) using the same FR numbers in contracts as in spec, or (b) noting in contracts that §-N numbers are the contract IDs and FRs from spec are the source.

- **Skeleton src/ stubs in contracts**: The plan references `src/shared/*.ts`, `src/lib/*.ts`, `src/hooks/*.ts` but doesn't create the stub directory structure. A minor improvement: the `/plan` skill could create stub empty files (or at least the directory skeleton) so that the tsconfig.json and package.json can reference real paths during implementation planning.
