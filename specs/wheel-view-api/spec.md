# Feature Specification: /wheel:wheel-view — Next.js API + React Viewer

**Feature Branch**: `build/wheel-view-api-20260427`
**Created**: 2026-04-27
**Status**: Draft
**Input**: Roadmap item — `.kiln/roadmap/items/2026-04-27-wheel-view-html-viewer.md` (phase: `12-loop-and-workflow-design`)

## Context

The current `wheel-view` skill generates a static HTML file by embedding all workflow data (local + plugin) into a template via shell-script JSON injection. This approach fights against bash's variable scoping, heredoc expansion limits, and JSON escaping — making the code fragile and hard to maintain.

The replacement architecture: a Next.js API server + React frontend, running in a Docker container, with on-demand filesystem discovery and in-memory project state.

## User Scenarios

### US1 — View workflows in current project (P1)
A maintainer invokes `/wheel:wheel-view` from a repo. The skill checks if the API container is running, starts it if not, registers the current repo as a project, and opens the frontend. The frontend shows all local workflows and plugin workflows for that project.

### US2 — Switch between projects (P1)
A maintainer working on multiple repos can switch the viewer between them via a project dropdown. Each project shows its own local workflows; plugin workflows are the same across all projects (same installed plugins).

### US3 — Inspect workflow steps (P1)
User clicks a workflow in the sidebar → detail pane shows metadata (name, path, description, step count) with expandable step rows showing full step content (command scripts, agent prompts, inputs/outputs, model selection).

### US4 — View feedback loops (P2)
When kiln is installed in the project (presence of `docs/feedback-loop/`), a third section appears with feedback loop docs. Each loop shows its Mermaid diagram and per-step documentation.

### US5 — Real-time discovery (P2)
The API reads from filesystem on each request — no caching. Plugin workflow changes (new install, workflow file edits) appear on next page load without restarting anything.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Docker Container (Next.js)                                 │
│  Port 3847 → 3000                                          │
│                                                             │
│  ┌─────────┐   ┌──────────┐   ┌─────────────────────────┐  │
│  │ Next.js │   │ API Route │   │ React Frontend          │  │
│  │ Server  │───│ handlers  │───│ (project switcher,      │  │
│  │ :3000   │   │           │   │  workflow list + detail) │  │
│  └─────────┘   └──────────┘   └─────────────────────────┘  │
│                    │                                      │
│                    └── reads filesystem on demand          │
│                         ~/.claude/plugins/installed_plugins│
│                         <project>/workflows/               │
└─────────────────────────────────────────────────────────────┘
         ▲                                    │
         │ curl / POST                       │ browser
         │                                    ▼
    /wheel:wheel-view skill          localhost:3847
    (starts container if needed)
```

### Components

1. **`plugin-wheel/viewer/`** — Next.js application source
   - `src/app/` — Next.js App Router pages and API routes
   - `src/components/` — React components
   - `Dockerfile` — container build

2. **`plugin-wheel/skills/wheel-view/skill.md`** — skill that:
   - Checks container running (`curl http://localhost:3847/api/health`)
   - Starts container if needed (`docker run -d -p 3847:3000`)
   - Calls `POST /api/projects { "path": "<cwd>" }`
   - Opens browser to `http://localhost:3847`

3. **In-memory project store** — projects registered via API live for container's lifetime. No persistence.

