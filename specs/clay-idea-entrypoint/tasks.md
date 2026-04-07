# Tasks: Clay Idea Entrypoint

**Input**: Design documents from `specs/clay-idea-entrypoint/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), contracts/interfaces.md

## Phase 1: Create `/clay:idea` Skill (US-1, US-2, US-3)

**Goal**: Create the new idea skill as the primary clay entrypoint with overlap detection and routing.

**Independent Test**: Run `/clay:idea "build a habit tracker"` with empty products/ and no clay.config. Verify it presents "New product" and offers to chain to `/idea-research`.

- [ ] T001 [US1] Create `plugin-clay/skills/idea/SKILL.md` with frontmatter (name: idea, description per contracts/interfaces.md) and User Input section that reads $ARGUMENTS and prompts if empty (FR-001)
- [ ] T002 [US1,US2] Add Step 1: Gather Context — scan `products/` directory for all product slugs, read research.md/naming.md/PRD.md from each to extract names, descriptions, summaries (FR-002)
- [ ] T003 [US3] Add clay.config reading to Step 1 — parse `clay.config` line by line with format `<slug> <url> <path> <date>`, skip malformed lines with warning, gracefully skip if file doesn't exist (FR-003, FR-010, FR-012)
- [ ] T004 [US1,US2,US3] Add Step 2: Overlap Analysis — instruct LLM to compare input idea against gathered products and tracked repos for semantic overlap, explain reasoning for each match (FR-004)
- [ ] T005 [US1,US2,US3] Add Step 3: Present Routing Options — display findings with exactly 4 routing options: "New product", "Add to existing product", "Work in existing repo", "Similar but distinct". Always require user confirmation before proceeding (FR-005)
- [ ] T006 [US1] Add Step 4: Route to Downstream Skill — implement chaining logic: "New product" chains to `/idea-research` → `/project-naming` → `/create-prd` sequentially with confirmation at each step (FR-006, FR-007)
- [ ] T007 [US2] Add "Add to existing product" route — chain to `/create-prd` in Mode C targeting the matched product slug (FR-006)
- [ ] T008 [US3] Add "Work in existing repo" route — suggest `cd <local-path>` and running `/build-prd` or `/clay:idea` there (FR-006)

**Checkpoint**: `/clay:idea` skill is complete. All 4 routes work. Overlap detection reads both products/ and clay.config.

---

## Phase 2: Update `/clay:create-repo` (US-4)

**Goal**: After successful repo creation, append an entry to clay.config so repos are tracked.

**Independent Test**: Run `/clay:create-repo` for a product. Verify clay.config is created/appended with the correct format.

- [ ] T009 [US4] Add Step 7.5 to `plugin-clay/skills/create-repo/SKILL.md` — after successful repo creation (Step 7) and before status marker (Step 8), append entry to clay.config with format `<slug> <repo-url> <local-path> <YYYY-MM-DD>`. Use `>>` (append). Create clay.config if it doesn't exist. (FR-009, FR-013)

**Checkpoint**: `/clay:create-repo` writes to clay.config after every successful repo creation.

---

## Phase 3: Update `/clay:clay-list` (US-5)

**Goal**: Show repo URLs and local paths from clay.config in the product list output.

**Independent Test**: Create products/ with entries and a clay.config with matching slugs. Run `/clay:clay-list`. Verify table includes repo URL and local path columns.

- [ ] T010 [US5] Add Step 1.5 to `plugin-clay/skills/clay-list/SKILL.md` — read clay.config if it exists, parse entries into a lookup map (slug → url, local_path, date). Skip gracefully if file doesn't exist. (FR-011, FR-012)
- [ ] T011 [US5] Update Step 4 (Display table) in `plugin-clay/skills/clay-list/SKILL.md` — when clay.config exists, add "Repo URL" and "Local Path" columns. Products without clay.config entries show "—". When clay.config doesn't exist, render table without repo columns. (FR-014)

**Checkpoint**: `/clay:clay-list` shows repo info from clay.config when available.

---

## Phase 4: Polish & Validation

**Goal**: Verify all skills work together and existing skills are unaffected.

- [ ] T012 Verify `/clay:idea` skill file has correct frontmatter and all required sections per contracts/interfaces.md
- [ ] T013 Verify `/clay:create-repo` changes are additive — all existing steps (1-9) are preserved and functional
- [ ] T014 Verify `/clay:clay-list` changes are additive — existing status derivation and artifact counting are preserved

**Checkpoint**: All 14 FRs are addressed. Existing clay skills are unaffected.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** (idea skill): No dependencies — can start immediately
- **Phase 2** (create-repo update): No dependencies on Phase 1 — can run in parallel
- **Phase 3** (clay-list update): No dependencies on Phase 1 or 2 — can run in parallel
- **Phase 4** (polish): Depends on Phases 1, 2, and 3

### Within Phase 1

- T001 must complete first (creates the file)
- T002 and T003 can run in parallel after T001 (gather context sections)
- T004 depends on T002 and T003 (overlap analysis needs gathered data)
- T005 depends on T004 (routing depends on analysis)
- T006, T007, T008 can run in parallel after T005 (independent routes)

### Parallel Opportunities

- Phases 1, 2, and 3 can be worked on in parallel by different agents (different files)
- Within Phase 1: T002/T003 are parallelizable; T006/T007/T008 are parallelizable
- Phase 2 is a single task (T009)
- Phase 3: T010 and T011 are sequential (T011 depends on T010's lookup map)
