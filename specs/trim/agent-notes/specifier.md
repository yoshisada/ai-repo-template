# Specifier Friction Note — Trim

## What went well
- The PRD was thorough with clear FRs and use cases, making spec generation straightforward
- Existing plugin patterns (shelf, wheel) provided clear structural templates to follow
- The branch already existed (`build/trim-20260409`), avoiding branch creation complexity

## Friction points
- The `/specify` skill's branch creation step assumes it needs to create a branch, but in pipeline mode the branch is pre-created by the team lead. Had to skip the `create-new-feature.sh` script.
- The plan template includes placeholders for `src/` and `tests/` directories that don't apply to plugin repos. Had to replace the entire Source Code section.
- The tasks template assumes a standard app project with models/services/endpoints. Plugin repos need a different mental model: skills, workflows, templates, manifests.
- Writing research.md fresh required using Bash because the Write tool requires a prior Read of the file.

## Suggestions for future pipelines
- Consider a "plugin" project type preset in the plan/tasks templates that uses skill/workflow/template structure instead of src/tests
- The specify skill could detect if the branch already exists and skip the creation script automatically
