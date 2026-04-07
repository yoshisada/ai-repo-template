# Tasks: Plugin Clay

**Input**: Design documents from `specs/plugin-clay/`
**Prerequisites**: plan.md (required), spec.md (required), contracts/interfaces.md (required)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US7)
- Exact file paths in descriptions

## Phase 1: Plugin Scaffold (FR-001, FR-002, FR-003)

**Purpose**: Create plugin-clay directory structure with manifests

- [ ] T001 [US7] Create `plugin-clay/.claude-plugin/plugin.json` with name, version, description, author, homepage, dependencies (wheel, shelf), and workflows field per contracts/interfaces.md schema
- [ ] T002 [P] [US7] Create `plugin-clay/.claude-plugin/marketplace.json` with distribution config matching kiln/wheel/shelf pattern
- [ ] T003 [P] [US7] Create `plugin-clay/package.json` for npm package `@yoshisada/clay` with version from VERSION file, bin entry pointing to init script if needed
- [ ] T004 [P] [US7] Create empty directory placeholders: `plugin-clay/skills/`, `plugin-clay/workflows/`

**Checkpoint**: Plugin scaffold exists, manifests are valid JSON, `jq . plugin-clay/.claude-plugin/plugin.json` succeeds

---

## Phase 2: Wheel Manifest Enhancement (FR-028, FR-029, FR-030, FR-031)

**Purpose**: Extend wheel to discover workflows from installed plugins — prerequisite for clay's Obsidian workflow

- [ ] T005 [US7] Add `workflow_discover_plugin_workflows()` function to `plugin-wheel/lib/workflow.sh` per contracts/interfaces.md signature. Scans `.claude/plugins/*/plugin.json` for `workflows` field, returns JSON array of `{name, plugin, path, readonly}` descriptors.
- [ ] T006 [US7] Update `plugin-wheel/skills/wheel-list/SKILL.md` to call `workflow_discover_plugin_workflows()` after scanning local `workflows/` directory. Display plugin workflows in a separate "Plugin Workflows (read-only)" section.
- [ ] T007 [US7] Update `plugin-wheel/skills/wheel-run/SKILL.md` Step 1 to resolve `<plugin>:<workflow-name>` syntax per contracts/interfaces.md. When name contains `:`, split on `:` and look up plugin workflow via `workflow_discover_plugin_workflows()`.

**Checkpoint**: `workflow_discover_plugin_workflows` returns valid JSON. `/wheel-list` shows plugin workflows. `/wheel-run clay:clay-sync` resolves to the correct file path.

---

## Phase 3: Idea Research Skill (FR-004 through FR-009) — US1

**Goal**: User can research a product idea and get a classified market report

**Independent Test**: Run `/idea-research "a CLI tool that generates changelogs from git history"` and verify `products/<slug>/research.md` is created with classified findings

- [ ] T008 [US1] Create `plugin-clay/skills/idea-research/SKILL.md` with frontmatter (name: idea-research, description per spec). Implement: (1) accept `$ARGUMENTS` as 1-5 sentence idea (FR-004), (2) derive slug via kebab-case, (3) create `products/<slug>/` if missing, (4) use WebSearch for market research (FR-005), (5) classify findings using rubric: EXACT MATCH, CLOSE COMPETITOR, ADJACENT, SLIGHTLY SIMILAR (FR-006), (6) write structured report to `products/<slug>/research.md` with product name, URL, description, classification, differentiators, pricing (FR-007, FR-008), (7) include go/no-go recommendation (FR-009).

**Checkpoint**: SKILL.md has valid frontmatter, report output matches FR-007/FR-008 structure

---

## Phase 4: Project Naming Skill (FR-010 through FR-014) — US2

**Goal**: User can get branded name candidates with availability checks

**Independent Test**: Run `/project-naming` with product context and verify `products/<slug>/naming.md` has ranked candidates

- [ ] T009 [US2] Create `plugin-clay/skills/project-naming/SKILL.md` with frontmatter (name: project-naming, description per spec). Implement: (1) accept `$ARGUMENTS` as product context (FR-010), (2) read `products/<slug>/research.md` if available for context, (3) generate 5-10 candidate names with rationale (FR-011), (4) check npm, GitHub, domain availability for each (FR-012), (5) write naming report to `products/<slug>/naming.md` with ranked recommendations (FR-013), (6) support iterative refinement via conversational follow-up (FR-014).

**Checkpoint**: SKILL.md has valid frontmatter, naming report includes availability data

---

## Phase 5: Create PRD Skill (FR-015 through FR-021) — US3

**Goal**: User answers clarifying questions and gets a 3-file PRD set ready for kiln's `/build-prd`

**Independent Test**: Run `/create-prd` with a product idea, answer questions, verify PRD.md + PRD-MVP.md + PRD-Phases.md are created

- [ ] T010 [US3] Create `plugin-clay/skills/create-prd/SKILL.md` with frontmatter (name: create-prd, description per spec). Implement merged logic from kiln's `/create-prd` and `founder-prd` skill (FR-015): (1) detect mode from input — Mode A (new product), Mode B (feature addition), Mode C (PRD-only workspace) (FR-016), (2) ask clarifying questions one at a time with multiple-choice options (FR-017) covering product, users, problem, use cases, MVP, scope control, success, constraints, tech stack, risks, absolute musts, (3) generate PRD.md, PRD-MVP.md, PRD-Phases.md (FR-018) under `products/<slug>/` (FR-019), (4) incorporate research.md and naming.md if present (FR-020), (5) enforce tech stack definition — never undefined, propose defaults (FR-021), (6) include "Absolute Musts" section with tech stack as #1.

