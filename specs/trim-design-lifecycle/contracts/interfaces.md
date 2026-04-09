# Interface Contracts: Trim Design Lifecycle

**Date**: 2026-04-09
**Spec**: [spec.md](../spec.md)

## Skills (User-Invocable Commands)

### /trim-edit

| Property | Value |
|----------|-------|
| **Skill file** | `plugin-trim/skills/trim-edit/SKILL.md` |
| **Input** | `$ARGUMENTS` — natural language edit description (required, non-empty) |
| **Delegates to** | `trim-edit` wheel workflow via `/wheel-run trim:trim-edit` |
| **Output** | Updated Penpot design + new entry in `.trim-changes.md` |
| **Side effects** | Modifies Penpot design via MCP. Does NOT modify code files. |
| **FR coverage** | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006 |

### /trim-verify

| Property | Value |
|----------|-------|
| **Skill file** | `plugin-trim/skills/trim-verify/SKILL.md` |
| **Input** | `$ARGUMENTS` — optional: specific flow name to verify (defaults to all flows) |
| **Delegates to** | `trim-verify` wheel workflow via `/wheel-run trim:trim-verify` |
| **Precondition** | `.trim-flows.json` must exist with at least one flow |
| **Output** | `.trim-verify-report.md` + screenshots in `.trim-verify/` |
| **Side effects** | Reads Penpot frames via MCP. Launches headless browser. Does NOT modify code or Penpot. |
| **FR coverage** | FR-007, FR-008, FR-009, FR-010, FR-011, FR-012 |

### /trim-redesign

| Property | Value |
|----------|-------|
| **Skill file** | `plugin-trim/skills/trim-redesign/SKILL.md` |
| **Input** | `$ARGUMENTS` — optional context/direction (e.g., "dark theme", "modernize") |
| **Delegates to** | `trim-redesign` wheel workflow via `/wheel-run trim:trim-redesign` |
| **Output** | New Penpot design + comprehensive entry in `.trim-changes.md` |
| **Side effects** | Modifies Penpot design via MCP. Does NOT modify code files. |
| **FR coverage** | FR-013, FR-014, FR-015, FR-016, FR-017 |

### /trim-flows

| Property | Value |
|----------|-------|
| **Skill file** | `plugin-trim/skills/trim-flows/SKILL.md` |
| **Input** | `$ARGUMENTS` — subcommand: `add <name>`, `list`, `sync`, `export-tests` |
| **Delegates to** | Inline (no workflow) |
| **Output** | Varies by subcommand (see below) |
| **FR coverage** | FR-018, FR-019, FR-020, FR-021, FR-022, FR-023, FR-024 |

#### /trim-flows Subcommands

| Subcommand | Input | Output | Side Effects |
|------------|-------|--------|-------------|
| `add <name>` | Flow name + interactive step descriptions | Updated `.trim-flows.json` | Creates file if not exists |
| `list` | None | Formatted table to stdout | None (read-only) |
| `sync` | None | Updated `.trim-flows.json` with Penpot frame IDs | Reads Penpot via MCP |
| `export-tests` | None | Playwright test files in project test directory | Creates test files |

## Wheel Workflows

### trim-edit.json

| Property | Value |
|----------|-------|
| **File** | `plugin-trim/workflows/trim-edit.json` |
| **name** | `trim-edit` |
| **version** | `1.0.0` |
| **FR coverage** | FR-001 through FR-006, FR-025 through FR-027 |

**Steps**:

| Step ID | Type | Description | Output |
|---------|------|-------------|--------|
| `resolve-trim-plugin` | command | Scan `installed_plugins.json` for trim path, fall back to `plugin-trim/` | `.wheel/outputs/resolve-trim-plugin.txt` |
| `read-design-state` | command | Read `.trim-components.json` and `.trim-config` | `.wheel/outputs/read-design-state.txt` |
| `apply-edit` | agent | Interpret natural language description, read current Penpot design via MCP, apply targeted changes | `.wheel/outputs/apply-edit.txt` |
| `log-change` | agent | Append entry to `.trim-changes.md` with timestamp, request, actual changes, affected frames | `.wheel/outputs/log-change.txt` |

**Context flow**: `resolve-trim-plugin` → `read-design-state` → `apply-edit` (context_from: resolve-trim-plugin, read-design-state) → `log-change` (context_from: read-design-state, apply-edit)

### trim-verify.json

| Property | Value |
|----------|-------|
| **File** | `plugin-trim/workflows/trim-verify.json` |
| **name** | `trim-verify` |
| **version** | `1.0.0` |
| **FR coverage** | FR-007 through FR-012, FR-025 through FR-027 |

**Steps**:

