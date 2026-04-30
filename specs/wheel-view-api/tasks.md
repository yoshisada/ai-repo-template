# Tasks: wheel-view Next.js API + React Viewer

## Phase 1: Project Setup

- [X] Create `viewer/src/` directory structure
- [X] Write `viewer/package.json` with Next.js 15, React 19, uuid
- [X] Write `viewer/next.config.js`
- [X] Write `viewer/tsconfig.json`
- [X] Write `viewer/Dockerfile` (node:20-alpine, npm run dev)

## Phase 2: API Routes

- [X] `GET /api/health` — returns `{ status: "ok", version: "0.1.0" }`
- [X] `GET /api/projects` — returns `Project[]`
- [X] `POST /api/projects` — body: `{ path: string }`, returns `Project`, idempotent by path
- [X] `DELETE /api/projects/:id` — returns 204
- [X] `GET /api/workflows?projectId=<id>` — returns `{ local: Workflow[], plugin: Workflow[] }`
- [X] `GET /api/workflows/:name?projectId=<id>` — returns single `Workflow` or 404
- [X] `GET /api/feedback-loops?projectId=<id>` — returns `{ loops: FeedbackLoop[], kilnInstalled: bool }`

## Phase 3: Frontend Components

- [X] `viewer/src/lib/types.ts` — TypeScript interfaces
- [X] `viewer/src/lib/projects.ts` — globalThis-persisted project store
- [X] `viewer/src/lib/discover.ts` — filesystem discovery (local + plugin)
- [X] `viewer/src/lib/api.ts` — client-side fetch helpers
- [X] `viewer/src/app/layout.tsx` — dark-themed root layout
- [X] `viewer/src/app/page.tsx` — main viewer page
- [X] `viewer/src/components/Sidebar.tsx` — project switcher + workflow list
- [X] `viewer/src/components/WorkflowDetail.tsx` — step list + metadata
- [X] `viewer/src/components/StepRow.tsx` — expandable step row
- [X] `viewer/src/styles/viewer.css` — dark theme styles

## Phase 4: Skill + Docker

- [X] Update `viewer/Dockerfile` — install deps, build, start
- [X] Update `plugin-wheel/skills/wheel-view/skill.md` — check health → start container → register project → open browser

## Verified

- [X] Build succeeds (`npm run build`)
- [X] API health returns `{ status: "ok", version: "0.1.0" }`
- [X] Project registration works (idempotent by path)
- [X] Workflow discovery returns 2 local + 18 plugin workflows for this repo
- [X] Frontend page renders

## Dependencies
- Phase 2 must complete before Phase 3 (API routes needed for frontend fetch calls)
- Phase 3 can proceed in parallel with Phase 4 (separate files)
