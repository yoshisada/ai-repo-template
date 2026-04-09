# Data Model: Trim Penpot Layout & Auto-Flows

**Date**: 2026-04-09

## Entities

### Flow Entry (in `.trim/flows.json`)

Existing schema extended with `source` field:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | yes | Flow name (unique identifier) |
| description | string | yes | Human-readable description |
| source | string | yes | `"auto-discovered"` or `"manual"` |
| steps | array | yes | Ordered list of flow steps |
| last_verified | string/null | no | ISO 8601 timestamp of last verification |

### Flow Step (within a flow entry)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| action | string | yes | One of: navigate, click, fill, select, scroll, wait |
| target | string | yes | CSS selector, component name, or URL path |
| page | string | yes | Route/URL for this step |
| component | string/null | no | Component name involved |
| penpot_frame_id | string/null | no | Mapped Penpot frame reference |

### Component Group (conceptual, within agent instructions)

Not persisted as a separate data structure. Derived at runtime by the agent from:
- Directory structure of scanned components
- Component naming patterns
- Penpot component group metadata

### Penpot Page Mapping (conceptual, within agent instructions)

Not persisted as a separate data structure. The agent determines page-to-Penpot-page mapping at runtime from:
- Application route/page scan results
- Existing Penpot pages in the file

## State Transitions

### Flow Entry Lifecycle

```
(does not exist) → auto-discovered → verified → auto-discovered (re-scan updates)
(does not exist) → manual (via /trim-flows add) → verified → manual (never overwritten)
```

### Components Page Lifecycle

```
(does not exist) → created by first push/design → updated by subsequent push/design
```

Components are appended to existing groups; existing positions are preserved.
