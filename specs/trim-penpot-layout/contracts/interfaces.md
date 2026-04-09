# Interface Contracts: Trim Penpot Layout & Auto-Flows

**Date**: 2026-04-09

These contracts define the exact changes to make in each workflow JSON file and skill SKILL.md file. Each contract specifies which file, which field, and what text to add or modify.

---

## Contract 1: Positioning Instructions (all Penpot-creating agent steps)

**Applies to**: Every agent step with `"type": "agent"` whose instruction involves creating Penpot elements.

**Change**: Prepend the following positioning block to the agent instruction text:

```
POSITIONING RULES (apply to ALL Penpot element creation):
- Before creating any frame, read all existing frames on the current page via MCP to get their bounding boxes (x, y, width, height).
- Calculate the new frame's position: x = rightmost_existing_frame.x + rightmost_existing_frame.width + 40, y = 0 for top-level frames.
- If placing variants/states of a frame, position them vertically: y = primary_frame.y + primary_frame.height + 40, same x as primary.
- If this is the first frame on the page, position at x=0, y=0.
- Minimum gap between any two frames: 40px in both x and y directions.
- Never position a frame at (0,0) if other frames already exist on the page.
```

**Affected files**:
| File | Step ID |
|------|---------|
| trim-push.json | push-to-penpot |
| trim-pull.json | pull-design |
| trim-design.json | generate-design |
| trim-redesign.json | generate-redesign |
| trim-edit.json | apply-edit |
| trim-library-sync.json | sync-components |

---

## Contract 2: Page Separation Instructions (push and design agent steps)

**Applies to**: Agent steps in trim-push.json and trim-design.json that create page-level designs.

**Change**: Add the following page separation block to the agent instruction text:

```
PAGE SEPARATION RULES:
- Each application page/route MUST get its own dedicated Penpot page.
- Before creating page-level frames, check if a Penpot page already exists for this route. If yes, use it. If no, create a new Penpot page named after the route.
- Do NOT place multiple page designs on the same Penpot page.
- Component-level elements (not full pages) go on the "Components" page, not on route pages.
```

**Affected files**:
| File | Step ID |
|------|---------|
| trim-push.json | push-to-penpot |
| trim-design.json | generate-design |

---

## Contract 3: Components Page with Bento Grid (push and design agent steps)

**Applies to**: Agent steps in trim-push.json and trim-design.json.

**Change**: Add the following Components page block to the agent instruction text:

```
COMPONENTS PAGE RULES:
- Create (or update) a Penpot page named "Components" for the component library.
- Group components by category. Infer categories from directory structure (e.g., components/buttons/ → "Buttons"). If flat directory, group alphabetically.
- For each category group:
  a. Create a text element as a header label (e.g., "Buttons", "Inputs", "Cards") at the top of the group area.
  b. Arrange components in a grid below the header: fixed column width of 300px, 20px gap between items, wrap to new rows when exceeding 1200px total width.
  c. Each component is displayed inside a labeled card frame (component name as text label above the component frame).
- When updating an existing Components page: keep existing component positions, append new components to the end of their category group.
- Position category groups vertically with 60px gap between groups.
```

**Affected files**:
| File | Step ID |
|------|---------|
| trim-push.json | push-to-penpot |
| trim-design.json | generate-design |

---

## Contract 4: Auto-Flow Discovery — Push (new step in trim-push.json)

**Change**: Add a new agent step `discover-flows` between `push-to-penpot` and `update-mappings` in trim-push.json.

```json
{
  "id": "discover-flows",
  "type": "agent",
  "instruction": "<see instruction text below>",
  "context_from": ["detect-framework", "scan-components", "read-config"],
  "output": ".wheel/outputs/trim-discover-flows-push.txt"
}
```

