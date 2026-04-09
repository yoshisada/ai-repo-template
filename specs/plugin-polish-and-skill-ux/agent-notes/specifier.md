# Specifier Agent Friction Notes

**Agent**: specifier
**Feature**: plugin-polish-and-skill-ux
**Date**: 2026-04-09

## What Was Confusing or Unclear

- The instruction said to use `/specify`, `/plan`, `/tasks` slash commands, but as a sub-agent I invoked these as skills. The skill system loaded full skill prompts that expected interactive user input and branch creation workflows. Since the branch and spec directory were already defined by the team lead, I had to work around the skill's branch creation steps (step 0/1/2 of specify) and directory conventions.

- The specify skill wanted to run `create-new-feature.sh` to create a new branch, but the branch already existed. I used `check-prerequisites.sh --json --paths-only` to confirm the right paths and skipped branch creation.

## Where I Got Stuck

- The plan template had placeholder sections (Option 1/2/3 for project structure) that don't apply to a plugin project — this is a collection of Markdown/Bash/JSON files, not a traditional src/ application. Had to remove all placeholder options and write the actual file layout.

- The `setup-plan.sh` script copies the plan template, but then I need to overwrite it entirely with the actual plan content. The template is more of a structural guide than a fillable form.

## What Could Be Improved

- For sub-agent specifiers that already have a branch and spec directory, the specify skill should have a "headless" mode that skips branch creation and directory setup.

- The plan template could benefit from a "plugin project" variant that doesn't include src/tests/backend/frontend structure options.

- Task instructions should clarify that US1/US2 in tasks.md map to the user stories in spec.md by number, not by FR number. The PRD has FR-001 through FR-012 but the spec groups them into 6 user stories.
