# Trim Research: Penpot MCP Capabilities

**Date**: 2026-04-09
**Researcher**: researcher agent
**Purpose**: Map Penpot MCP capabilities to PRD use cases for the trim plugin

---

## 1. Penpot MCP Landscape

There are two distinct categories of Penpot MCP servers:

### A. Official Penpot MCP (penpot/penpot-mcp)

- **Repository**: Originally at `penpot/penpot-mcp`, now integrated into `penpot/penpot` at `mcp/` directory
- **Architecture**: Plugin-based. An MCP server communicates with a Penpot plugin running inside the browser via WebSocket. The plugin executes code using the Penpot Plugin API.
- **Transport**: Streamable HTTP endpoint at `http://localhost:4401/mcp` (local mode)
- **Install**: `npx @penpot/mcp@beta`
- **Requirement**: Penpot must be open in a browser with the MCP plugin loaded from `http://localhost:4400/manifest.json`

**Available Tools (Official)**:
| Tool | Description |
|------|-------------|
| `execute_code` | Runs arbitrary JavaScript in the Penpot Plugin environment. Has access to `penpot` API object, `penpotUtils` helpers, `storage` for persistence, and `console` for logging. This is the primary workhorse tool. |
| `high_level_overview` | Returns comprehensive system documentation and capabilities |
| `penpot_api_info` | Retrieves Penpot Plugin API type information and TypeScript definitions |
| `export_shape` | Exports design shapes as PNG, JPG, SVG, or PDF |
| `import_image` | Imports images into the design (local mode only) |

**Key insight**: The official MCP uses `execute_code` as a general-purpose tool. Rather than exposing discrete create/update/delete tools, it gives the LLM full access to the Plugin API via code execution. The LLM writes JavaScript snippets that call `penpot.createBoard()`, `penpot.createRectangle()`, `penpot.createText()`, etc.

**Plugin API capabilities** (accessible via `execute_code`):
- Create elements: `penpot.createBoard()`, `penpot.createRectangle()`, `penpot.createText()`, `penpot.createEllipse()`, `penpot.createPath()`
- Read/modify file structure: components, styles, tokens, pages, layers
- Create and manage design tokens (spacing, typography, color)
- Apply tokens and styles consistently across elements
- Read layout properties, component hierarchies
- Organize and rename layers and components

### B. Community MCP: zcube/penpot-mcp-server (76+ tools)

- **Repository**: `zcube/penpot-mcp-server`
- **Architecture**: Direct API access. Communicates with Penpot's backend RPC API directly (no browser plugin required).
- **Advantage**: Does NOT require Penpot open in a browser. Works headlessly.
- **Disadvantage**: Third-party, may lag behind Penpot releases.

**Available Tools (76+ across 11 categories)**:

| Category | Tools | Key Operations |
|----------|-------|----------------|
| **Project/File Management** | `list_projects`, `list_files`, `get_file`, `create_file`, `rename_file`, `delete_file` | Browse and manage projects/files |
| **Page Management** | `list_pages`, `add_page`, `get_page_shapes`, `query_shapes`, `get_shape_properties`, `rename_page`, `delete_page`, `move_shapes` | Full page CRUD and shape querying |
| **Shape Creation** | `create_rectangle`, `create_circle`, `create_frame`, `create_text`, `create_svg`, `create_path` (planned) | Create all primitive shape types |
| **Shape Manipulation** | `update_shape`, `delete_shape`, `duplicate_shapes` (planned), `group_shapes` (planned) | Modify position, size, style properties |
| **Alignment & Distribution** | `align_shapes`, `distribute_shapes` | Layout alignment |
| **Component System** | `create_component`, `update_component`, `delete_component`, `list_components`, `instantiate_component` (planned) | Full component CRUD |
| **Export & Media** | `export_shape`, `list_file_media`, `upload_file_media`, `upload_file_media_from_url`, `delete_file_media`, `clone_media` | Export to PNG/JPG/SVG/PDF, manage media |
| **Font Management** | `upload_font`, `list_team_fonts`, `get_font_variants`, `update_font_variant`, `delete_font_variant` | Custom font management |
| **Comments** | `list_comment_threads`, `get_comments`, `create_comment_thread`, `add_comment`, `update_comment`, `delete_comment` | Feedback/review workflow |
| **Search** | `search_files`, `search_projects`, `search_shapes`, `search_components`, `advanced_search` | Multi-resource search |
| **Team/Sharing** | `create_team`, `list_team_members`, `invite_team_member`, `create_share_link`, etc. | Collaboration management |

### C. Community MCP: montevive/penpot-mcp