**Instruction text**:
```
Auto-discover user flows from the codebase and merge into .trim/flows.json.

1. Read the framework detection output to determine the routing approach:
   - React: scan for react-router Route definitions, Link/NavLink components
   - Next.js: scan app/ or pages/ directory structure for file-based routes
   - Vue: scan for vue-router route definitions
   - Svelte: scan src/routes/ directory structure
   - HTML: scan for <a href> links between pages
2. Read the scanned components list from context.
3. For each discovered route, identify navigation links/calls that connect to other routes.
4. Build flow objects from connected routes:
   - Each flow represents a user journey through 2+ connected pages
   - Flow name: descriptive (e.g., "main-navigation", "auth-flow", "checkout-flow")
   - Each step: action="navigate", target=route path, page=route path, component=page component name
5. Read existing .trim/flows.json (or start with empty array if not found).
6. Merge rules:
   - If an auto-discovered flow has the same name as an existing flow with "source": "manual", SKIP IT.
   - If an auto-discovered flow has the same name as an existing "auto-discovered" flow, REPLACE it (re-scan updates).
   - All new flows get "source": "auto-discovered".
7. Write the merged flows array to .trim/flows.json with 2-space indentation.
8. Report: discovered N flows with M total steps, merged with K existing flows.
```

---

## Contract 5: Auto-Flow Discovery — Pull (new step in trim-pull.json)

**Change**: Add a new agent step `discover-flows` between `pull-design` and `update-mappings` in trim-pull.json.

```json
{
  "id": "discover-flows",
  "type": "agent",
  "instruction": "<see instruction text below>",
  "context_from": ["read-config", "resolve-trim-plugin"],
  "output": ".wheel/outputs/trim-discover-flows-pull.txt"
}
```

**Instruction text**:
```
Auto-discover user flows from Penpot page organization and merge into .trim/flows.json.

1. Read the config output to get penpot_file_id.
2. Use Penpot MCP tools to list all pages in the file and their frame structure.
3. Infer flows from page organization:
   - Page ordering suggests a primary navigation flow
   - Pages with related names (e.g., "Login", "Dashboard", "Settings") suggest a user journey
   - Linked or connected frames within pages suggest sub-flows
4. Build flow objects:
   - Flow name: descriptive based on page sequence (e.g., "main-navigation", "onboarding-flow")
   - Each step: action="navigate", target=page name, page=inferred route, component=null, penpot_frame_id=frame ID from Penpot
5. Read existing .trim/flows.json (or start with empty array if not found).
6. Merge rules:
   - If an auto-discovered flow has the same name as an existing flow with "source": "manual", SKIP IT.
   - If an auto-discovered flow has the same name as an existing "auto-discovered" flow, REPLACE it.
   - All new flows get "source": "auto-discovered".
7. Write the merged flows array to .trim/flows.json with 2-space indentation.
8. Report: discovered N flows, merged with K existing flows.
```

---

## Contract 6: Auto-Flow Discovery — Design (new step in trim-design.json)

**Change**: Add a new agent step `discover-flows` between `generate-design` and `update-mappings` in trim-design.json.

```json
{
  "id": "discover-flows",
  "type": "agent",
  "instruction": "<see instruction text below>",
  "context_from": ["read-product-context", "read-config"],
  "output": ".wheel/outputs/trim-discover-flows-design.txt"
}
```

**Instruction text**:
```
Auto-discover user flows from PRD context and merge into .trim/flows.json.

1. Read the product context output which contains PRD content.
2. Extract user journeys, user stories, and flow descriptions from the PRD:
   - Look for user story sections, acceptance scenarios, workflow descriptions
   - Identify sequences of pages/screens the user navigates through
   - Map PRD requirements to navigation paths
3. Build flow objects from PRD journeys:
   - Flow name: derived from the user story or journey name
   - Description: from the PRD user story text
   - Each step: action="navigate", target=page/screen name from PRD, page=inferred route, component=null
4. Read existing .trim/flows.json (or start with empty array if not found).
5. Merge rules:
   - If an auto-discovered flow has the same name as an existing flow with "source": "manual", SKIP IT.
   - If an auto-discovered flow has the same name as an existing "auto-discovered" flow, REPLACE it.
   - All new flows get "source": "auto-discovered".
6. Write the merged flows array to .trim/flows.json with 2-space indentation.
7. Report: discovered N flows from PRD, merged with K existing flows.
```

---

## Contract 7: Skill SKILL.md Report Updates

**trim-push/SKILL.md**: Add to the report template:
```
  Components Page: {created | updated} with {N} component groups
  Flows Discovered: {N} flows with {M} steps written to .trim/flows.json
```

**trim-pull/SKILL.md**: Add to the report template:
```
  Flows Discovered: {N} flows inferred from Penpot pages, written to .trim/flows.json
```

**trim-design/SKILL.md**: Add to the report template:
```
  Components Page: {created | updated} with {N} component groups
  Flows Discovered: {N} flows from PRD context, written to .trim/flows.json
```
