# Agent Friction Notes: impl-kiln

## What was confusing or unclear

- The contracts and tasks reference `plugin-kiln/skills/todo/prompt.md` as the file to create, but every existing skill in the repo uses `SKILL.md` (not `prompt.md`). I followed the existing convention (`SKILL.md`) rather than the contract filename. The contract should have matched the repo convention.

## Where I got stuck

- No blockers. The tasks were well-scoped and the contracts were clear on what each file needed.
- The tasks.md file was being modified concurrently by impl-wheel, which caused one stale-file error when marking T011. Re-reading the file resolved it immediately.

## What could be improved

- Contracts should reference actual filenames used in the project (`SKILL.md` not `prompt.md`) to avoid ambiguity.
- The UX evaluator had 3 separate path references to update — the contract only called out 2 (Input section + Step 3a). Step 3c also references `.kiln/qa/screenshots/desktop/` which I updated for consistency. A more thorough audit of path references in the contract would help.
