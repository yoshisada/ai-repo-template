# Interface Contracts: wheel-view API

## API Endpoints

### GET /api/health
**Response** `200 OK`:
```json
{ "status": "ok", "version": "0.1.0" }
```

### GET /api/projects
**Response** `200 OK`:
```json
[{ "id": "uuid", "path": "/repo/root", "addedAt": "2026-04-27T00:00:00Z" }]
```

### POST /api/projects
**Request body**:
```json
{ "path": "/repo/root" }
```

**Response** `201 Created` (new) or `200 OK` (already registered):
```json
{ "id": "uuid", "path": "/repo/root", "addedAt": "2026-04-27T00:00:00Z" }
```

**Errors**: `400 Bad Request` — missing `path` field.

### DELETE /api/projects/:id
**Response** `204 No Content`

**Errors**: `404 Not Found` — unknown project ID.

### GET /api/workflows?projectId=<id>
**Query params**:
- `projectId` (optional) — UUID of project. Defaults to first registered project.

**Response** `200 OK`:
```json
{
  "local": [
    {
      "name": "workflow-name",
      "description": "What it does",
      "path": "/repo/root/workflows/workflow-name.json",
      "source": "local",
      "stepCount": 3,
      "steps": [{ "id": "step-id", "type": "command", "command": "echo hi" }],
      "localOverride": false
    }
  ],
  "plugin": [
    {
      "name": "kiln-mistake",
      "description": "",
      "path": "/path/to/kiln/workflows/kiln-mistake.json",
      "source": "plugin",
      "plugin": "kiln",
      "stepCount": 5,
      "steps": [...],
      "localOverride": false
    }
  ]
}
```

**Errors**: `404 Not Found` — unknown projectId.

### GET /api/workflows/:name?projectId=<id>
**Path params**: `name` — workflow name (without `.json`)

**Query params**: `projectId` (optional)

**Response** `200 OK`: full `Workflow` object

**Errors**: `404 Not Found` — unknown workflow name or projectId.

### GET /api/feedback-loops?projectId=<id>
**Query params**: `projectId` (optional)

**Response** `200 OK`:
```json
{
  "kilnInstalled": true,
  "loops": [
    {
      "name": "retro-to-pi",
      "_meta": {
        "kind": "feedback",
        "status": "active",
        "owner": "yoshisada",
        "triggers": ["/kiln:kiln-feedback"],
        "metrics": "pi_proposed_count",
        "anti_patterns": [],
        "related_loops": []
      },
      "steps": [
        { "id": "capture", "_meta": { "actor": "Claude", "doc": "..." } },
        { "id": "distill", "_meta": { "actor": "Claude", "doc": "..." } }
      ],
      "_mermaid": "flowchart TD\n  capture --> distill"
    }
  ]
}
```

When `docs/feedback-loop/` does not exist: `{ "kilnInstalled": false, "loops": [] }`.

## Data Model

### Project (in-memory)
| Field | Type | Notes |
|-------|------|-------|
| `id` | string (UUID) | Generated on registration |
| `path` | string | Absolute path to repo root |
| `addedAt` | string (ISO8601) | Set on registration |

### Workflow
| Field | Type | Notes |
|-------|------|-------|
| `name` | string | From JSON `.name` |
| `description` | string | From JSON `.description` |
| `path` | string | Absolute path to JSON file |
| `source` | `"local" \| "plugin"` | Discovery source |
| `plugin` | string (optional) | Plugin name, only for plugin-sourced workflows |
| `stepCount` | number | `steps.length` |
| `steps` | `Step[]` | Full steps array from JSON |
| `localOverride` | boolean | True if local workflow shadows a plugin workflow of same name |

### Step
| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Step identifier |
| `type` | string | `"command" \| "agent" \| "workflow" \| "branch"` |
| `description` | string (optional) | |
| `prompt` | string (optional) | For agent steps |
| `command` | string (optional) | For command steps |
| `agent` | object (optional) | For agent steps |
| `requires_plugins` | string[] (optional) | |
| `model` | string (optional) | e.g. `"sonnet"` |
| `inputs` | object (optional) | |
| `output` | string (optional) | |
| `if_zero` | string (optional) | For branch steps |
| `if_nonzero` | string (optional) | For branch steps |
| `context_from` | string[] (optional) | |
| `on_error` | string (optional) | |
| `skip` | string (optional) | |

### FeedbackLoop
| Field | Type | Notes |
|-------|------|-------|
| `name` | string | From JSON root or `_meta.name` |
| `_meta` | object | `{ kind, status, owner, triggers, metrics, anti_patterns, related_loops, last_audited }` |
| `steps` | array | Loop steps with `_meta.doc` and `_meta.actor` |
| `_mermaid` | string (optional) | Pre-rendered Mermaid source |
