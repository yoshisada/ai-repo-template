---
name: trim-pull
description: Pull a Penpot design into framework-appropriate code. Reads design via MCP, detects project framework, generates code, and updates component mappings.
---

# trim-pull — Pull Penpot Design into Code

Read a Penpot design via MCP and generate framework-appropriate code that matches the design's layout, spacing, colors, typography, and component hierarchy. Reuses existing components from the component mapping. Runs as a wheel workflow with deterministic step ordering.

## User Input

```text
$ARGUMENTS
```

Optional: Penpot page name or component name to pull. If omitted, pulls the default page from `.trim/config`.

## Steps

### 1. Validate Configuration

Check that `.trim/config` exists and has valid Penpot connection details:

```bash
if [ ! -f .trim/config ]; then
  echo "ERROR: No .trim/config found. Run /trim-init first to connect to your Penpot project."
  exit 1
fi
```

### 2. Run Workflow

Delegate to the trim-pull wheel workflow:

```
/wheel-run trim:trim-pull
```

The workflow executes these steps in order:
1. **read-config** — parses `.trim/config` and validates required fields
2. **detect-framework** — detects UI framework (React/Vue/Svelte/HTML) and CSS approach from package.json
3. **read-mappings** — reads current `.trim/components.json` to know which components already exist
4. **resolve-trim-plugin** — resolves the trim plugin install path at runtime
5. **pull-design** — reads Penpot design via MCP, generates framework-appropriate code, reuses existing components
6. **update-mappings** — writes updated component mappings to `.trim/components.json`

### 3. Report Results

After the workflow completes, read the outputs and report:

```
Pull complete.

  Framework:       {detected framework}
  CSS Approach:    {detected CSS approach}
  Page/Component:  {what was pulled}

  Generated Files:
    - {list of created/updated code files}

  Component Mappings:
    - {N} existing (unchanged)
    - {N} new (created)

  Updated: .trim/components.json

Next: Run /trim-diff to verify code matches the design,
      or edit the generated code and /trim-push to sync changes back.
```

If the workflow failed (e.g., MCP unavailable), display the error from the relevant step output.

## Rules

- **Config required** — fail immediately if `.trim/config` is missing (FR-026)
- **Reuse existing components** — never recreate a component that already has a mapping (FR-011)
- **Framework-appropriate** — generated code must match the detected framework and CSS approach (FR-009, FR-010)
- **Update mappings** — all new components must be added to `.trim/components.json` (FR-012)
- **MCP only** — all Penpot interactions go through MCP tools, never direct API calls (NFR-003)
