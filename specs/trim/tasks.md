# Tasks: Trim — Bidirectional Design-Code Sync Plugin

**Input**: Design documents from `/specs/trim/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: No test suite — this is a Claude Code plugin (markdown/bash/JSON). Testing is done by running skills on consumer projects.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Plugin Scaffold)

**Purpose**: Create the plugin directory structure and package manifests

- [X] T001 Create plugin manifest at `plugin-trim/.claude-plugin/plugin.json` with name "trim", version "000.000.000.000", and description per contracts/interfaces.md
- [X] T002 Create marketplace config at `plugin-trim/.claude-plugin/marketplace.json` with distribution settings
- [X] T003 Create npm package at `plugin-trim/package.json` with name "@yoshisada/trim" per contracts/interfaces.md
- [X] T004 [P] Create config template at `plugin-trim/templates/trim-config.tpl` with placeholder key-value pairs and comments
- [X] T005 [P] Create component mapping template at `plugin-trim/templates/trim-components.tpl` with empty JSON array `[]`

**Checkpoint**: Plugin scaffold exists with manifest, package.json, and templates. No skills or workflows yet.

---

## Phase 2: Foundational — Configuration Skill (US6, Priority P1)

**Purpose**: The config skill is a prerequisite for all other skills. Must be complete before any sync operation.

**Goal**: Developer can run `/trim-config` to connect their project to a Penpot project.

**Independent Test**: Run `/trim-config` in a fresh project, provide Penpot IDs, verify `.trim-config` is created.

- [ ] T006 [US6] Create configuration skill at `plugin-trim/skills/trim-config/SKILL.md` — reads/creates `.trim-config`, prompts for penpot_project_id and penpot_file_id, sets defaults for optional fields, initializes empty `.trim-components.json` if missing. Per FR-025, FR-026, FR-002, FR-003.

**Checkpoint**: `/trim-config` is runnable and creates valid `.trim-config` and `.trim-components.json` files.

---

## Phase 3: User Story 1 — Pull Design into Code (Priority: P1) MVP

**Goal**: Developer runs `/trim-pull` and gets framework-appropriate code from a Penpot design.

**Independent Test**: Create a Penpot component, run `/trim-pull`, verify generated code matches the design's layout in the detected framework.

### Workflow

- [ ] T007 [US1] Create trim-pull wheel workflow at `plugin-trim/workflows/trim-pull.json` with 6 steps: read-config (command), detect-framework (command), read-mappings (command), resolve-trim-plugin (command), pull-design (agent), update-mappings (command). All command step scripts per contracts/interfaces.md. Agent step instruction: read Penpot design via MCP, generate framework-appropriate code, reuse existing components from mappings. Per FR-004, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012.

### Skill

- [ ] T008 [US1] Create trim-pull skill at `plugin-trim/skills/trim-pull/SKILL.md` — accepts optional page/component name as argument, delegates to `/wheel-run trim:trim-pull`, reports generated files and updated mappings. Per FR-008.

**Checkpoint**: `/trim-pull` runs the wheel workflow, reads Penpot via MCP, generates code, and updates `.trim-components.json`.

---

## Phase 4: User Story 2 — Push Code to Penpot (Priority: P2)

**Goal**: Developer runs `/trim-push` and code components are created/updated in Penpot.

**Independent Test**: Have a UI component in code, run `/trim-push`, verify matching Penpot component exists.

### Workflow

- [ ] T009 [US2] Create trim-push wheel workflow at `plugin-trim/workflows/trim-push.json` with 7 steps: read-config (command), detect-framework (command), scan-components (command), read-mappings (command), resolve-trim-plugin (command), push-to-penpot (agent), update-mappings (command). Scan-components command detects UI component files by framework convention. Agent step creates/updates Penpot components via MCP. Per FR-004, FR-006, FR-007, FR-013, FR-014, FR-015, FR-016.

### Skill

- [ ] T010 [US2] Create trim-push skill at `plugin-trim/skills/trim-push/SKILL.md` — accepts optional component path/glob as argument, delegates to `/wheel-run trim:trim-push`, reports pushed components and updated mappings. Per FR-013.

**Checkpoint**: `/trim-push` scans code components, creates Penpot components via MCP, and updates `.trim-components.json`.

---

## Phase 5: User Story 3 — Detect Drift (Priority: P2)

**Goal**: Developer runs `/trim-diff` and gets a categorized drift report with actionable suggestions.

**Independent Test**: Pull a design, manually change code, run `/trim-diff`, verify report identifies the change.

### Workflow

- [ ] T011 [US3] Create trim-diff wheel workflow at `plugin-trim/workflows/trim-diff.json` with 5 steps: read-config (command), read-mappings (command), scan-components (command), resolve-trim-plugin (command), generate-diff (agent, terminal). Agent step compares Penpot state vs code for each tracked component, categorizes mismatches (code-only, design-only, style-divergence, layout-difference), suggests pull/push/manual-review. Per FR-004, FR-006, FR-007, FR-017, FR-018, FR-019.

### Skill

- [ ] T012 [US3] Create trim-diff skill at `plugin-trim/skills/trim-diff/SKILL.md` — accepts optional component name as argument, delegates to `/wheel-run trim:trim-diff`, displays drift report. Per FR-017.

**Checkpoint**: `/trim-diff` compares Penpot and code, produces a categorized drift report with suggestions.

---

## Phase 6: User Story 4 — Component Library Management (Priority: P3)

**Goal**: Developer runs `/trim-library` to see sync status, or `/trim-library sync` to auto-sync drifted components.

**Independent Test**: Set up tracked components in `.trim-components.json`, run `/trim-library`, verify status display.

### Workflow (sync mode only)

- [ ] T013 [US4] Create trim-library-sync wheel workflow at `plugin-trim/workflows/trim-library-sync.json` with 7 steps: read-config (command), read-mappings (command), detect-framework (command), check-git-timestamps (command), resolve-trim-plugin (command), sync-components (agent), update-mappings (command). Check-git-timestamps gets last git modification for each tracked code path. Agent determines sync direction per component and syncs via Penpot MCP. Per FR-004, FR-006, FR-007, FR-021.

### Skill

- [ ] T014 [US4] Create trim-library skill at `plugin-trim/skills/trim-library/SKILL.md` — list mode (no args): reads `.trim-components.json` inline, displays table with component name, code path, Penpot name, sync status, last synced. Sync mode (`sync` arg): delegates to `/wheel-run trim:trim-library-sync`. Per FR-020, FR-021.

**Checkpoint**: `/trim-library` lists component status; `/trim-library sync` auto-syncs drifted components.

---

## Phase 7: User Story 5 — Design Generation (Priority: P3)

**Goal**: Developer runs `/trim-design` with product context and gets an initial Penpot design.

**Independent Test**: Provide a simple PRD, run `/trim-design`, verify a Penpot page is created with appropriate components.

### Workflow

- [ ] T015 [US5] Create trim-design wheel workflow at `plugin-trim/workflows/trim-design.json` with 7 steps: read-config (command), read-mappings (command), detect-framework (command), read-product-context (command), resolve-trim-plugin (command), generate-design (agent), update-mappings (command). Read-product-context gathers PRDs, conventions, existing component names. Agent creates Penpot design via MCP reusing existing library components. Per FR-004, FR-006, FR-007, FR-022, FR-023, FR-024.

### Skill

- [ ] T016 [US5] Create trim-design skill at `plugin-trim/skills/trim-design/SKILL.md` — accepts description or PRD path as argument, delegates to `/wheel-run trim:trim-design`, reports created design and new mappings. Per FR-022.

**Checkpoint**: `/trim-design` generates a Penpot design informed by product context and existing components.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T017 [P] Verify all 6 skills have correct frontmatter (name, description) matching contracts/interfaces.md
- [ ] T018 [P] Verify all 5 workflows have correct structure (name, version, steps) and all step outputs write to `.wheel/outputs/`
- [ ] T019 Verify plugin.json version matches package.json version and both match VERSION file pattern

**Checkpoint**: All skills discoverable, all workflows valid, manifests consistent.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — can start immediately
- **Phase 2 (Config)**: Depends on Phase 1 — BLOCKS all user stories (config is prerequisite)
- **Phase 3 (Pull)**: Depends on Phase 2 — MVP skill
- **Phase 4 (Push)**: Depends on Phase 2 — can run in parallel with Phase 3
- **Phase 5 (Diff)**: Depends on Phase 2 — can run in parallel with Phases 3-4
- **Phase 6 (Library)**: Depends on Phase 2 — can run in parallel with Phases 3-5
- **Phase 7 (Design)**: Depends on Phase 2 — can run in parallel with Phases 3-6
- **Phase 8 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US6 Config (P1)**: Foundation — all other stories depend on this
- **US1 Pull (P1)**: Depends only on config — primary MVP
- **US2 Push (P2)**: Depends only on config — independent of pull
- **US3 Diff (P2)**: Depends only on config — independent of pull/push
- **US4 Library (P3)**: Depends only on config — benefits from pull/push populating mappings
- **US5 Design (P3)**: Depends only on config — benefits from library being populated

### Parallel Opportunities

- T004 and T005 (templates) can run in parallel
- Phases 3-7 (all user stories) can run in parallel after Phase 2 completes
- T017, T018 (polish verification) can run in parallel

---

## Implementation Strategy

### MVP First (Config + Pull)

1. Complete Phase 1: Setup scaffold
2. Complete Phase 2: Config skill (US6)
3. Complete Phase 3: Pull skill + workflow (US1)
4. Verify: `/trim-config` creates config, `/trim-pull` generates code from Penpot
5. MVP is deployable

### Incremental Delivery

1. Setup + Config → Foundation ready
2. Add Pull (US1) → Design-first flow works (MVP)
3. Add Push (US2) → Code-first flow works
4. Add Diff (US3) → Drift detection works
5. Add Library (US4) → Library management works
6. Add Design (US5) → Design generation works
7. Each story adds value without breaking previous stories

---

## Notes

- All file paths are relative to `plugin-trim/` unless otherwise noted
- No test tasks — plugin is markdown/bash/JSON, tested by running on consumer projects
- Each skill SKILL.md must match the frontmatter defined in contracts/interfaces.md
- Each workflow JSON must match the step structure defined in contracts/interfaces.md
- Commit after each completed phase
