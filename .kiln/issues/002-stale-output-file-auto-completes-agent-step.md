# Issue 002: Stale output files auto-complete agent steps

## Summary
`dispatch_agent` marks an agent step done if the step's declared `output` file
exists on disk — but it doesn't verify the file was written during the current
run. If a previous workflow run left the file behind (committed to the repo,
or left in `reports/`), the next run will "succeed" without the agent ever
doing anything.

## Reproduction
1. Run `/wheel:wheel-run tests/command-chain` — summarize agent step writes
   `reports/file-census.md`. Workflow archives.
2. Run `/wheel:wheel-run tests/command-chain` again (without deleting the file).
3. Observed: workflow archives immediately via `handle_terminal_step` without
   the agent writing a new file. The stale file from run 1 satisfies the
   `-f "$output_key"` check in `dispatch_agent` `stop` handler (working branch).

## Impact
- Tests that share output file paths (`reports/file-census.md`,
  `reports/parent-final.md`, etc.) produce false passes.
- The repo has committed stale outputs in `reports/` from prior runs.
- CI or repeated test runs can hide regressions.

## Fix
1. **Code**: When an agent step transitions `pending → working`, delete the
   step's declared `output` file (if any). Only a fresh write by the current
   agent can then re-create it. Applied in `dispatch_agent stop` handler's
   pending branch and in any kickstart path that sets the step to working.
2. **Repo hygiene**: Move committed outputs out of the repo or add them to
   `.gitignore`. `reports/` should not track workflow outputs.

## Status
Fixing in this session.
