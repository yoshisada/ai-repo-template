---
name: "kiln-coverage"
description: "Check test coverage against the 80% constitutional gate"
---

## Coverage Gate Check

Verify that the codebase meets the 80% test coverage requirement from the constitution.

### Workflow

1. Check if a coverage tool is installed (e.g., `@vitest/coverage-v8`, `c8`, `istanbul`).
2. If not installed, install `@vitest/coverage-v8` as a devDependency.
3. Run the test suite with coverage: `npx vitest run --coverage`.
4. Parse the coverage report.
5. For each source file changed in the current branch (vs main):
   - Check line coverage >= 80%
   - Check branch coverage >= 80%
6. Report results per file and overall.

### Output

Produce a report with:
- Overall line coverage percentage
- Overall branch coverage percentage
- Per-file breakdown for changed files
- PASS if both >= 80%, FAIL otherwise
- List of files below threshold with specific uncovered lines

### Rules

- Only measure coverage on new/changed code (not the entire codebase)
- Use `git diff main...HEAD --name-only` to find changed files
- If no tests exist for a changed file, report it as 0% coverage
- Constitution rule II is NON-NEGOTIABLE — do not approve partial coverage
