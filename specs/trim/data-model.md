# Data Model: Trim Plugin

## Entities

### Trim Config (`.trim-config`)

Plain-text key-value file at repo root. One key per line, `key = value` format.

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `penpot_project_id` | string | yes | Penpot project UUID |
| `penpot_file_id` | string | yes | Penpot file UUID |
| `default_page` | string | no | Default Penpot page name to sync (if omitted, syncs all pages) |
| `components_file` | string | no | Path to component mapping file (default: `.trim-components.json`) |
| `framework` | string | no | Override auto-detected framework (react, vue, svelte, html) |

**Example**:
```
# Trim configuration — maps this repo to its Penpot project
penpot_project_id = abc123-def456
penpot_file_id = 789ghi-012jkl
default_page = main
components_file = .trim-components.json
```

### Component Mapping (`.trim-components.json`)

JSON array at repo root. Each entry tracks a bidirectional link between a code component and a Penpot component.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code_path` | string | yes | Relative path to the code component file |
| `component_name` | string | yes | Human-readable component name |
| `penpot_component_id` | string | yes | Penpot component UUID |
| `penpot_component_name` | string | yes | Name in Penpot |
| `last_synced` | string (ISO 8601) | yes | Timestamp of last successful sync |
| `sync_direction` | string | yes | Last sync direction: `pull`, `push`, or `initial` |

**Example**:
```json
[
  {
    "code_path": "src/components/Button.tsx",
    "component_name": "Button",
    "penpot_component_id": "comp-uuid-123",
    "penpot_component_name": "Button",
    "last_synced": "2026-04-09T12:00:00Z",
    "sync_direction": "pull"
  }
]
```

### Drift Report (output of `/trim-diff`)

Written to `.wheel/outputs/trim-diff-report.md`. Categorized list of mismatches.

| Category | Description |
|----------|-------------|
| `code-only` | Component exists in code but not in Penpot |
| `design-only` | Component exists in Penpot but not in code |
| `style-divergence` | Component exists in both but visual properties differ |
| `layout-difference` | Component exists in both but layout/structure differs |
| `deleted` | Component tracked in mapping but deleted from one side |

Each entry includes: component name, category, details (what differs), and suggestion (pull, push, or manual review).

### Workflow Step Outputs

All wheel workflow steps write their outputs to `.wheel/outputs/` using descriptive filenames prefixed with `trim-`:

| Output File | Source Step | Contents |
|-------------|-----------|----------|
| `trim-read-config.txt` | read-config | Parsed .trim-config values |
| `trim-detect-framework.txt` | detect-framework | Detected framework, CSS approach, conventions |
| `trim-scan-components.txt` | scan-components | List of code components with paths and properties |
| `trim-read-mappings.txt` | read-mappings | Current .trim-components.json contents |
| `trim-diff-report.md` | diff-report | Categorized drift report |

## Relationships

```
.trim-config
    ├── references → Penpot project (by ID)
    └── references → .trim-components.json (by path)

.trim-components.json
    ├── maps → code files (by code_path)
    └── maps → Penpot components (by penpot_component_id)

Wheel Workflows
    ├── read → .trim-config
    ├── read/write → .trim-components.json
    ├── read/write → Penpot (via MCP)
    └── write → .wheel/outputs/trim-*
```

## State Transitions

### Component Sync Status

```
unlinked → linked (after first pull or push)
linked/in-sync → drifted (when code or Penpot changes after last_synced)
drifted → in-sync (after successful sync via pull, push, or library sync)
linked → deleted (when component removed from code or Penpot)
```
