# Interface Contracts: Kiln Polish

## 1. `/next` Skill Output Contract (FR-001, FR-002, FR-003)

### Suggested Next Section

After the existing Step 5 output (priority-grouped recommendations) and before the report footer, the `/next` skill MUST append:

```markdown
---

> **Suggested next**: `/command` — reason
```

When no actionable recommendations exist:

```markdown
---

> **Suggested next**: Nothing urgent — check the backlog with `/issue-to-prd`
```

### Rules

- The `---` horizontal rule visually separates the suggestion from the recommendations list
- The suggestion is rendered as a blockquote (`>`) for visual prominence
- The command is the first item from the priority-sorted recommendation list (Step 4)
- The reason is the description from that same recommendation item
- In `--brief` mode, the "Suggested next" line STILL appears (it is never suppressed)
- The suggestion appears in both terminal output AND the persistent report file

## 2. QA Directory Structure Contract (FR-004, FR-005, FR-007)

### Canonical Directory List

The following directories MUST be created by both `/qa-setup` and `init.mjs`:

```
.kiln/qa/tests/
.kiln/qa/results/
.kiln/qa/screenshots/
.kiln/qa/videos/
.kiln/qa/config/
```

### mkdir Command

Both `/qa-setup` SKILL.md and `init.mjs` MUST use:

```bash
mkdir -p .kiln/qa/tests .kiln/qa/results .kiln/qa/screenshots .kiln/qa/videos .kiln/qa/config
```

### init.mjs Function Signature

```javascript
// Inside scaffoldProject(), after existing .kiln directory creation:
// Add QA subdirectories to the kilnDirs array:
const kilnDirs = [
  ".kiln/workflows",
  ".kiln/agents",
  ".kiln/issues",
  ".kiln/qa",
  ".kiln/qa/tests",
  ".kiln/qa/results",
  ".kiln/qa/screenshots",
  ".kiln/qa/videos",
  ".kiln/qa/config",
  ".kiln/logs"
];
```

No new functions are exported. The change is internal to the `scaffoldProject()` function.

### qa-readme.md Scaffold Template

A new file at `plugin/scaffold/qa-readme.md` is copied to `.kiln/qa/README.md` during init.
`copyIfMissing()` is used (never overwrites existing README).

## 3. QA Agent Output Path Contract (FR-006)

### Path Mapping

| Artifact Type | Old Path | New Canonical Path |
|---------------|----------|-------------------|
| QA reports | `.kiln/qa/QA-REPORT.md` | `.kiln/qa/results/QA-REPORT.md` |
| QA pass reports | `.kiln/qa/latest/QA-PASS-REPORT.md` | `.kiln/qa/results/QA-PASS-REPORT.md` |
| UX reports | `.kiln/qa/latest/UX-REPORT.md` | `.kiln/qa/results/UX-REPORT.md` |
| Test results JSON | `.kiln/qa/test-results.json` | `.kiln/qa/results/test-results.json` |
| Screenshots | `.kiln/qa/latest/screenshots/` | `.kiln/qa/screenshots/` |
| Reference screenshots | `.kiln/qa/latest/screenshots/reference/` | `.kiln/qa/screenshots/reference/` |
| Desktop screenshots | `.kiln/qa/latest/screenshots/desktop/` | `.kiln/qa/screenshots/desktop/` |
| Videos | `.kiln/qa/videos/` | `.kiln/qa/videos/` (unchanged) |
| Playwright config | `.kiln/qa/playwright.config.ts` | `.kiln/qa/config/playwright.config.ts` |
| Test matrix | `.kiln/qa/test-matrix.md` | `.kiln/qa/config/test-matrix.md` |
| Env template | `.kiln/qa/.env.test.example` | `.kiln/qa/config/.env.test.example` |
| Env credentials | `.kiln/qa/.env.test` | `.kiln/qa/config/.env.test` |
| Test stubs | `.kiln/qa/tests/` | `.kiln/qa/tests/` (unchanged) |

### Files That Must Be Updated

| File | What Changes |
|------|-------------|
| `plugin/skills/next/SKILL.md` | Add "Suggested next" section (FR-001/002/003) |
| `plugin/skills/qa-setup/SKILL.md` | Update mkdir and output paths to canonical structure |
| `plugin/agents/qa-reporter.md` | Update report output paths |
| `plugin/agents/ux-evaluator.md` | Update screenshot paths |
| `plugin/agents/qa-engineer.md` | Update screenshot/video paths (if present) |
| `plugin/skills/next/SKILL.md` | Update QA report paths in Step 2 (where it reads reports) |
| `plugin/templates/kiln-manifest.json` | Add QA subdirectory entries |
| `plugin/bin/init.mjs` | Add QA subdirectories + README copy |
| `plugin/scaffold/qa-readme.md` | New file — README template |
| `plugin/scaffold/gitignore` | Update gitignore paths for new canonical locations |

## 4. `.kiln/qa/README.md` Content Contract (FR-008)

The README MUST document:
- Each subdirectory's name and purpose
- What file types are expected in each directory
- Which kiln skills/agents write to each directory
- A note about `.env.test` being gitignored
