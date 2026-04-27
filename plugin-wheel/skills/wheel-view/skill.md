---
name: wheel-view
description: Generate an HTML viewer for all available wheel workflows and (when kiln is installed) feedback loops.
---

# Wheel View — HTML Workflow Viewer

Generate a self-contained HTML page showing all available wheel workflows (local + plugin) with expandable step details, and — when kiln is installed — feedback-loop docs with Mermaid diagrams.

## Step 1: Discover Local Workflows (FR-001, FR-002)

```bash
WORKFLOW_FILES=($(find workflows/ -name "*.json" -type f 2>/dev/null | sort))
if [[ ${#WORKFLOW_FILES[@]} -eq 0 ]]; then
  echo "NO_LOCAL_WORKFLOWS"
fi
```

If the output contains `NO_LOCAL_WORKFLOWS`, local workflows section will be empty-state.

## Step 2: Discover Plugin Workflows (FR-002)

```bash
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${WHEEL_LIB_DIR}/workflow.sh"

PLUGIN_WORKFLOWS=$(workflow_discover_plugin_workflows)
PLUGIN_WF_COUNT=$(echo "$PLUGIN_WORKFLOWS" | jq 'length')
echo "PLUGIN_COUNT:$PLUGIN_WF_COUNT"
```

## Step 3: Check for Feedback Loops (FR-010)

```bash
FEEDBACK_LOOPS_DIR="docs/feedback-loop"
if [[ -d "$FEEDBACK_LOOPS_DIR" && -n "$(find "$FEEDBACK_LOOPS_DIR" -name "*.json" -type f 2>/dev/null)" ]]; then
  echo "KILN_INSTALLED=true"
  FEEDBACK_FILES=($(find "$FEEDBACK_LOOPS_DIR" -name "*.json" -type f 2>/dev/null | sort))
  echo "FEEDBACK_COUNT:${#FEEDBACK_FILES[@]}"
else
  echo "KILN_INSTALLED=false"
fi
```

## Step 4: Build Data & Generate HTML (FR-003 – FR-022)

