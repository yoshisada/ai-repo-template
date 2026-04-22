# QA Directory Structure

This directory contains all QA artifacts produced by kiln QA skills and agents.

## Subdirectories

| Directory | Purpose | File Types | Written By |
|-----------|---------|------------|------------|
| `tests/` | Playwright test stubs and E2E test scripts | `.spec.ts` | `/kiln:kiln-qa-setup`, QA engineer |
| `results/` | QA reports, pass reports, UX reports, test result JSON | `.md`, `.json` | `qa-reporter`, QA engineer |
| `screenshots/` | Screenshots captured during QA passes and UX evaluation | `.png` | `ux-evaluator`, QA engineer |
| `videos/` | Video recordings of test runs and user flow walkthroughs | `.webm` | QA engineer, Playwright |
| `config/` | Playwright config, test matrix, environment templates | `.ts`, `.md`, `.env.*` | `/kiln:kiln-qa-setup` |

## Notes

- `config/.env.test` is gitignored -- NEVER commit real credentials.
- Copy `config/.env.test.example` to `config/.env.test` and fill in values for authenticated test flows.
- Screenshots and videos are transient outputs; they are regenerated on each QA pass.
- Reports in `results/` are the primary QA deliverables attached to PRs.
