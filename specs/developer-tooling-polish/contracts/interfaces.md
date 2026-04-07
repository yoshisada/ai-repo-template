# Interface Contracts: Developer Tooling Polish

**Date**: 2026-04-07  
**Spec**: [spec.md](../spec.md)  
**Plan**: [plan.md](../plan.md)

These are Claude Code plugin skills — Markdown files with embedded Bash. The "interfaces" are the skill definitions (frontmatter + step structure) and their observable outputs.

## Skill 1: `/wheel-list`

**File**: `plugin-wheel/skills/wheel-list/SKILL.md`

### Frontmatter

```yaml
name: wheel-list
description: List all available wheel workflows. Scans workflows/ directory and displays names, step counts, step types, validation status, grouped by directory.
```

### Steps (embedded Bash blocks)

| Step | FR | Input | Output | Behavior |
|------|----|-------|--------|----------|
| Step 1: Scan | FR-001 | `workflows/` directory at repo root | Array of `.json` file paths | Recursively find all `.json` files in `workflows/`. If none found, display empty-state message (FR-005) and stop. |
| Step 2: Parse & Validate | FR-002, FR-004 | Each workflow `.json` file | Per-workflow metadata: name, step_count, step_types[], has_composition, validation_status | Parse JSON with `jq`. Extract name, count steps, collect unique step types, check for `workflow` type steps. On parse failure, set validation_status to error message. |
| Step 3: Group & Display | FR-003 | Parsed workflow metadata | Formatted grouped output | Group workflows by parent directory. Display as formatted sections with columns: Name, Steps, Types, Composition, Status. |
| Empty State | FR-005 | No `.json` files found | Helpful message | Display: "No workflows found. Run `/wheel-create` to create your first workflow." |

### Output Format

```text
## workflows/

| Workflow | Steps | Types | Composition | Status |
|----------|-------|-------|-------------|--------|
| my-flow  | 5     | command, agent | No | Valid |
| broken   | -     | -     | -           | ERROR: invalid JSON |

## workflows/tests/

| Workflow | Steps | Types | Composition | Status |
|----------|-------|-------|-------------|--------|
| test-ci  | 3     | command | No | Valid |
```

## Skill 2: `/qa-audit`

**File**: `plugin-kiln/skills/qa-audit/SKILL.md`

### Frontmatter

```yaml
name: qa-audit
description: Audit test files for duplicate scenarios and redundant assertions. Outputs a prioritized report to .kiln/qa/test-audit-report.md.
```

### Steps (embedded Bash blocks)

| Step | FR | Input | Output | Behavior |
|------|----|-------|--------|----------|
| Step 1: Discover | FR-006 | Project directory | Array of test file paths | Find files matching `*.test.*`, `*.spec.*`, `tests/**`, `__tests__/**`, `e2e/**`. Exclude `node_modules/`. If none found, display message and stop. |
| Step 2: Extract | FR-007, FR-008 | Test file contents | Per-file: test names, descriptions, selectors, URLs, assertions | Read each file, extract `test()`/`it()`/`describe()` blocks with descriptions. Collect selector patterns, URL patterns, assertion targets. |
| Step 3: Analyze | FR-007, FR-008 | Extracted test metadata | Overlap findings | Compare test descriptions for similarity. Compare selector/URL/assertion patterns across files. Flag pairs with high overlap. |
| Step 4: Report | FR-009, FR-010 | Analysis findings | Markdown report at `.kiln/qa/test-audit-report.md` | Create `.kiln/qa/` if needed. Write prioritized report with: summary stats, duplicate scenario pairs, redundant assertion groups, consolidation suggestions. |
| Step 5: Pipeline Integration | FR-011 | Optional pipeline context | Findings routed to implementer | When invoked during pipeline, flag critical overlaps to implementer agent before test execution. |

### Report Format (`.kiln/qa/test-audit-report.md`)

```markdown
# QA Test Audit Report

**Date**: YYYY-MM-DD
**Files scanned**: N
**Total tests**: N
**Findings**: N overlaps, N redundant assertions

## Summary

- X duplicate scenario pairs found
- Y redundant assertion groups found
- Estimated redundancy: Z%

## Duplicate Scenarios (Priority: High)

### Finding 1
- **Test A**: `path/to/file.test.ts` — "should handle user login"
- **Test B**: `path/to/other.test.ts` — "should log in user"
- **Overlap**: Both test the same login flow with identical steps
- **Suggestion**: Consolidate into a single test in `path/to/file.test.ts`

## Redundant Assertions (Priority: Medium)

### Finding 1
- **Files**: `file1.test.ts:42`, `file2.test.ts:87`
- **Assertion**: Both check `page.locator('.nav').isVisible()`
- **Suggestion**: Extract to shared helper or remove from one test

## Recommendations

1. [Prioritized action items]
```

## Cross-Skill Dependencies

None. The two skills are fully independent — they live in different plugins and share no code or state.
