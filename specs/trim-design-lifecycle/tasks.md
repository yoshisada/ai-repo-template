# Tasks: Trim Design Lifecycle

**Input**: Design documents from `specs/trim-design-lifecycle/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not applicable — this is a plugin source repo. Deliverables are markdown skills and JSON workflows, not application code.

**Organization**: Tasks are grouped by user story to enable independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

All deliverables go into `plugin-trim/`:
- Skills: `plugin-trim/skills/<name>/SKILL.md`
- Workflows: `plugin-trim/workflows/<name>.json`
- Manifest: `plugin-trim/.claude-plugin/plugin.json`
- Package: `plugin-trim/package.json`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ensure plugin-trim/ directory structure exists with skills/ and workflows/ directories

- [ ] T001 Create directory structure: `plugin-trim/skills/trim-edit/`, `plugin-trim/skills/trim-verify/`, `plugin-trim/skills/trim-redesign/`, `plugin-trim/skills/trim-flows/`, `plugin-trim/workflows/`
- [ ] T002 Verify `plugin-trim/.claude-plugin/plugin.json` exists and read current skill registrations
- [ ] T003 Verify `plugin-trim/package.json` exists and read current version

**Checkpoint**: Plugin directory structure ready for skill and workflow creation.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational blocking tasks — each skill/workflow is self-contained. User stories can begin immediately after setup.

**Checkpoint**: Setup complete — proceed to user stories.

---

## Phase 3: User Story 1 — Natural Language Design Editing (Priority: P1)

**Goal**: Developer runs `/trim-edit "description"` and the Penpot design is updated with the change logged to `.trim-changes.md`.

**Independent Test**: Run `/trim-edit "make the header blue"` in a consumer project with Penpot MCP. Verify Penpot design changed and `.trim-changes.md` has a new entry.

### Implementation for User Story 1

- [ ] T004 [US1] Create `/trim-edit` skill at `plugin-trim/skills/trim-edit/SKILL.md` — frontmatter (name: trim-edit, description), input validation ($ARGUMENTS required), delegates to `trim-edit` wheel workflow, post-workflow reminder that changes stay in Penpot only. Follow pattern from `plugin-shelf/skills/shelf-sync/SKILL.md`. References FR-001, FR-004.
- [ ] T005 [US1] Create `trim-edit` workflow at `plugin-trim/workflows/trim-edit.json` — 4 steps: resolve-trim-plugin (command: scan installed_plugins.json, fall back to plugin-trim/), read-design-state (command: read .trim-components.json and .trim-config), apply-edit (agent: interpret description, read Penpot via MCP, apply targeted changes), log-change (agent: append entry to .trim-changes.md with timestamp/request/changes/frames). Follow pattern from `plugin-shelf/workflows/shelf-create.json`. References FR-001 through FR-006, FR-025 through FR-027.

**Checkpoint**: `/trim-edit` skill and workflow are complete. A developer can make natural language Penpot edits with changelog tracking.

---

## Phase 4: User Story 2 — User Flow Management (Priority: P2)

**Goal**: Developer manages user flows in `.trim-flows.json` via `/trim-flows add|list|sync|export-tests`.

**Independent Test**: Run `/trim-flows add "login"`, define steps, then `/trim-flows list` to verify. Run `/trim-flows export-tests` to generate Playwright stubs.

### Implementation for User Story 2

- [ ] T006 [US2] Create `/trim-flows` skill at `plugin-trim/skills/trim-flows/SKILL.md` — frontmatter (name: trim-flows, description), parse $ARGUMENTS for subcommand (add, list, sync, export-tests), implement each subcommand inline: add (interactive flow definition, write to .trim-flows.json per schema in data-model.md), list (read .trim-flows.json, display formatted table with name/step count/last_verified), sync (map flow steps to Penpot frames via MCP and code routes), export-tests (generate Playwright test stubs, one test per flow, one step per assertion). References FR-018 through FR-024.

**Checkpoint**: `/trim-flows` skill is complete. Flows can be added, listed, synced to Penpot, and exported as test stubs.

---

## Phase 5: User Story 3 — Visual Verification (Priority: P3)

**Goal**: Developer runs `/trim-verify` to visually compare rendered code against Penpot designs for all tracked flows.

**Independent Test**: Define a flow with `/trim-flows add`, start a dev server, run `/trim-verify`, check `.trim-verify-report.md` has per-step pass/fail results.

### Implementation for User Story 3

- [ ] T007 [US3] Create `/trim-verify` skill at `plugin-trim/skills/trim-verify/SKILL.md` — frontmatter (name: trim-verify, description), check .trim-flows.json exists and has flows, optional $ARGUMENTS for specific flow name, delegates to `trim-verify` wheel workflow, reports results. References FR-007, FR-008.
- [ ] T008 [US3] Create `trim-verify` workflow at `plugin-trim/workflows/trim-verify.json` — 5 steps: resolve-trim-plugin (command), read-flows (command: read .trim-flows.json, validate), capture-screenshots (agent: walk each flow in Playwright headless or /chrome, screenshot each step, fetch Penpot frames via MCP), compare-visuals (agent: Claude vision comparison, identify layout/color/typography/spacing mismatches), write-report (agent: generate .trim-verify-report.md per report schema in data-model.md, update last_verified in .trim-flows.json, store screenshots in .trim-verify/). References FR-007 through FR-012, FR-025 through FR-027.

**Checkpoint**: `/trim-verify` skill and workflow are complete. Visual verification walks flows and reports mismatches.

---

## Phase 6: User Story 4 — Full UI Redesign (Priority: P4)

**Goal**: Developer runs `/trim-redesign "context"` and gets a complete new Penpot design preserving information architecture.

**Independent Test**: Run `/trim-redesign "dark theme"` in a consumer project. Verify Penpot design was updated and `.trim-changes.md` has a comprehensive redesign entry.

### Implementation for User Story 4

- [ ] T009 [US4] Create `/trim-redesign` skill at `plugin-trim/skills/trim-redesign/SKILL.md` — frontmatter (name: trim-redesign, description), optional $ARGUMENTS as context/direction, delegates to `trim-redesign` wheel workflow, post-workflow reminder that changes stay in Penpot only. References FR-013, FR-017.
- [ ] T010 [US4] Create `trim-redesign` workflow at `plugin-trim/workflows/trim-redesign.json` — 5 steps: resolve-trim-plugin (command), gather-context (command: read PRD, .trim-components.json, .trim-flows.json, .trim-config), read-current-design (agent: fetch current Penpot design state via MCP), generate-redesign (agent: reimagine visual design preserving IA — pages/nav/flows, apply to Penpot via MCP), log-changes (agent: append comprehensive redesign entry to .trim-changes.md with rationale). References FR-013 through FR-017, FR-025 through FR-027.

**Checkpoint**: `/trim-redesign` skill and workflow are complete. Full UI redesign capability with changelog.

---

## Phase 7: User Story 5 — QA Integration (Priority: P5)

**Goal**: QA engineer can generate Playwright E2E test stubs from `.trim-flows.json`.

**Independent Test**: Already covered by `/trim-flows export-tests` in Phase 4 (T006).

### Implementation for User Story 5

No additional tasks — QA integration is fully delivered by the `export-tests` subcommand in T006.

**Checkpoint**: QA integration works via `/trim-flows export-tests`.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Plugin manifest registration and version bump

- [ ] T011 [P] Update `plugin-trim/.claude-plugin/plugin.json` to register 4 new skills (trim-edit, trim-verify, trim-redesign, trim-flows) with name, description, and path fields per contracts/interfaces.md
- [ ] T012 [P] Update `plugin-trim/package.json` to bump version reflecting new skills added

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: No blocking tasks
- **User Stories (Phase 3-7)**: Depend on Setup (Phase 1) only
  - US1 (/trim-edit): Independent — can start after setup
  - US2 (/trim-flows): Independent — can start after setup
  - US3 (/trim-verify): Depends on US2 (/trim-flows must exist for flow-driven verification)
  - US4 (/trim-redesign): Independent — can start after setup
  - US5 (QA Integration): Delivered by US2
- **Polish (Phase 8)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: No dependencies on other stories
- **US2 (P2)**: No dependencies on other stories
- **US3 (P3)**: Depends on US2 (needs `.trim-flows.json` and `/trim-flows` to exist)
- **US4 (P4)**: No dependencies on other stories
- **US5 (P5)**: Fully delivered by US2

### Within Each User Story

- Skill SKILL.md before workflow JSON (skill references the workflow name)
- Workflow JSON references outputs from the skill

### Parallel Opportunities

- T004 (US1 skill) and T006 (US2 skill) and T009 (US4 skill) can run in parallel
- T005 (US1 workflow) and T009 (US4 skill) can run in parallel
- T011 and T012 (manifest + package) can run in parallel

---

## Parallel Example: Phase 3-6 Kickoff

```bash
# After setup, these can start simultaneously:
Task T004: "Create /trim-edit skill at plugin-trim/skills/trim-edit/SKILL.md"
Task T006: "Create /trim-flows skill at plugin-trim/skills/trim-flows/SKILL.md"
Task T009: "Create /trim-redesign skill at plugin-trim/skills/trim-redesign/SKILL.md"

# After T004 completes:
Task T005: "Create trim-edit workflow at plugin-trim/workflows/trim-edit.json"

# After T006 completes:
Task T007: "Create /trim-verify skill at plugin-trim/skills/trim-verify/SKILL.md"
Task T008: "Create trim-verify workflow at plugin-trim/workflows/trim-verify.json"

# After T009 completes:
Task T010: "Create trim-redesign workflow at plugin-trim/workflows/trim-redesign.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 3: /trim-edit skill + workflow (T004-T005)
3. Developers can now make natural language Penpot edits with changelog

### Incremental Delivery

1. Setup → T001-T003
2. /trim-edit → T004-T005 (natural language editing)
3. /trim-flows → T006 (flow management + QA integration)
4. /trim-verify → T007-T008 (visual verification)
5. /trim-redesign → T009-T010 (full redesign)
6. Polish → T011-T012 (manifest + version)

---

## Notes

- All deliverables are markdown (skills) and JSON (workflows) — no compiled code
- Each skill follows the pattern in `plugin-shelf/skills/shelf-sync/SKILL.md`
- Each workflow follows the pattern in `plugin-shelf/workflows/shelf-create.json`
- Commit after each completed phase
- The `/trim-flows` skill handles all subcommands inline — no workflow needed
