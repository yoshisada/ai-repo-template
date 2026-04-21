---
name: trim-diff
description: Compare Penpot designs against code and report drift. Categorizes mismatches as code-only, design-only, style-divergence, or layout-difference with actionable suggestions.
---

# diff — Detect Design-Code Drift

Compare the current state of Penpot designs against the current code and produce a categorized drift report. Each mismatch includes an actionable suggestion (pull, push, or manual review). Runs as a wheel workflow.

## User Input

```text
$ARGUMENTS
```

Optional: component name to diff. If omitted, checks all tracked components in `.trim/components.json`.

## Steps

### 1. Validate Configuration

```bash
if [ ! -f .trim/config ]; then
  echo "ERROR: No .trim/config found. Run /trim:trim-init first to connect to your Penpot project."
  exit 1
fi
```

### 2. Run Workflow

Delegate to the diff wheel workflow:

```
/wheel:run trim:trim-diff
```

The workflow executes these steps in order:
1. **read-config** — parses `.trim/config` and validates required fields
2. **read-mappings** — reads current `.trim/components.json`
3. **scan-components** — finds current code component files by framework convention
4. **resolve-trim-plugin** — resolves trim plugin install path at runtime
5. **generate-diff** — compares Penpot state vs code for each tracked component, categorizes mismatches, generates report

### 3. Report Results

After the workflow completes, read `.wheel/outputs/diff-report.md` and display the drift report:

```
Drift Report for {project}

  Components Checked: {N}

  In Sync:          {N}
  Code-only:        {N} — run /trim:trim-push to create in Penpot
  Design-only:      {N} — run /trim:trim-pull to generate code
  Style Divergence:  {N} — pull or push to resolve
  Layout Difference: {N} — manual review recommended

  Full report: .wheel/outputs/diff-report.md
```

## Rules

- **Config required** — fail immediately if `.trim/config` is missing (FR-026)
- **Categorized mismatches** — every mismatch must be one of: code-only, design-only, style-divergence, layout-difference (FR-018)
- **Actionable suggestions** — every mismatch must include a pull/push/manual-review suggestion (FR-019)
- **MCP only** — all Penpot reads go through MCP tools (NFR-003)
