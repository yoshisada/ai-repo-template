# Technical Plan: wheel-view Next.js API + React Viewer

## Branch
`build/wheel-view-api-20260427`

## Technical Context

### Stack
- **Next.js 15** with App Router, TypeScript
- **React 19** frontend
- **Node.js 20+** (bundled in Next.js build)
- **Docker** container for API + frontend
- **No external database** — in-memory project store

### Directory Layout
```
plugin-wheel/viewer/
├── src/
│   ├── app/
│   │   ├── layout.tsx          # root layout
│   │   ├── page.tsx            # main viewer page
│   │   ├── api/
│   │   │   ├── health/route.ts
│   │   │   ├── projects/route.ts
│   │   │   ├── workflows/route.ts
│   │   │   └── feedback-loops/route.ts
│   ├── components/
│   │   ├── Sidebar.tsx
│   │   ├── WorkflowDetail.tsx
│   │   └── StepRow.tsx
│   ├── lib/
│   │   ├── projects.ts         # in-memory project store
│   │   ├── discover.ts          # filesystem discovery
│   │   └── types.ts             # TypeScript interfaces
│   └── styles/
│       └── viewer.css
├── Dockerfile
├── package.json
├── next.config.js
└── tsconfig.json
```

### Key Implementation Decisions

1. **Single container** — API and frontend in one Next.js app (API routes + page in same process). No separate backend needed.

2. **Filesystem discovery in TypeScript** — Read `~/.claude/plugins/installed_plugins.json` directly with Node `fs`. No bash, no shell escaping issues. Same logic as `workflow_discover_plugin_workflows()` but in TypeScript.

3. **In-memory projects** — module-level `Map<string, Project>` in `projects.ts`. No persistence.

4. **No caching** — Every API request reads from disk. Always fresh.

5. **Mermaid CDN** — Same approach as original viewer.html. Single `<script>` tag for Mermaid 10.9.0 in the page.

## Phase 1: Project Setup
- [ ] Create `viewer/` directory structure
- [ ] Write `package.json`, `next.config.js`, `tsconfig.json`, `Dockerfile`
- [ ] Install deps (locally, not in container)

## Phase 2: API Routes
- [ ] `GET /api/health` — returns `{ status: "ok", version: "0.1.0" }`
- [ ] `GET /api/projects` — list registered projects
- [ ] `POST /api/projects` — register a project (idempotent by path)
- [ ] `DELETE /api/projects/:id` — unregister project
- [ ] `GET /api/workflows` — local + plugin workflows for a project
- [ ] `GET /api/workflows/:name` — single workflow detail
- [ ] `GET /api/feedback-loops` — kiln loops if present

## Phase 3: Frontend
- [ ] `layout.tsx` — dark-themed root layout with global CSS
- [ ] `page.tsx` — main viewer (sidebar + detail pane)
- [ ] `Sidebar.tsx` — project switcher + workflow sections
- [ ] `WorkflowDetail.tsx` — metadata header + step list
- [ ] `StepRow.tsx` — expandable step row

## Phase 4: Skill + Docker
- [ ] Update `skill.md` to start container and call `POST /api/projects`
- [ ] `Dockerfile` — build Next.js app, expose port 3000

## Constitutions & Contracts

See `specs/wheel-view-api/contracts/interfaces.md` for API shape.

## Risks & Open Questions

- **Docker on macOS** — tested on user's Darwin setup; assumes Docker CLI available
- **Port 3847** — fixed port. Conflict unlikely but could be env-var configurable
