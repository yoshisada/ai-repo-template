---
name: trim-design
description: Generate an initial Penpot design from product context. Reads PRD, existing components, and project conventions to create a structured Penpot design via MCP.
---

# trim-design — Generate Design from Product Context

Read product context (PRDs, existing component library, project conventions) and generate an initial Penpot design via MCP. Reuses existing library components where appropriate and follows the project's visual conventions. Runs as a wheel workflow.

## User Input

```text
$ARGUMENTS
```

Description of what to design, or path to a PRD file. Examples:
- `"login page with email, password, and submit button"`
- `docs/features/2026-04-09-trim/PRD.md`
- `"settings page based on the current PRD"`

## Steps

### 1. Validate Configuration

```bash
if [ ! -f .trim/config ]; then
  echo "ERROR: No .trim/config found. Run /trim-init first to connect to your Penpot project."
  exit 1
fi
```

### 2. Run Workflow

Delegate to the trim-design wheel workflow:

```
/wheel-run trim:trim-design
```

The workflow executes these steps in order:
1. **read-config** — parses `.trim/config` and validates required fields
2. **read-mappings** — reads existing component library from `.trim/components.json`
3. **detect-framework** — detects UI framework and CSS approach for informed design decisions
4. **read-product-context** — gathers PRDs, project conventions, and existing component names
5. **resolve-trim-plugin** — resolves trim plugin install path at runtime
6. **generate-design** — creates Penpot design via MCP, reusing existing components, applying project conventions
7. **update-mappings** — writes updated component mappings for newly created design components

### 3. Report Results

After the workflow completes, read the outputs and report:

```
Design generated.

  Page/Frame:        {name of created Penpot page or frame}
  Components Reused: {N} from existing library
  Components Created: {N} new

  Visual Conventions Applied:
    - {colors, typography, spacing patterns detected and used}

  Components Page: {created | updated} with {N} component groups
  Updated: .trim/components.json

Next: Open Penpot to review and refine the generated design,
      then run /trim-pull to generate code from the design.
```

## Rules

- **Config required** — fail immediately if `.trim/config` is missing (FR-026)
- **Reuse library components** — use existing Penpot components from mappings where appropriate (FR-023)
- **Follow conventions** — apply project's existing visual conventions for colors, typography, spacing (FR-024)
- **Product context driven** — design decisions should be informed by PRD requirements (FR-022)
- **MCP only** — all Penpot interactions go through MCP tools (NFR-003)
