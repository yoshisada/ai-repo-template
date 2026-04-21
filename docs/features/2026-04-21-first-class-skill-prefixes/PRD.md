# Feature PRD: First-Class Skill Prefix Convention

## Parent Product

- Parent PRD: [docs/PRD.md](../../PRD.md)
- Product: `@yoshisada/kiln` — spec-first development harness for Claude Code, distributed as a plugin marketplace with five plugins (kiln, shelf, clay, trim, wheel).

## Feature Overview

Rename every first-class (user-invokable) skill across all five plugins to follow the `<plugin>-<action>` prefix convention. Directories, frontmatter `name:` fields, and every cross-reference are updated in lockstep. Pipeline-internal skills (`specify`, `plan`, `tasks`, `implement`, `audit`) stay unprefixed because users never invoke them directly.

This reverses the in-plugin prefix stripping done in PR #121 (2026-04-20, commit `cc19311`) and extends the convention to first-class skills that never carried a prefix, producing a uniform surface.

## Problem / Motivation

PR #121 stripped prefixes like `wheel-stop` → `stop`, `shelf-sync` → `sync`, `trim-pull` → `pull` in the name of "consistency" with the plugin directory. In practice this made skill names ambiguous to grep / file search: `stop`, `create`, `init`, `list`, `run`, `status`, `update` collide across multiple plugins, and plain text like `sync` matches hundreds of unrelated lines. The repo owner uses grep as a primary navigation tool and explicitly pushed back: "i think we want wheel-stop since it helps with searchability for me."