## API Design

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/health` | Container health check. Returns `{ "status": "ok", "version": "x.y.z" }` |
| `GET` | `/api/projects` | List registered projects. Returns `[{ "id": "uuid", "path": "/repo/root", "addedAt": "ISO8601" }]` |
| `POST` | `/api/projects` | Register a project. Body: `{ "path": "/repo/root" }`. Returns `{ "id": "uuid", "addedAt": "ISO8601" }`. Idempotent — if path already registered, returns existing entry. |
| `DELETE` | `/api/projects/:id` | Unregister a project. Returns `204 No Content`. |
| `GET` | `/api/workflows?projectId=<id>` | Get workflows for a project. Returns `{ "local": [...], "plugin": [...] }`. Local scanned from `<project>/workflows/*.json`; plugin discovered via `~/.claude/plugins/installed_plugins.json`. |
| `GET` | `/api/workflows/:name?projectId=<id>` | Get single workflow detail. Returns full workflow JSON (steps array). |
| `GET` | `/api/feedback-loops?projectId=<id>` | Get feedback loops if kiln present. Returns `{ "loops": [...], "kilnInstalled": true/false }`. Only populated if `docs/feedback-loop/` exists in project. |

### Notes

- All responses are JSON with `Content-Type: application/json`.
- `projectId` param references the in-memory project registry by UUID, not path.
- If `projectId` is omitted from workflow endpoints, defaults to the first registered project (for convenience when there's only one).
- API reads filesystem directly on every request — no caching layer.

## Data Model

### Project (in-memory)
```typescript
interface Project {
  id: string;        // UUID
  path: string;      // absolute path to repo root
  addedAt: string;   // ISO8601 timestamp
}
```

### Workflow (API response shape)
```typescript
interface Workflow {
  name: string;
  description: string;
  path: string;      // absolute path to .json file
  source: "local" | "plugin";
  plugin?: string;   // only for plugin-sourced workflows
  stepCount: number;
  steps: Step[];
  localOverride: boolean;  // true if a local workflow shadows a plugin workflow of same name
}

interface Step {
  id: string;
  type: "command" | "agent" | "workflow" | "branch";
  description?: string;
  prompt?: string;      // for agent steps
  command?: string;     // for command steps
  agent?: object;       // for agent steps
  requires_plugins?: string[];
  model?: string;
  inputs?: object;
  output?: string;
  if_zero?: string;
  if_nonzero?: string;
  context_from?: string[];
  on_error?: string;
  skip?: string;
}
```

### Feedback Loop (API response shape)
```typescript
interface FeedbackLoop {
  name: string;
  _meta: {
    kind: string;
    status: string;
    owner?: string;
    triggers?: string[];
    metrics?: string;
    anti_patterns?: string[];
    related_loops?: string[];
    last_audited?: string;
  };
  steps: Array<{
    id: string;
    _meta?: { doc?: string; actor?: string };
    doc?: string;
    actor?: string;
  }>;
  _mermaid?: string;  // derived Mermaid diagram source
}
```

## Technical Approach

### Next.js App (`plugin-wheel/viewer/`)

**Stack**: Next.js 14+ with App Router, TypeScript, Tailwind CSS (optional or vanilla CSS).

**Directory structure**:
```
viewer/
├── src/
│   ├── app/
│   │   ├── layout.tsx          # root layout
│   │   ├── page.tsx           # main viewer page
│   │   ├── api/
│   │   │   ├── health/route.ts
│   │   │   ├── projects/route.ts
│   │   │   ├── workflows/route.ts
│   │   │   └── feedback-loops/route.ts
│   ├── components/
│   │   ├── Sidebar.tsx        # project switcher + workflow list
│   │   ├── WorkflowDetail.tsx # step list + metadata
│   │   └── StepRow.tsx        # expandable step row
│   ├── lib/
│   │   ├── projects.ts        # in-memory project store
│   │   ├── discover.ts        # filesystem discovery helpers
│   │   └── types.ts           # TypeScript interfaces
│   └── styles/
│       └── viewer.css         # viewer-specific styles
├── Dockerfile
├── package.json
├── next.config.js
└── tsconfig.json
```

**API route handlers** — directly read from filesystem using `fs` module. Use `child_process` to call `jq` for JSON parsing (reusing `workflow_discover_plugin_workflows` logic or reimplementing the scanning subset).

**No database** — all project state is in a module-level Map/array.

### Docker

**Dockerfile** at `plugin-wheel/viewer/Dockerfile`:
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY viewer/package.json viewer/next.config.js ./
RUN npm install
COPY viewer/src ./src
EXPOSE 3000
CMD ["npm", "run", "dev"]
```

Container runs with `HOST_PORT=3847` → `CONTAINER_PORT=3000`.

### Skill (`plugin-wheel/skills/wheel-view/skill.md`)

Updated to:
1. Check health: `curl -s http://localhost:3847/api/health`
2. If not running: `docker build -t wheel-view ./viewer && docker run -d -p 3847:3000 wheel-view`
3. Register project: `curl -X POST http://localhost:3847/api/projects -H "Content-Type: application/json" -d '{"path":"<cwd>"}'`
4. Open browser: `open http://localhost:3847`

### Frontend Design

Dark-themed, matching the original viewer.html aesthetic:
- Left sidebar: project dropdown (if multiple projects) + section headers ("Local", "Plugin", "Feedback Loops") + workflow items
- Right pane: workflow metadata header + expandable step list

No authentication. No persistent state. Page reload re-fetches all data.

## Dependencies

- Node.js 20+ (for Next.js)
- Docker (for container runtime)
- No external database or stateful backend

## Out of Scope (v2)

- Persistent project registry
- Search/filter across workflows
- Workflow execution from the viewer
- Real-time updates (SSE/polling) — v1 is "reload to refresh"
- Windows support for Docker-based workflow

## Acceptance Criteria

1. `/wheel:wheel-view` starts the Docker container if needed and opens `localhost:3847`
2. Frontend shows local workflows and plugin workflows for the registered project
3. Switching projects via dropdown shows that project's local workflows (plugin list unchanged)
4. Clicking a workflow expands its steps showing full content
5. Feedback loops appear when `docs/feedback-loop/` exists in the project
6. New/changed workflow files appear on page reload without container restart
7. Container can be stopped and restarted; projects list resets to empty
8. API returns proper error responses (404 for unknown workflow, 400 for missing params)