| Step ID | Type | Description | Output |
|---------|------|-------------|--------|
| `resolve-trim-plugin` | command | Scan `installed_plugins.json` for trim path | `.wheel/outputs/resolve-trim-plugin.txt` |
| `read-flows` | command | Read `.trim-flows.json` and validate structure | `.wheel/outputs/read-flows.txt` |
| `capture-screenshots` | agent | Walk each flow step in headless Playwright (or /chrome), screenshot each step, fetch Penpot frames via MCP | `.wheel/outputs/capture-screenshots.txt` |
| `compare-visuals` | agent | Compare each screenshot against Penpot frame using Claude vision; identify layout, color, typography, spacing mismatches | `.wheel/outputs/compare-visuals.txt` |
| `write-report` | agent | Generate `.trim-verify-report.md` and update `last_verified` in `.trim-flows.json` | `.wheel/outputs/write-report.txt` |

**Context flow**: `resolve-trim-plugin` → `read-flows` → `capture-screenshots` (context_from: resolve-trim-plugin, read-flows) → `compare-visuals` (context_from: capture-screenshots) → `write-report` (context_from: read-flows, compare-visuals)

### trim-redesign.json

| Property | Value |
|----------|-------|
| **File** | `plugin-trim/workflows/trim-redesign.json` |
| **name** | `trim-redesign` |
| **version** | `1.0.0` |
| **FR coverage** | FR-013 through FR-017, FR-025 through FR-027 |

**Steps**:

| Step ID | Type | Description | Output |
|---------|------|-------------|--------|
| `resolve-trim-plugin` | command | Scan `installed_plugins.json` for trim path | `.wheel/outputs/resolve-trim-plugin.txt` |
| `gather-context` | command | Read PRD, `.trim-components.json`, `.trim-flows.json`, `.trim-config` | `.wheel/outputs/gather-context.txt` |
| `read-current-design` | agent | Fetch entire current Penpot design state via MCP (pages, components, styles) | `.wheel/outputs/read-current-design.txt` |
| `generate-redesign` | agent | Reimagine visual design preserving IA (pages, nav, flows), apply to Penpot via MCP | `.wheel/outputs/generate-redesign.txt` |
| `log-changes` | agent | Append comprehensive redesign entry to `.trim-changes.md` with rationale | `.wheel/outputs/log-changes.txt` |

**Context flow**: `resolve-trim-plugin` → `gather-context` → `read-current-design` (context_from: resolve-trim-plugin, gather-context) → `generate-redesign` (context_from: gather-context, read-current-design) → `log-changes` (context_from: gather-context, generate-redesign)

## File Schemas

### .trim-changes.md

Append-only markdown file. Each entry is a level-2 heading with structured content. See data-model.md for field definitions.

```markdown
# Design Changelog

## [ISO-8601-TIMESTAMP] TYPE

**Request**: [natural language description]

**Changes**:
- [change 1]
- [change 2]

**Affected Frames**: [frame1], [frame2]

**Rationale**: [for redesign only — why this approach]

---
```

### .trim-flows.json

JSON array. See data-model.md for full schema.

```json
[
  {
    "name": "string",
    "description": "string",
    "steps": [
      {
        "action": "navigate|click|fill|select|scroll|wait",
        "target": "string (selector, component, or URL)",
        "page": "string (route)",
        "component": "string|null",
        "penpot_frame_id": "string|null"
      }
    ],
    "last_verified": "ISO-8601|null"
  }
]
```

### .trim-verify-report.md

Generated markdown report. See data-model.md for field definitions.

```markdown
# Visual Verification Report

**Date**: [ISO-8601]
**Flows verified**: [count]
**Pass**: [count] | **Fail**: [count]

## Flow: [name]

### Step 1: [action] [target]
- **Result**: pass|fail
- **Screenshot**: .trim-verify/[flow]-step-[N].png
- **Penpot Frame**: [frame_id]
- **Mismatch**: [description or "none"]

---
```

## Plugin Manifest Updates

### plugin-trim/.claude-plugin/plugin.json

Add 4 new skills to the manifest's skills array:

```json
{
  "name": "trim-edit",
  "description": "Edit Penpot designs via natural language. Changes are logged and stay in Penpot until pulled.",
  "path": "skills/trim-edit"
},
{
  "name": "trim-verify",
  "description": "Visually verify rendered code matches Penpot designs. Walks user flows, screenshots each step, compares via Claude vision.",
  "path": "skills/trim-verify"
},
{
  "name": "trim-redesign",
  "description": "Full UI redesign in Penpot. Reimagines visual design while preserving information architecture and user flows.",
  "path": "skills/trim-redesign"
},
{
  "name": "trim-flows",
  "description": "Manage user flows for verification and QA. Subcommands: add, list, sync, export-tests.",
  "path": "skills/trim-flows"
}
```

### plugin-trim/package.json

Bump version to reflect new skills added.
