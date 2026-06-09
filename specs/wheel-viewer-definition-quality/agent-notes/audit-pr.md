# audit-pr — Friction Notes (FR-009)

**Agent**: audit-pr (task #7 — Smoke test + PR creation)
**Pipeline**: wheel-viewer-definition-quality
**PRD**: `docs/features/2026-05-09-wheel-viewer-definition-quality/PRD.md`
**Date**: 2026-05-09

## Smoke test outcome

| Step | Result |
|---|---|
| `docker build -t wheel-view plugin-wheel/viewer` | ✅ PASS — Next.js 15.1.0 production build, 8/8 static pages, 174 kB First Load JS, image `a6f7da8172ce`, build time ~17s. |
| Container start (`docker run -d -p 3847:3000 ...`) | ✅ PASS — container `c3c048627ade` (initial), then re-run as `f20e5ee217a4` after adding the project bind-mount. |
| `GET /api/health` | ✅ PASS — `{"status":"ok","version":"0.1.0"}`. |
| `POST /api/projects` (register repo) | ✅ PASS — returned 201 with valid `Project` JSON. |
| `GET /api/workflows?projectId=<id>` | ✅ PASS — `{local_count: 18, plugin_count: 19}`. All 19 plugin workflows tagged `discoveryMode: "source"` (FR-6.2 source-checkout discovery confirmed live). |
| Container teardown | ✅ PASS — clean stop + rm. |

## Friction encountered

### F-1 (LOW) — Docker daemon was not running at start

When I ran the very first `docker build`, the daemon was down. Symptom: `Cannot connect to the Docker daemon at unix:///var/run/docker.sock`. Recovered with `open -a "Docker"` followed by an `until docker info > /dev/null; do sleep 3; done` poll.

**Lesson for next pipeline**: a future iteration of `kiln:audit-pr` could include a `docker info` pre-check + auto-start as the very first action so this friction doesn't burn an iteration mid-pipeline.

### F-2 (LOW) — audit-compliance recommended `docker compose up`, but no compose file ships

The audit-compliance handoff message recommended `cd plugin-wheel/viewer && docker compose up`, but the viewer ships only a `Dockerfile` (no `docker-compose.yml`). I fell back to the original task-prompt recipe (`docker build` + `docker run`). Worth a heads-up to whoever wrote the audit-compliance instruction template that the recommended invocation should match what's actually shipped.

**Recommendation**: either add a `docker-compose.yml` to `plugin-wheel/viewer/` (cleanest UX for `docker compose up`), or update the audit-compliance instruction template to use the bare-Dockerfile recipe.

### F-3 (MEDIUM) — Smoke recipe in task instructions only mounts `~/.claude`, not the project

The task prompt's recommended `docker run` only bind-mounts `$HOME/.claude:/host_home/.claude:ro`. With that mount alone, `discoverLocalWorkflows` and `discoverSourcePluginWorkflows` cannot see the host project — `/api/workflows?projectId=<id>` returned `{local: 0, plugin: 0}` because the container looks up `<project.path>` literally inside its own filesystem.

To get a meaningful smoke (and to validate the new `discoveryMode` field per task instruction step 3), I added `-v <projectPath>:<projectPath>:ro` to the run command. Then `local_count=18, plugin_count=19` and all 19 plugin workflows reported `discoveryMode: "source"`.

**Recommendation**: either (a) update the audit-pr smoke recipe in the build-prd skill to mount the project by default, or (b) document this requirement in `plugin-wheel/viewer/README.md` so end-users get a working smoke recipe out of the box. (a) is preferable.

### F-4 (LOW) — Build artifact `tsconfig.tsbuildinfo` not in `.gitignore`

`plugin-wheel/viewer/tsconfig.tsbuildinfo` (TypeScript incremental-build artifact, ~129 KB) showed up untracked. Added to `.gitignore` as part of this PR alongside `.kiln/qa/results/` (also untracked, also a generated artifact).

**Recommendation**: roll into a future kiln-init/kiln-doctor pass so consumer projects scaffolded via `init.mjs` get these patterns from day one.

### F-5 (LOW) — Stale `cwd` in Bash session after first `cd`

After the first `cd plugin-wheel/viewer && docker build .`, the shell stayed in that subdirectory and a subsequent `plugin-wheel/...` relative path failed. Switched all subsequent invocations to absolute paths and the issue cleared.

**Lesson**: when the harness persists shell state across Bash calls, prefer absolute paths from the start. CLAUDE.md already advises this — internalizing it more aggressively would have saved one iteration.

## Process observations

- **Wait-state worked cleanly**: I parked on "blocked by task #6" and resumed within seconds of audit-compliance's `Compliance audit done` SendMessage. No spurious early starts; no polling. The build-prd team-mode coordination is solid.
- **Audit handoff was high-signal**: audit-compliance's SendMessage included headline numbers, residual caveats (the screenshot mirror, the qa-engineer uncommitted-files cleanup), and the PR body recipe. That cuts down the audit-pr context-load cost a lot. Worth preserving as a template across pipelines.
- **Screenshots discoverable at both canonical paths**: per audit-compliance's note, the 12 screenshots now live at BOTH `specs/wheel-viewer-definition-quality/screenshots/` (qa-engineer's working location) AND `docs/features/2026-05-09-wheel-viewer-definition-quality/screenshots/` (PRD-relative, mirror created during audit-compliance). I'm using the `docs/features/.../screenshots/` paths in the PR body so GitHub renders them inline relative to the PRD location.
