---
name: wheel-view
description: Inspect wheel workflows (local + plugin) and feedback loops via a browser UI backed by a local API.
---

# Wheel View — Workflow Inspection UI

Open a browser-based workflow inspector backed by a Next.js API running in a Docker container.

The only input to register a project is its path — the API reads the filesystem directly to discover local and plugin workflows.

## Step 1: Check if Container is Running

```bash
CONTAINER_ID=$(docker ps --filter "ancestor=wheel-view" --format "{{.ID}}" 2>/dev/null | head -1)
if [[ -n "$CONTAINER_ID" ]]; then
  echo "CONTAINER_RUNNING:$CONTAINER_ID"
else
  echo "CONTAINER_NOT_RUNNING"
fi
```

## Step 2: Start Container (if not running)

```bash
VIEWER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../viewer"
DOCKERFILE="$VIEWER_DIR/Dockerfile"

if ! docker image inspect wheel-view >/dev/null 2>&1; then
  echo "Building wheel-view image..."
  docker build -t wheel-view "$VIEWER_DIR" || { echo "Docker build failed"; exit 1; }
fi

CONTAINER_ID=$(docker run -d -p 3847:3000 --name wheel-view -v "$HOME/.claude:/host_home/.claude:ro" wheel-view)
echo "CONTAINER_STARTED:$CONTAINER_ID"
sleep 3
```

Display output from both blocks above.

## Step 3: Verify API Health

```bash
HEALTH=$(curl -s http://localhost:3847/api/health 2>/dev/null || echo '{"error":"unreachable"}')
echo "API_HEALTH:$HEALTH"
```

## Step 4: Register Current Project (idempotent — only path required)

```bash
REPO_PATH="$(pwd)"
REGISTER_RESULT=$(curl -s -X POST http://localhost:3847/api/projects \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"$REPO_PATH\"}" 2>/dev/null)
echo "REGISTER_RESULT:$REGISTER_RESULT"
```

Display the output.

## Step 5: Open Browser

```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
  open http://localhost:3847 2>/dev/null && echo "Browser opened." || echo "Open manually: http://localhost:3847"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  xdg-open http://localhost:3847 2>/dev/null && echo "Browser opened." || echo "Open manually: http://localhost:3847"
else
  echo "Open manually: http://localhost:3847"
fi
```

## Step 6: One-line Status Summary

```bash
echo "wheel-view running at http://localhost:3847 — add any repo by entering its path in the sidebar"
```

## Rules

- Container name/tag `wheel-view` is used for singleton management — one container at a time (FR-016).
- Port **3847** is fixed — no env var configuration in v1.
- Project registration is idempotent by path — `POST /api/projects` returns existing project if path already registered (FR-007, FR-008).
- No persistent storage — projects live in container memory only; restarting the container resets the registry.
- `~/.claude/plugins/installed_plugins.json` is mounted read-only into the container so the API can discover plugin workflows without modify access.
- Stop the container with `docker stop wheel-view && docker rm wheel-view` when done.
