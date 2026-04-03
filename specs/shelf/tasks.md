# Tasks: Shelf

**Input**: Design documents from `specs/shelf/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md (required)

## Phase 1: Setup — Plugin Scaffolding

**Purpose**: Create the plugin directory structure and package files

- [X] T001 Create `plugin-shelf/package.json` with name `@yoshisada/shelf`, version from VERSION file, and description matching plugin.json
- [X] T002 [P] Create skill directories: `plugin-shelf/skills/shelf-create/`, `shelf-update/`, `shelf-sync/`, `shelf-feedback/`, `shelf-status/`, `shelf-release/`

**Checkpoint**: Plugin directory structure ready for skill files

---

## Phase 2: User Story 1 — Scaffold New Project (/shelf-create) (Priority: P1)

**Goal**: User runs `/shelf-create` and gets a complete Obsidian project structure with auto-detected tags

**Independent Test**: Run `/shelf-create` in a repo and verify all files/directories created in Obsidian via MCP

### Implementation

- [X] T003 [US1] Write `plugin-shelf/skills/shelf-create/SKILL.md` — full skill definition covering: slug resolution (FR-004), duplicate check (FR-005), tech stack detection (FR-029), `--tags` merge (FR-030), dashboard creation with frontmatter (FR-002), about.md creation (FR-003), directory scaffolding (FR-001), MCP-only writes (FR-006), graceful degradation (NFR-004)

**Checkpoint**: `/shelf-create` produces complete Obsidian project structure

---

## Phase 3: User Story 2 — Push Progress Update (/shelf-update) (Priority: P1)

**Goal**: User runs `/shelf-update` and progress + status + decisions are recorded in Obsidian

**Independent Test**: Run `/shelf-update --summary "test" --status "in-progress"` and verify progress entry appended and frontmatter updated

### Implementation

- [X] T004 [US2] Write `plugin-shelf/skills/shelf-update/SKILL.md` — full skill definition covering: read-before-write (FR-012), interactive prompting (FR-011), monthly file creation (FR-008), progress entry append (FR-007), decision record creation (FR-031, FR-032, FR-033), dashboard frontmatter update (FR-009), Human Needed section update (FR-010), graceful degradation (NFR-004)

**Checkpoint**: `/shelf-update` records session work in Obsidian

---

## Phase 4: User Story 3 — Sync Issues (/shelf-sync) (Priority: P1)

**Goal**: User runs `/shelf-sync` and all GitHub issues + backlog items are reflected as Obsidian notes

**Independent Test**: Create a GitHub issue, add a `.kiln/issues/` file, run `/shelf-sync`, verify Obsidian notes exist

### Implementation

- [X] T005 [US3] Write `plugin-shelf/skills/shelf-sync/SKILL.md` — full skill definition covering: GitHub issue fetch via `gh` (FR-013), backlog read from `.kiln/issues/` (FR-014), frontmatter with type/status/severity/source/last_synced (FR-015), closed issue handling (FR-016), skip-unchanged logic (FR-017), slug filename generation (FR-018), graceful degradation (NFR-004)

**Checkpoint**: `/shelf-sync` mirrors all issues into Obsidian

---

## Phase 5: User Story 4 — Read Feedback (/shelf-feedback) (Priority: P2)

**Goal**: User runs `/shelf-feedback` at session start and sees any Obsidian feedback with suggested actions

**Independent Test**: Add feedback to Obsidian dashboard, run `/shelf-feedback`, verify items displayed and archived

### Implementation

- [X] T006 [US4] Write `plugin-shelf/skills/shelf-feedback/SKILL.md` — full skill definition covering: project existence check (FR-022), Feedback section extraction (FR-019), action suggestion (FR-020), archive to Feedback Log with timestamp (FR-021), empty feedback handling (FR-023), graceful degradation (NFR-004)

**Checkpoint**: `/shelf-feedback` reads and archives feedback from Obsidian

---

## Phase 6: User Story 5 — Quick Status View (/shelf-status) (Priority: P2)

**Goal**: User runs `/shelf-status` and sees a formatted project summary without modifying anything

**Independent Test**: Run `/shelf-status` after populating project data, verify read-only summary output

### Implementation

- [ ] T007 [US5] Write `plugin-shelf/skills/shelf-status/SKILL.md` — full skill definition covering: project existence check (FR-028), frontmatter display (FR-024), latest progress entry (FR-025), open issue count (FR-026), Human Needed items (FR-027), graceful degradation (NFR-004)

**Checkpoint**: `/shelf-status` displays complete read-only project summary

---

## Phase 7: User Story 6 — Record Release (/shelf-release) (Priority: P2)

**Goal**: User runs `/shelf-release` and a release note with changelog is created plus a progress entry

**Independent Test**: Run `/shelf-release` after tagging a version, verify release note and progress entry in Obsidian

### Implementation

- [ ] T008 [US6] Write `plugin-shelf/skills/shelf-release/SKILL.md` — full skill definition covering: version detection (FR-035), duplicate check (FR-038), changelog from git log (FR-036), summary prompt (FR-037), release note creation (FR-034), progress entry append (FR-039), graceful degradation (NFR-004)

**Checkpoint**: `/shelf-release` creates release note with auto-generated changelog

---

## Phase 8: Polish & Packaging

**Purpose**: Final packaging and manifest updates

- [ ] T009 Verify `plugin-shelf/.claude-plugin/plugin.json` has correct name, version, and description
- [ ] T010 [P] Verify all 6 SKILL.md files reference the correct FR IDs in their instructions
- [ ] T011 [P] Verify all SKILL.md files include the shared slug resolution, base path, and graceful degradation patterns from contracts/interfaces.md

**Checkpoint**: Plugin is complete and ready for publishing

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **User Stories (Phases 2-7)**: Depend on Phase 1 for directory structure
  - Phases 2-7 can proceed in parallel (each skill is a standalone SKILL.md file)
  - Or sequentially in priority order (P1: create, update, sync → P2: feedback, status, release)
- **Polish (Phase 8)**: Depends on all skill files being written

### Parallel Opportunities

- T001 and T002 can run in parallel (package.json vs directories)
- T003 through T008 can ALL run in parallel (each writes to a different SKILL.md file)
- T009, T010, T011 can run in parallel (each is a verification pass)

## Implementation Strategy

### MVP First (Phase 1 + Phase 2)

1. Complete Phase 1: Plugin scaffolding
2. Complete Phase 2: `/shelf-create` — the foundational command
3. Validate: run `/shelf-create` against a real vault
4. Proceed to remaining skills

### Incremental Delivery

1. Phase 1: Scaffolding (T001-T002)
2. Phase 2: `/shelf-create` (T003) — project can now exist in Obsidian
3. Phase 3: `/shelf-update` (T004) — sessions can be recorded
4. Phase 4: `/shelf-sync` (T005) — issues are visible
5. Phase 5: `/shelf-feedback` (T006) — bidirectional communication
6. Phase 6: `/shelf-status` (T007) — read-only dashboard view
7. Phase 7: `/shelf-release` (T008) — release recording
8. Phase 8: Polish (T009-T011) — final verification

## Notes

- Each SKILL.md is a standalone Markdown file — no cross-dependencies between skills
- All skills share the same slug resolution, base path, and MCP degradation patterns (defined in contracts/interfaces.md)
- No compiled code, no tests, no build step — skills are Markdown instructions
- Mark each task `[X]` immediately after completing it
- Commit after each phase