Extending the same convention to first-class skills that never had a prefix (e.g., kiln's `report-issue`, shelf's `feedback`, clay's `idea`) closes the gap — so every user-invokable skill looks the same regardless of which plugin owns it. Pipeline-internal skills stay bare because they are implementation details of `/kiln:build-prd` and `/kiln:fix` and are already excluded from the `/kiln:next` whitelist.

## Goals

- Every first-class skill has a directory and frontmatter `name` of the form `<plugin>-<action>` (e.g., `kiln-build-prd`, `shelf-sync`, `wheel-stop`).
- Every internal cross-reference — other skills, agents, workflow JSON, templates, hooks, docs, `CLAUDE.md` — updates in lockstep with the renames.
- `/plugin:<new-name>` resolves for every renamed command after the plugin cache refreshes.
- Pipeline-internal skills (`kiln:specify`, `kiln:plan`, `kiln:tasks`, `kiln:implement`, `kiln:audit`) are deliberately left unprefixed so `/kiln:build-prd` and `/kiln:fix` keep invoking them as they do today.

## Non-Goals

- Plugin directory names (`plugin-kiln`, `plugin-shelf`, etc.) — unchanged.
- Agent names inside `plugin-*/agents/` — unchanged.
- Hook script names — unchanged.
- Workflow JSON filenames beyond what's required to keep `<skill>.json` aligned with the renamed skill that owns it.
- Unprefixing the five pipeline-internal skills or otherwise changing their surface.
- User-facing docs outside the repo (e.g., the marketplace listing, the npm README) — follow-on work, not in this PR.

## Target Users

Kiln plugin maintainers (primary — Ryan / yoshisada) and downstream consumer-repo users who invoke plugin commands. The maintainer benefit is searchability; the consumer benefit is that every first-class command follows one predictable shape.

## Core User Stories

- **US-001** As the plugin maintainer, when I grep for `wheel-stop` I get exactly the handful of files that reference the wheel stop skill, so I can confidently find every call site before changing behavior.
- **US-002** As the plugin maintainer, when I run `/plugin:create` from memory I can predict that the plugin name prefix is always present on first-class skills, so I don't have to remember per-plugin exceptions.
- **US-003** As a `/kiln:build-prd` or `/kiln:fix` orchestrator, I continue to invoke pipeline-internal skills as `/kiln:specify`, `/kiln:plan`, `/kiln:tasks`, `/kiln:implement`, `/kiln:audit` with no renames, so existing pipeline prompts keep working unchanged.

## Functional Requirements

- **FR-001 First-class rename coverage.** Every first-class skill in `plugin-kiln/skills/`, `plugin-shelf/skills/`, `plugin-clay/skills/`, `plugin-trim/skills/`, and `plugin-wheel/skills/` is renamed so both the directory name AND the frontmatter `name:` field match `<plugin>-<action>`. The five pipeline-internal skills (`specify`, `plan`, `tasks`, `implement`, `audit` under `plugin-kiln/skills/`) are explicitly excluded.
- **FR-002 Complete rename table.** The implementation plan includes an explicit rename table mapping every old skill directory to its new name. Skills already prefixed (`kiln-cleanup`, `kiln-doctor`) appear in the table as no-ops so the final state is unambiguous.
- **FR-003 Cross-reference update.** Every cross-reference to a renamed skill is updated wherever it appears: other SKILL.md files, `plugin-*/agents/*.md`, `plugin-*/workflows/*.json`, top-level `workflows/*.json`, `plugin-*/templates/`, `plugin-*/scripts/`, `plugin-*/hooks/`, `CLAUDE.md`, `docs/**/*.md`, `specs/**/*.md`, and `.kiln/issues/*.md`. Dangling references are treated as blockers.
- **FR-004 Workflow alignment.** Where a workflow JSON filename matches a renamed skill (e.g., `plugin-kiln/workflows/report-issue.json`), the workflow file is renamed to match the new skill name and every `activate_name` / workflow lookup is updated accordingly. Workflow JSONs that do NOT correspond to a skill keep their current name.
- **FR-005 `/kiln:next` whitelist update.** The `/kiln:next` skill's allowed-commands whitelist is updated so every first-class command appears in its new prefixed form. The blocklist stays unchanged (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit` remain blocked and mapped to `/kiln:build-prd`).
- **FR-006 Parent PRD + top-level docs.** `docs/PRD.md`, `CLAUDE.md`, and any README references in the plugin source repo are updated to show new command names.
- **FR-007 Hard cutover, no aliases.** No legacy aliases, compatibility shims, or redirects are shipped. The rename is a single-commit, single-PR cutover. Any consumer repo that has invoked an old command path will need to learn the new one. This mirrors PR #121's approach.
- **FR-008 Agent teammate naming convention reference.** Inside `plugin-kiln/skills/build-prd/SKILL.md`, every example/reference of an internal command stays unprefixed (`/specify`, `/plan`, etc.) per FR-001's explicit exclusion. First-class commands named in the build-prd skill body (`/kiln:create-prd`, `/kiln:fix`, etc.) switch to the prefixed form.
- **FR-009 Version bump.** The rename PR bumps the `pr` segment of `VERSION` and propagates to all five `plugin-*/.claude-plugin/plugin.json` files and the root `package.json`.

## Absolute Musts

1. **No dangling references** — after the rename, grep for each old skill name across the full repo must return only intentional out-of-scope hits (same pattern as PR #121's residual matches in `.shelf-sync.json` data files, `specs/` historical artifacts, `.kiln/` runtime caches, etc.). Any live cross-reference to an old name is a hard blocker.
2. **Pipeline still works end-to-end** — `/kiln:build-prd` and `/kiln:fix` must continue to dispatch to `specify`/`plan`/`tasks`/`implement`/`audit` using the exact same skill invocation mechanism they use today.
3. **Tech stack: Markdown + JSON + Bash** — no new runtime dependencies, no new libraries, no new tools. This is a rename refactor.

## Tech Stack

Inherited from the parent product PRD (`docs/PRD.md`) — no additions, no overrides. The only tools involved are:

- Markdown (SKILL.md, agent definitions, docs)
- JSON (workflow definitions, plugin manifests)
- Bash (hook scripts, plugin command steps)
- `jq`, `gh`, standard POSIX utilities (already assumed by the kiln harness)
- Claude Code agent teams (`TeamCreate`, `TaskCreate`, `SendMessage`, `TeamDelete`) — same orchestration model PR #121 used

## Impact on Existing Features

**Breaking changes expected** — every first-class command the user types today changes shape.

Known impact surfaces:

- **User muscle memory.** `/wheel:stop` → `/wheel:wheel-stop`, `/shelf:sync` → `/shelf:shelf-sync`, `/clay:new-product` → `/clay:clay-new-product`, etc. Affects the repo owner and any collaborator who has memorized command paths.
- **`/kiln:next` output.** Recommendation strings change. Old log files remain valid but suggest pre-rename commands — acceptable (historical artifacts).
- **Existing `.kiln/issues/*.md` files.** Suggested-command lines reference old names. Treat as historical — do not rewrite.
- **In-flight specs and PRDs.** Any spec/PRD that references a command path is updated. Completed specs' historical text is out of scope (same rule PR #121 applied).
- **Downstream consumer repos.** Any repo that has invoked the old command paths will see "skill not found" until they relearn the new names. Mitigation: a one-line note in the PR body listing the renames and the CLAUDE.md update.
- **Plugin cache divergence (existing known issue).** Until each consumer repo refreshes the plugin cache to pick up the new version, they're on the old names. This is not new behavior — PR #121 had the same property. The existing backlog item `.kiln/issues/2026-04-20-plugin-cache-divergence.md` is unaffected by this PR.

No impact on:

- The five pipeline-internal skills and the build-prd/fix orchestration that uses them.
- Agent names, hook names, plugin directory names.
- Workflow JSON filenames that don't correspond to a renamed skill.
- Runtime state (`.wheel/state_*.json`, `.kiln/implementing.lock`, `.shelf-sync.json`).

## Success Metrics

- **SC-001 Zero dangling references.** `grep` for every old skill name across the full repo (excluding historical specs, `.kiln/` caches, and runtime data files) returns zero live hits after the rename commits land. Auditor verifies.
- **SC-002 All first-class skills prefixed.** A grep/list of `plugin-*/skills/*/SKILL.md` shows every first-class skill's frontmatter `name:` matches `<plugin>-<action>`. The five excluded pipeline-internal skills are explicitly confirmed unprefixed.
- **SC-003 Pipeline smoke.** A manual end-to-end `/kiln:build-prd` run on a throwaway feature completes through specifier → implementer → auditor → retrospective without "skill not found" errors. (Same post-merge smoke requirement PR #121 had.)
- **SC-004 `/kiln:next` whitelist round-trip.** Invoking `/kiln:next` on a clean project emits suggestions using the new prefixed command forms with no old-form recommendations.

## Risks / Unknowns

- **Cross-reference surface is large.** PR #121 touched hundreds of references; this PR has comparable scope plus the newly-added first-class skills that never had prefixes. Mitigation: lift PR #121's parallel-by-plugin agent-team structure wholesale and use the same SC-001 grep-gate pattern as the hard verification.
- **Claude Code command-path collisions.** If two plugins both have a skill named `<plugin>-create` (e.g., `shelf-create` and `wheel-create` and `clay-create-repo`), the plugin-name prefix on the user-invokable path (`/shelf:shelf-create` vs `/wheel:wheel-create`) handles disambiguation, but the verbosity compounds. Accept as a known ergonomic cost.
- **In-flight branches / open PRs.** Any open branch that renames a skill or references an old command in its spec will merge-conflict once this lands. Mitigation: check branch state before kickoff, merge or rebase outstanding work first.
- **Plugin cache staleness at consumer sites.** Consumer repos running the previous cached version will keep seeing the old names until they refresh. Not a blocker — same behavior as PR #121.

## Assumptions

- The Claude Code plugin system uses the frontmatter `name:` field as the single source of truth for both directory lookup and `/plugin:name` command resolution — validated by PR #121's behavior.
- No consumer repo has built automation that hardcodes old command paths in ways we can't update in the same PR. (The only such surfaces we know about — the five plugins and the `.specify/` / `CLAUDE.md` scaffold — are inside this repo.)
- PR #121's specs/plan/tasks template can be inverted and reused. The rename table shape is identical; only the mapping direction flips.

## Open Questions

- None that block PRD approval. Plan phase will need to produce the full rename table and decide the agent-team partition (one implementer per plugin, mirroring PR #121).
