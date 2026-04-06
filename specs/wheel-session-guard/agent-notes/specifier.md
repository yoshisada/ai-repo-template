# Specifier Agent Notes: Wheel Session Guard

## What Went Well

- The PRD was exceptionally detailed — all 5 FRs had clear descriptions, ownership was unambiguous, and non-goals were explicit. This made the spec almost a direct translation.
- The existing wheel codebase has consistent patterns across all 6 hooks (same guard-init-handle structure), making the plan straightforward.
- No clarifications needed — the PRD answered every question before it could be asked.

## Friction Points

1. **Branch already existed**: The feature branch `build/wheel-session-guard-20260405` was pre-created by the team lead, but the spec directory didn't exist. The `/specify` skill's create-new-feature.sh script expects to create the branch itself. I had to skip the branch creation step and create the spec directory manually. The skill should handle the case where the branch exists but the spec directory doesn't.

2. **Spec template references `src/` and `tests/`**: The spec template and task template assume a standard application structure with `src/` and `tests/` directories. This plugin repo has `plugin-wheel/lib/` and `plugin-wheel/hooks/` instead. The templates should be more neutral about directory structure or offer plugin-specific variants.

3. **Test coverage gate N/A**: The constitution mandates 80% test coverage, but there's no test framework for shell hook scripts. The spec had to mark this as N/A. A clearer constitution exemption for shell-only plugin repos would reduce friction.

4. **User stories vs. implementation reality**: The task template wants each user story to have its own implementation tasks, but in this feature, most user stories are satisfied by the same foundational work (guard.sh + hook integration). US2, US3, US4 ended up with "no additional tasks needed" phases. The template should better handle features where stories are orthogonal views of the same implementation.

## Suggestions for Improvement

- Add a `/specify --existing-branch` flag that skips branch creation when the branch already exists
- Consider a "plugin" or "shell" project type in the spec templates that adjusts terminology and expectations
- Allow the constitution to declare per-project-type exemptions for test coverage