- **Repository**: `montevive/penpot-mcp`
- **Architecture**: Python-based, direct API access
- **Tools**: `list_projects`, `get_project_files`, `get_file`, `export_object`, `get_object_tree`, `search_object`
- **Scope**: Read-heavy, limited write capabilities. Best for inspection/export.

---

## 2. PRD Use Case to MCP Capability Mapping

### UC-1: Design-First (Penpot -> Code) — `/trim-pull`

| Requirement | Official MCP Support | zcube MCP Support | Assessment |
|------------|---------------------|-------------------|------------|
| Read component tree | `execute_code` + Plugin API | `get_page_shapes`, `query_shapes`, `get_shape_properties` | FULLY SUPPORTED by both |
| Read layout (flex/grid) | `execute_code` + Plugin API | `get_shape_properties` | SUPPORTED — Plugin API exposes flex/grid layout |
| Read styles (colors, typography, spacing) | `execute_code` + Plugin API | `get_shape_properties`, `query_shapes` (filter by color/font) | FULLY SUPPORTED by both |
| Read component hierarchy | `execute_code` + Plugin API | `list_components`, `get_object_tree` | FULLY SUPPORTED |
| Detect UI framework from code | N/A (code-side, not MCP) | N/A | Trim handles this, not MCP |

**Verdict**: UC-1 is fully feasible. Both MCP options provide sufficient read access.

### UC-2: Code-First (Code -> Penpot) — `/trim-push`

| Requirement | Official MCP Support | zcube MCP Support | Assessment |
|------------|---------------------|-------------------|------------|
| Create Penpot components | `execute_code` + `penpot.createBoard()`, etc. | `create_frame`, `create_rectangle`, `create_text`, `create_component` | FULLY SUPPORTED |
| Set layout properties | `execute_code` + Plugin API | `update_shape` | SUPPORTED — flex/grid via API |
| Set styles (colors, typography) | `execute_code` + Plugin API | `update_shape`, `create_text` (with styling) | SUPPORTED |
| Upload images/media | `import_image` | `upload_file_media`, `upload_file_media_from_url` | SUPPORTED |
| Register as component | `execute_code` | `create_component` | SUPPORTED |

**Verdict**: UC-2 is fully feasible. Creating structured Penpot components from code properties is well-supported.

### UC-3: Round-Trip Sync — Edit in Penpot, Sync Back

| Requirement | MCP Support | Assessment |
|------------|-------------|------------|
| Detect changes since last sync | Read component properties + compare against `.trim-components.json` timestamps | SUPPORTED — requires trim to implement diff logic |
| Surgical code updates (visual only) | N/A (code-side) | Trim agent handles this |

**Verdict**: UC-3 is feasible. It combines UC-1 read + trim-side diff logic. No new MCP capabilities needed beyond UC-1.

### UC-4: Drift Detection — `/trim-diff`

| Requirement | MCP Support | Assessment |
|------------|-------------|------------|
| Read current Penpot state | Same as UC-1 reads | FULLY SUPPORTED |
| Compare against code state | N/A (code-side) | Trim handles this |
| Categorize mismatches | N/A (trim logic) | Trim handles this |

**Verdict**: UC-4 is fully feasible. Pure read operations on Penpot side.

### UC-5: Component Library — `/trim-library`

| Requirement | Official MCP Support | zcube MCP Support | Assessment |
|------------|---------------------|-------------------|------------|
| List all components | `execute_code` | `list_components`, `search_components` | FULLY SUPPORTED |
| Get component metadata | `execute_code` | `get_shape_properties` | SUPPORTED |
| Sync drifted components | Combines UC-1 + UC-2 | Combines UC-1 + UC-2 | SUPPORTED |

**Verdict**: UC-5 is fully feasible. Leverages capabilities from UC-1 and UC-2.

### UC-6: Design Generation — `/trim-design`

| Requirement | Official MCP Support | zcube MCP Support | Assessment |
|------------|---------------------|-------------------|------------|
| Create new Penpot page/frame | `execute_code` | `add_page`, `create_frame` | SUPPORTED |
| Create components from scratch | `execute_code` | `create_*` tools + `create_component` | SUPPORTED |
| Apply existing design tokens | `execute_code` | `update_shape` | SUPPORTED |
| Reuse library components | `execute_code` | `list_components`, `instantiate_component` (planned) | PARTIALLY — instantiate is planned in zcube |

**Verdict**: UC-6 is feasible with the official MCP (via `execute_code`). The zcube server has a gap with `instantiate_component` being planned.

---

## 3. MCP Server Recommendation for Trim

### Recommended Approach: MCP-Agnostic