```bash
SKILL_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SKILL_BASE_DIR/../.."
WHEEL_LIB_DIR="${PLUGIN_DIR}/lib"
source "${WHEEL_LIB_DIR}/workflow.sh"

WORKFLOW_FILES=($(find workflows/ -name "*.json" -type f 2>/dev/null | sort))
PLUGIN_WORKFLOWS=$(workflow_discover_plugin_workflows)

FEEDBACK_LOOPS_DIR="docs/feedback-loop"
HAS_KILN=false
if [[ -d "$FEEDBACK_LOOPS_DIR" && -n "$(find "$FEEDBACK_LOOPS_DIR" -name "*.json" -type f 2>/dev/null)" ]]; then
  HAS_KILN=true
fi

WHEEL_VERSION=$(cd "$PLUGIN_DIR" && cat package.json | jq -r '.version' 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build local workflows JSON
LOCAL_WF_JSON="[]"
if [[ ${#WORKFLOW_FILES[@]} -gt 0 ]]; then
  LOCAL_WF_JSON=$(for f in "${WORKFLOW_FILES[@]}"; do
    JSON=$(cat "$f" 2>/dev/null)
    if echo "$JSON" | jq empty 2>/dev/null; then
      NAME=$(echo "$JSON" | jq -r '.name // empty')
      if [[ -z "$NAME" ]]; then continue; fi
      DESC=$(echo "$JSON" | jq -r '.description // empty')
      STEPS=$(echo "$JSON" | jq -c '.steps // []')
      echo "$JSON" | jq --arg name "$NAME" --arg desc "$DESC" --arg path "$f" --argjson steps "$STEPS" \
        -c '{name: $name, description: $desc, path: $path, source: "local", steps: $steps, stepCount: ($steps | length), localOverride: false}'
    fi
  done | jq -s '.')
fi

# Build plugin workflows JSON
PLUGIN_WF_JSON="[]"
if [[ $(echo "$PLUGIN_WORKFLOWS" | jq 'length') -gt 0 ]]; then
  PLUGIN_WF_JSON=$(echo "$PLUGIN_WORKFLOWS" | jq -c '.[]' | while read entry; do
    WF_PATH=$(echo "$entry" | jq -r '.path')
    WF_NAME=$(echo "$entry" | jq -r '.name')
    PLUGIN_NAME=$(echo "$entry" | jq -r '.plugin')
    JSON=$(cat "$WF_PATH" 2>/dev/null)
    if echo "$JSON" | jq empty 2>/dev/null; then
      DESC=$(echo "$JSON" | jq -r '.description // empty')
      STEPS=$(echo "$JSON" | jq -c '.steps // []')
      LOCAL_OVERRIDE=false
      [[ -f "workflows/${WF_NAME}.json" ]] && LOCAL_OVERRIDE=true
      echo "$entry" | jq --arg desc "$DESC" --argjson steps "$STEPS" --arg path "$WF_PATH" \
        --argjson localOverride "$LOCAL_OVERRIDE" --argjson stepCount "$(echo $STEPS | jq 'length')" \
        -c '. + {description: $desc, path: $path, steps: $steps, stepCount: $stepCount, localOverride: $localOverride}'
    fi
  done | jq -s '.')
fi

# Build feedback loops JSON if kiln installed
FEEDBACK_JSON="[]"
if [[ "$HAS_KILN" == "true" ]]; then
  FEEDBACK_JSON=$(find "$FEEDBACK_LOOPS_DIR" -name "*.json" -type f -exec cat {} \; 2>/dev/null | jq -s 'flatten' 2>/dev/null || echo "[]")
fi

# Build meta object
META_JSON=$(jq -n --arg version "$WHEEL_VERSION" --arg timestamp "$TIMESTAMP" \
  '{version: $version, timestamp: $timestamp}')

# Combine into full data object
DATA_JSON=$(jq -n --argjson local "$LOCAL_WF_JSON" --argjson plugin "$PLUGIN_WF_JSON" \
  --argjson feedback "$FEEDBACK_JSON" --argjson meta "$META_JSON" \
  '{local: $local, plugin: $plugin, feedback: $feedback, meta: $meta}')

# Escape for JS embedding
ESCAPED_DATA=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" <<< "$DATA_JSON")

# Read template and inject data
VIEWER_HTML="$SKILL_BASE_DIR/viewer.html"
HTML_CONTENT=$(cat "$VIEWER_HTML")
FINAL_HTML=$(python3 -c "import sys
content = sys.stdin.read()
data = sys.argv[1]
print(content.replace('WHEEL_VIEW_DATA_PLACEHOLDER', data))
" "$ESCAPED_DATA" <<< "$HTML_CONTENT")

# Write to temp file
OUTPUT_FILE="/tmp/wheel-view-$$.html"
echo "$FINAL_HTML" > "$OUTPUT_FILE"

echo "HTML_GENERATED:$OUTPUT_FILE"
```

Display the output from the bash block above.

## Step 5: Open in Browser (FR-015, FR-016)

```bash
HTML_FILE=$(ls -t /tmp/wheel-view-*.html 2>/dev/null | head -1)
if [[ -z "$HTML_FILE" ]]; then
  echo "ERROR: HTML file not found"
  exit 1
fi

echo "Generated: $HTML_FILE"

# Try to open in browser
if [[ "$OSTYPE" == "darwin"* ]]; then
  open "$HTML_FILE" 2>/dev/null && echo "Opened in browser." || echo "Could not auto-open. Open manually: $HTML_FILE"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  xdg-open "$HTML_FILE" 2>/dev/null && echo "Opened in browser." || echo "Could not auto-open. Open manually: $HTML_FILE"
else
  echo "Open manually: $HTML_FILE"
fi
```

Display the output from the bash block above.

## Rules

- This skill takes no arguments and is read-only (FR-012, FR-020).
- Workflow discovery reuses `workflow_discover_plugin_workflows()` from `plugin-wheel/lib/workflow.sh` — no reimplementation (FR-002).
- Local workflow discovery uses `find workflows/ -name "*.json"` — mirrors `wheel-list` FR-001 (FR-002).
- The generated HTML is self-contained with inline CSS and vanilla JS only; Mermaid CDN is the only external resource (FR-003, FR-013, FR-014).
- Feedback-loops section only renders when `docs/feedback-loop/` exists — absence is intentional (FR-010, SC-006).
- Malformed workflow JSON appears as an error entry with parse error preview — never silently dropped (FR-017).
- The HTML file is written to `/tmp/wheel-view-<pid>.html` (FR-016).
- The skill never modifies `workflows/`, plugin install directories, or `docs/feedback-loop/` (FR-020).