**Checkpoint**: All 3 PRD files generated with tech stack defined and absolute musts present

---

## Phase 6: Create Repo Skill (FR-022 through FR-027) — US4

**Goal**: User creates a GitHub repo from a finished PRD, scaffolded with kiln

**Independent Test**: Run `/create-repo` with a product slug pointing at a finished PRD, verify GitHub repo is created with kiln infrastructure and PRD in docs/

- [ ] T011 [US4] Create `plugin-clay/skills/create-repo/SKILL.md` with frontmatter (name: create-repo, description per spec). Implement: (1) resolve PRD from `$ARGUMENTS` — product slug or explicit path (FR-022), (2) validate `gh` CLI is authenticated, (3) create GitHub repo with specified name, visibility, org (FR-025), (4) scaffold kiln infrastructure via init script (FR-023), (5) copy PRD.md, PRD-MVP.md, PRD-Phases.md from `products/<slug>/` to `docs/` (FR-024), (6) install kiln, wheel, shelf plugins (FR-026), (7) suggest `/build-prd` as next step (FR-027), (8) write repo URL to `products/<slug>/.repo-url` marker file for status tracking.

**Checkpoint**: Skill creates repo, seeds PRD, installs plugins, suggests next step

---

## Phase 7: Clay List Skill (FR-036, FR-037) — US6

**Goal**: User sees all products with their pipeline status

**Independent Test**: Create product directories with varying artifacts, run `/clay-list`, verify table output

- [ ] T012 [US6] Create `plugin-clay/skills/clay-list/SKILL.md` with frontmatter (name: clay-list, description per spec). Implement: (1) scan `products/*/` directories, (2) derive status using `clay_derive_status` logic from contracts/interfaces.md (FR-036), (3) enforce directory structure convention (FR-037), (4) output formatted table with product name, status, artifact list.

**Checkpoint**: `/clay-list` outputs correct statuses for products at different pipeline stages

---

## Phase 8: Obsidian Sync Workflow (FR-032 through FR-035) — US5

**Goal**: Products and PRDs sync to Obsidian via wheel workflow

**Independent Test**: Run `/wheel-run clay:clay-sync` and verify Obsidian notes are created/updated

- [ ] T013 [US5] Create `plugin-clay/workflows/clay-sync.json` per contracts/interfaces.md schema. Three steps: (1) `scan-products` command step — scans `products/` and writes manifest to `.clay/sync-manifest.json`, (2) `sync-to-obsidian` agent step — creates/updates Obsidian notes for each product via shelf MCP with name, status, artifact links (FR-032, FR-033, FR-035), (3) `sync-research` agent step — syncs research findings as linked notes (FR-034). Context flows from scan-products to both agent steps.
- [ ] T014 [P] [US5] Update `plugin-clay/.claude-plugin/plugin.json` to include `"workflows": ["workflows/clay-sync.json"]` in the manifest (FR-032). Verify JSON is valid.

**Checkpoint**: Workflow JSON passes `workflow_load` validation. Plugin manifest declares the workflow.

---

## Phase 9: Polish & Validation

**Purpose**: Cross-cutting validation across all skills and wheel changes

- [ ] T015 Validate all SKILL.md files have correct frontmatter (name + description fields)
- [ ] T016 [P] Validate all JSON files parse cleanly: `jq . plugin-clay/.claude-plugin/plugin.json`, `jq . plugin-clay/package.json`, `jq . plugin-clay/workflows/clay-sync.json`
- [ ] T017 [P] Verify `plugin-clay/.claude-plugin/plugin.json` dependencies field lists `["wheel", "shelf"]`
- [ ] T018 [P] Verify `workflow_discover_plugin_workflows()` in `plugin-wheel/lib/workflow.sh` handles edge cases: no plugins directory, plugins without workflows field, malformed plugin.json

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Scaffold)**: No dependencies — start immediately
- **Phase 2 (Wheel Manifest)**: No dependencies on Phase 1 — can run in parallel
- **Phase 3-7 (Skills)**: Depend on Phase 1 (need plugin-clay/ directory to exist). Can run in parallel with each other.
- **Phase 8 (Obsidian Sync)**: Depends on Phase 1 (plugin.json exists) and Phase 2 (wheel discovers plugin workflows)
- **Phase 9 (Polish)**: Depends on all previous phases

### Parallel Opportunities

- **Phase 1 + Phase 2**: Different plugins, no file conflicts — run in parallel
- **Phase 3 + Phase 4**: Different skill directories — run in parallel
- **Phase 5 + Phase 6**: Different skill directories — run in parallel
- **Phase 7 + Phase 8**: Phase 7 (clay-list) is independent; Phase 8 depends on Phase 2
- **T001-T004**: All create different files — run in parallel
- **T013 + T014**: Different files — run in parallel

### Agent Assignment

| Agent | Phases | Files Owned |
|-------|--------|-------------|
| impl-infra | 1, 7, 8 | `plugin-clay/` (scaffold), `plugin-clay/skills/clay-list/`, `plugin-clay/workflows/` |
| impl-skills-1 | 3, 4 | `plugin-clay/skills/idea-research/`, `plugin-clay/skills/project-naming/` |
| impl-skills-2 | 5, 6 | `plugin-clay/skills/create-prd/`, `plugin-clay/skills/create-repo/` |
| impl-wheel-manifest | 2 | `plugin-wheel/lib/workflow.sh`, `plugin-wheel/skills/wheel-list/`, `plugin-wheel/skills/wheel-run/` |

No two agents write to the same file.