Trim should be **MCP-server-agnostic**. The PRD states (NFR-003): "All Penpot interactions MUST go through the Penpot MCP tools — no direct API calls." This means trim workflows should invoke MCP tools by name, and the user configures whichever MCP server they prefer.

However, the two server types have fundamentally different tool interfaces:
- **Official**: 5 tools, primarily `execute_code` (write JS code)
- **zcube**: 76+ discrete tools (`create_rectangle`, `update_shape`, etc.)

**Recommendation**: Trim workflows should use **agent steps** (not command steps) for all Penpot MCP interactions. The agent receives instructions about what to accomplish (e.g., "read the component tree from page X") and uses whichever MCP tools are available. This naturally adapts to either MCP server.

The workflow's **command steps** handle code-side operations (scan framework, read config, parse components), while **agent steps** handle Penpot-side operations via MCP tools.

### Setup Requirements

Regardless of which MCP server, the user needs:
1. A running Penpot instance (self-hosted or penpot.app)
2. An MCP server configured in their Claude Code MCP settings
3. For official MCP: Penpot open in browser with plugin loaded
4. For zcube: Penpot API access token configured

Trim should document both options and detect which MCP tools are available at runtime.

---

## 4. Limitations and Gaps

### L-1: Official MCP Requires Browser
The official Penpot MCP requires Penpot to be open in a browser tab with the plugin loaded. This means MCP interactions are limited to one file at a time and require the user to keep the browser/terminal open. Headless/CI workflows are not possible with the official MCP.

### L-2: `execute_code` Is Unpredictable
The official MCP's `execute_code` tool requires the LLM to generate correct JavaScript for the Plugin API. This is powerful but less deterministic than discrete tools. Token cost is higher, and failure modes are harder to debug.

### L-3: Component Instantiation (zcube)
The zcube server's `instantiate_component` tool is listed as "planned" (not yet implemented). This affects UC-6 (reusing library components in generated designs). Workaround: duplicate the component shape tree manually.

### L-4: No Design Versioning via MCP
Neither MCP server exposes design version history. Trim cannot query "what changed in Penpot since timestamp X." Drift detection (UC-4) must compare full current state against the last-known state stored in `.trim-components.json`, not incremental changes.

### L-5: Style Token Extraction
While the Plugin API supports design tokens, extracting a complete token set (all colors, typography scales, spacing values) in a structured format requires custom `execute_code` scripts. This is doable but requires careful prompt engineering in agent steps.

### L-6: Remote MCP Not Production-Ready
The official remote MCP (no local server needed) is currently in testing only and "not available yet in Penpot production." Users must run local MCP for now.

### L-7: Single-Tab Limitation
The official MCP "can only be active in one browser tab at a time." This prevents parallel operations on multiple Penpot files.

---

## 5. Descoping Recommendations

Based on the research, **no PRD features need to be fully descoped**. All six use cases are feasible with available MCP tools. However, the following should be noted:

1. **FR-017** (`/trim-library sync` with last-modified-wins): Penpot MCP does not expose modification timestamps per component. The sync direction logic may need to rely solely on git history for the code side and treat Penpot state as "current" without historical comparison. Alternative: store a snapshot hash at sync time and compare against current.

2. **FR-019/FR-020** (reuse existing components in design generation): Fully supported by official MCP via `execute_code`. The zcube `instantiate_component` gap can be worked around.

3. **Framework detection** (FR-005): This is code-side logic, not MCP-dependent. Heuristic detection of React/Vue/Svelte/HTML is straightforward for command steps.

---

## 6. Architecture Implications for Trim Workflows

Based on MCP capabilities, trim workflows should follow this pattern:

```
trim-pull workflow:
  Step 1 (command): Read .trim-config, detect framework, scan existing components
  Step 2 (agent):   Read Penpot design via MCP tools, extract component tree/styles/layout
  Step 3 (agent):   Generate framework-appropriate code from Penpot data, update .trim-components.json

trim-push workflow:
  Step 1 (command): Scan code components, extract visual properties, read .trim-config
  Step 2 (agent):   Create/update Penpot components via MCP tools
  Step 3 (command): Update .trim-components.json with new mappings

trim-diff workflow:
  Step 1 (command): Read .trim-components.json, scan code component state
  Step 2 (agent):   Read current Penpot component state via MCP tools
  Step 3 (agent):   Compare and generate drift report

trim-design workflow:
  Step 1 (command): Read PRD, existing components, project conventions
  Step 2 (agent):   Generate Penpot design via MCP tools using product context
  Step 3 (command): Update .trim-components.json with new component mappings
```

This pattern aligns with PRD FR-021 (command-first/agent-second) and ensures MCP interactions are confined to agent steps where the LLM can adapt to whichever MCP tools are available.
