# Data Model: Trim Design Lifecycle

**Date**: 2026-04-09

## Entities

### Design Change Entry (`.trim-changes.md`)

Append-only changelog in markdown format. Each entry is a section:

| Field | Type | Description |
|-------|------|-------------|
| timestamp | ISO 8601 datetime | When the change was made |
| type | string | `edit`, `redesign` |
| request | string | What the developer asked for (natural language) |
| changes | list of strings | What was actually modified (components, properties) |
| affected_frames | list of strings | Penpot frame names/IDs that were changed |
| rationale | string | Why this change was made (for redesign entries) |

**Format in .trim-changes.md**:
```markdown
## [2026-04-09T14:30:00Z] edit

**Request**: Make the sidebar narrower and change the accent color to blue

**Changes**:
- Sidebar width: 280px → 220px
- Accent color: #FF6B35 → #2563EB (all components using accent token)

**Affected Frames**: main-layout, sidebar-nav, dashboard

---
```

### User Flow (`.trim-flows.json`)

JSON array of flow objects:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | yes | Flow identifier (e.g., "login", "checkout") |
| description | string | yes | Human-readable description of the flow |
| steps | array of FlowStep | yes | Ordered sequence of interactions |
| last_verified | ISO 8601 or null | yes | Timestamp of last verification run |

### Flow Step

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| action | string | yes | Interaction type: "navigate", "click", "fill", "select", "scroll", "wait" |
| target | string | yes | CSS selector, component name, or URL path |
| page | string | yes | Route/URL for this step |
| component | string | no | Component name involved (for mapping) |
| penpot_frame_id | string | no | Penpot frame ID for visual comparison (null until synced) |

**Example `.trim-flows.json**:
```json
[
  {
    "name": "login",
    "description": "User logs into the application",
    "steps": [
      { "action": "navigate", "target": "/login", "page": "/login", "component": "LoginPage", "penpot_frame_id": "frame-abc123" },
      { "action": "fill", "target": "#email", "page": "/login", "component": "LoginForm", "penpot_frame_id": "frame-abc123" },
      { "action": "fill", "target": "#password", "page": "/login", "component": "LoginForm", "penpot_frame_id": "frame-abc123" },
      { "action": "click", "target": "#submit", "page": "/login", "component": "LoginForm", "penpot_frame_id": "frame-abc123" },
      { "action": "navigate", "target": "/dashboard", "page": "/dashboard", "component": "DashboardPage", "penpot_frame_id": "frame-def456" }
    ],
    "last_verified": null
  }
]
```

### Verification Report (`.trim-verify-report.md`)

Generated markdown report, one section per flow, one subsection per step:

| Field | Type | Description |
|-------|------|-------------|
| flow_name | string | Name of the flow being verified |
| step_index | number | Step position in the flow |
| step_action | string | What was done (e.g., "navigate to /login") |
| result | "pass" or "fail" | Whether the step matched the design |
| mismatch_description | string or null | What was different (if fail) |
| screenshot_path | string | Path to captured screenshot in `.trim-verify/` |
| penpot_frame_ref | string | Penpot frame ID used for comparison |

## Relationships

- A **User Flow** contains 1..N **Flow Steps**
- A **Flow Step** references a **Penpot frame** (optional, populated by `/trim-flows sync`)
- A **Verification Report** references **User Flows** and their **Flow Steps**
- A **Design Change Entry** references **Penpot frames** that were modified
- `/trim-verify` reads **User Flows** to know what to verify
- `/trim-edit` and `/trim-redesign` write **Design Change Entries**
- `/trim-flows export-tests` reads **User Flows** to generate test stubs
