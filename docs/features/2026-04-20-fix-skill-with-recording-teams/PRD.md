# Feature PRD: Fix Skill with Recording Teams

## Parent Product

Kiln plugin (`@yoshisada/kiln`) + shelf plugin (`@yoshisada/shelf`) — see `docs/PRD.md` for product context. Feature lives in the kiln plugin because it extends `/kiln:fix`; the Obsidian write paths are owned by shelf conventions.

## Feature Overview

Extend the existing `/kiln:fix` skill so that every completed bug fix (successful OR escalated-after-9-attempts) produces a durable record — locally to `.kiln/fixes/` and to the Obsidian vault at `@projects/<project>/fixes/` — and triggers a lightweight manifest-improvement reflection. The skill's debug loop stays in main chat (preserves the live-collaboration quality of `/fix`). After the debug loop terminates, the skill spawns **two agent teams in parallel** that do the recording + reflection in isolated contexts so main-chat tokens are preserved.

This is NOT a wheel workflow. We evaluated that path and rejected it: wheel would push the entire debug loop into a wheel-runner subagent, regressing the collaborative debug case. Agent teams give us context isolation for the cheap, non-interactive finishing work without touching the valuable interactive part.

## Problem / Motivation

Today `/kiln:fix` leaves no trail beyond the commit message. The fix happens, git records it, the knowledge disappears. In contrast:

- `/kiln:mistake` captures AI errors and flows them through `@inbox/open/` → `<project>/mistakes/` as durable training data for future agents.
- `/kiln:build-prd` pipelines end with a retrospective + `shelf:propose-manifest-improvement` sub-workflow that surfaces schema/template gaps noticed during the run.
- **`/kiln:fix` has neither.**

Bug fixes are exactly the kind of event where manifest-improvement signal is highest — something in the codebase was wrong, someone investigated it, that investigation often reveals a schema/template gap the manifest could have prevented. Losing that signal every time is waste.

We also want the fix record itself (issue, root cause, files changed, commit) in the Obsidian vault so a maintainer can grep/search across fixes, link to them from project dashboards, and spot patterns over time.

The constraint that shapes everything: do NOT regress the main-chat debug experience. `/fix` works today because the debug loop lives in main chat and the user can redirect mid-loop ("no, try X"). Any solution that pushes the debug loop into a subagent (e.g., running the whole thing as a wheel workflow) breaks that. We solve this by keeping the debug loop in main and offloading ONLY the post-commit recording + reflection to isolated agent teams.

## Goals

- Every successful `/kiln:fix` invocation produces two artifacts: `.kiln/fixes/<YYYY-MM-DD>-<slug>.md` (local) and `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` (Obsidian).
- Every escalated `/kiln:fix` invocation (9 attempts exhausted, no fix) produces the same two artifacts with `status: escalated` + techniques tried + diagnostics collected.
- Bug fixes become a manifest-improvement signal source on par with build-prd pipelines — `fix-reflect` team files a proposal in `@inbox/open/` when (and only when) an actionable improvement is identified.
- Main-chat debug loop is unchanged — no regression in collaborative debugging.
- Main-chat token overhead per `/fix` invocation is ≤3k tokens (team briefs + SendMessage escape hatches only).
- Two teams run in parallel — total wall-clock cost is roughly the slower of the two, not the sum.

## Non-Goals

- **NOT a wheel workflow.** We rejected this path explicitly (see Feature Overview rationale).
- **No `shelf:shelf-full-sync` invocation.** Direct Obsidian write via MCP. Full sync is ~64.5k tokens we don't need to pay here.
- **No auto-apply of manifest improvements.** Fix-reflect proposals go to `@inbox/open/` for human review, same as `shelf:propose-manifest-improvement`.
- **No changes to `/kiln:mistake`.** Fixes and mistakes are separate concepts with separate flows.
- **No scoring, ranking, or deduping across fixes.** One file per fix, maintainer reviews in bulk.
- **No backfill of historical fixes.** Starts recording from the first `/fix` invocation after this feature ships.
- **No UI surface in the IDE or CLI.** The local file + Obsidian note + optional proposal is the entire surface.
- **No built-in viewer, dashboard, or aggregation tool.** Maintainers use `grep`, `ls`, and Obsidian search as the interface.

## Target Users

- **Direct users**: developers invoking `/kiln:fix` — they want the fix to "just work" and produce a trail without extra prompts or ceremony.
- **Indirect users**: maintainers reviewing `@inbox/open/` — they benefit from an additional well-scoped proposal source.
- **Future AI agents**: reading `@projects/<project>/fixes/` entries to avoid repeating the same diagnosis work.

## Core User Stories

- As a developer who just fixed a bug with `/kiln:fix`, I want the fix recorded automatically so that future me (or another agent) can find the root cause and the patch without re-deriving it.
- As a maintainer triaging `@inbox/open/`, I want bug-fix-driven manifest proposals to come through the same exact-patch gate as build-prd-driven proposals, so the quality bar is consistent.
- As a future AI agent debugging a similar bug, I want to find prior fix notes in `@projects/<project>/fixes/` with wikilinks to the feature spec and commit, so I can learn from them.
- As a maintainer reading a fix record, I want the one-sentence root cause and the list of changed files visible at the top of the note, so triage is fast.

## Functional Requirements

- **FR-1**: `/kiln:fix` MUST, after the debug loop terminates (successful commit OR 9-attempt escalation), compose a complete fix envelope containing: `issue`, `root_cause`, `fix_summary`, `files_changed[]`, `commit_hash` (null if escalated), `feature_spec_path` (null if no spec), `project_name`, `resolves_issue` (GitHub issue number or URL if provided, else null), `status` (`fixed` | `escalated`).
- **FR-2**: `/kiln:fix` MUST, before spawning the teams, append a local fix record at `.kiln/fixes/<YYYY-MM-DD>-<slug>.md`. This write happens inline in the skill (bash block), NOT inside either team.
- **FR-3**: `/kiln:fix` MUST spawn two agent teams in parallel after the local write: `fix-record` (Obsidian write) and `fix-reflect` (manifest-improvement reflection). Both teams receive the complete fix envelope from FR-1.
- **FR-4**: `fix-record` team MUST write exactly one file to `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` via `mcp__claude_ai_obsidian-manifest__create_file`. No direct filesystem writes to the vault.
- **FR-5**: The Obsidian fix note MUST conform to a new manifest type `@manifest/types/fix.md`. Authoring that type is part of this feature's scope.
- **FR-6**: `@manifest/types/fix.md` MUST define required frontmatter fields: `type: fix`, `date: <YYYY-MM-DD>`, `status: fixed | escalated`, `commit: <hash or null>`, `resolves_issue: <ref or null>`, `files_changed: [<path>, ...]`, `tags: [topic/*, language/* or framework/* or lib/* or infra/* or testing/*]`. Body MUST contain five H2 sections in this fixed order: `## Issue`, `## Root cause`, `## Fix`, `## Files changed`, `## Escalation notes` (the last section is `_none_` for successful fixes, populated with techniques tried + diagnostics collected for escalated fixes).
- **FR-7**: The Obsidian fix note body MUST include wikilinks to: the feature spec (if `feature_spec_path` is non-null), the resolving issue (if `resolves_issue` is non-null), and the commit (plain hash text, not a wikilink — commits are outside the vault).
- **FR-8**: `fix-reflect` team MUST use the same exact-patch gate as `shelf:propose-manifest-improvement` (FR-005 of that feature). Specifically: target restricted to `@manifest/types/*.md` or `@manifest/templates/*.md`, `current` text must verbatim-exist in the target file, `why` must cite something concrete from the fix envelope.
- **FR-9**: `fix-reflect` team MUST write to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` if and only if an actionable improvement is identified. Otherwise it MUST be silent — no file, no log line, no user-visible artifact.
- **FR-10**: `fix-reflect` team MAY `SendMessage` main chat and the `fix-record` teammate for disambiguation. These messages MUST be the exception, not the default. The envelope from FR-1 should be complete enough that most runs require zero back-talk.
- **FR-11**: `fix-record` team MAY `SendMessage` main chat ONLY for path-resolution escape (e.g., ambiguous project name, missing `feature_spec_path`). It MUST NOT ask main to compose or review the note body.
- **FR-12**: On 9-attempt escalation (debug loop exhausted, no successful fix), `/kiln:fix` MUST still run the full flow (local write + both teams). The envelope carries `status: escalated`, `commit_hash: null`, `fix_summary` describes the techniques tried, `files_changed[]` lists files inspected (not changed).
- **FR-13**: Project name resolution — `/kiln:fix` MUST resolve `<project>` by: (1) reading `project_name=<slug>` from `.shelf-config` at repo root if present; else (2) `basename "$(git rev-parse --show-toplevel)"`; else (3) skip Obsidian write silently with a one-line warn. Local `.kiln/fixes/` write always proceeds regardless.
- **FR-14**: Slug derivation for both local + Obsidian filenames MUST be kebab-case, stop-words removed, ≤50 characters, word-boundary-truncated — derived from the fix's one-line `issue` summary. Reuse the derivation logic/pattern from `plugin-shelf/scripts/derive-proposal-slug.sh` (do not duplicate; factor to a shared helper or invoke it directly).
- **FR-15**: Same-day filename collisions (local or Obsidian) MUST disambiguate with `-2`, `-3`, ... suffix. Never overwrite an existing file.
- **FR-16**: Obsidian MCP unavailability MUST NOT block the skill. If `mcp__claude_ai_obsidian-manifest__create_file` is unavailable, the `fix-record` team MUST warn once and exit 0. The local `.kiln/fixes/` file persists. The skill reports the fix as successful.
- **FR-17**: Both teams MUST be shut down via `TeamDelete` after reaching terminal state (success, silent skip, or MCP-unavailable warn). No orphaned teams left alive after `/fix` returns control to the user.
- **FR-18**: Teams MUST NOT read the main-chat transcript, prior tool results, or any file beyond what the envelope references. This enforces the "main-chat context isolation" goal — team briefs are the complete input.
- **FR-19**: `/kiln:fix` MUST NOT invoke `shelf:shelf-full-sync` at any point in this flow. Direct Obsidian write via MCP is the only vault-write mechanism.
- **FR-20**: Debug loop behavior in main chat MUST be unchanged. No task-create, team-spawn, or wheel-dispatch happens before the commit lands. Recording is strictly a post-commit stage.

## Absolute Musts

1. **Tech stack parity**: no new dependencies. Uses existing Claude Code agent teams (`TeamCreate`, `TaskCreate`, `SendMessage`, `TeamDelete`), existing Obsidian MCP (`mcp__claude_ai_obsidian-manifest__create_file`), existing exact-patch gate scripts from `plugin-shelf/scripts/`.
2. **Debug loop stays in main chat (FR-20)**: non-negotiable. The reason this isn't a wheel workflow. If implementation finds itself spawning anything during the debug loop, that's a scope violation.
3. **Two teams, not one (FR-3)**: fix-record and fix-reflect are independent concerns. Coupling them adds coordination overhead without benefit. Parallel spawn.
4. **Complete envelope (FR-1, FR-18)**: `SendMessage` from teams to main is an escape hatch, not a mechanism. The envelope must be rich enough that most runs require zero team→main back-talk.
5. **Silent on no-improvement (FR-9)**: matches `shelf:propose-manifest-improvement` principle. A team that writes "no improvement found" notes creates noise.
6. **Escalated fixes still produce records (FR-12)**: a failed fix attempt is exactly the signal worth capturing for future agents.
7. **Direct Obsidian write (FR-19)**: never invoke `shelf:shelf-full-sync`. That's ~64.5k tokens we don't owe here.
8. **Plugin portability**: if any new command scripts are added, they MUST resolve via `${WORKFLOW_PLUGIN_DIR}` per CLAUDE.md. (This feature doesn't add wheel workflows, but scripts invoked by team agents must still be plugin-portable.)

## Tech Stack

Inherited from kiln + shelf. No additions.

- **Agent orchestration**: Claude Code agent teams (`TeamCreate` / `TaskCreate` / `SendMessage` / `TeamDelete`)
- **Vault writes**: Obsidian MCP (`mcp__claude_ai_obsidian-manifest__create_file`)
- **Exact-patch gate**: existing `plugin-shelf/scripts/check-manifest-target-exists.sh` + `validate-reflect-output.sh`
- **Slug derivation**: existing `plugin-shelf/scripts/derive-proposal-slug.sh`
- **Shell**: bash 5.x for the inline local-record block in the skill

## Impact on Existing Features

- **`/kiln:fix`**: gains a terminal recording stage after the commit. Existing debug-loop + commit behavior is unchanged. Skill file gains a "Step 7: Record the fix" section and associated bash + team-spawn logic.
- **`shelf:propose-manifest-improvement`**: no change, but its exact-patch gate scripts are now invoked from a second caller (the `fix-reflect` team). Its own caller wiring is unchanged.
- **`@manifest/types/`**: gains `fix.md` (new file). No modifications to existing types.
- **`@projects/<project>/fixes/`**: new canonical vault folder. Created on first fix per project (MCP `create_file` will create the parent path as needed, or the team explicitly ensures it).
- **`.kiln/fixes/`**: new local folder. Created on first fix. Gitignored by default (added to `.gitignore` as part of this feature) so fix records don't clutter every PR diff.
- **`@inbox/open/`**: maintainers may see `manifest-improvement-*.md` proposals originating from both `shelf:propose-manifest-improvement` (build-prd pipelines, sub-workflow callers) and `fix-reflect` (bug fixes). Filenames are consistent; provenance is evident from the `why` field citing either a pipeline run or a fix.
- **No breaking changes.** If this feature is disabled (recording stage removed from `/kiln:fix`), behavior reverts to today's commit-only trail.

## Success Metrics

- **M1 — Recording coverage**: 100% of terminal `/kiln:fix` invocations (successful AND escalated) produce both `.kiln/fixes/<date>-<slug>.md` and `@projects/<project>/fixes/<date>-<slug>.md`, measured over first 30 days. Local file coverage is a hard gate (no MCP dependency); Obsidian coverage excludes invocations where FR-13's resolution step fell through to (3) silent-skip.
- **M2 — Reflect silent rate**: ≥70% of `fix-reflect` runs produce no `@inbox/open/` proposal. Parallels `shelf:propose-manifest-improvement` expectation — most fixes won't surface a manifest gap. Measured monthly.
- **M3 — Reflect precision**: ≥80% of `fix-reflect`-authored `@inbox/open/` proposals are accepted by the maintainer (merged into `@manifest/` as-written, possibly with minor edits). Parallels `shelf:propose-manifest-improvement` M2.
- **M4 — Main-chat token overhead**: ≤3k tokens of team-related traffic (spawn + task brief + SendMessage exchanges) visible in main chat per `/fix` invocation. Measured by inspecting the conversation transcript for 10 representative runs.
- **M5 — Zero main-chat debug regression**: collaborative-debug user flows still work end-to-end. Measured by running 5 interactive `/fix` sessions where the user redirects mid-loop ("try X instead") and verifying the redirect lands in the same main-chat debug loop as before this feature.

## Risks / Unknowns

- **Team back-talk bleed**: teams that ask too many disambiguation questions defeat the point of the isolation. Mitigation: FR-1 mandates a complete envelope; FR-10/FR-11 cap SendMessage as an escape hatch, not a default. Monitor via M4.
- **Obsidian MCP unavailability**: the vault MCP may be unavailable (user not signed in, vault not configured, network blip). Mitigation: FR-16 makes the write non-blocking — warn once, exit 0, local file persists. Same pattern as `shelf:propose-manifest-improvement` FR-015.
- **Project-name resolution gaps**: monorepos with nested projects may not have a clean `.shelf-config` entry. FR-13 fallback to `basename` works for most single-repo-one-project setups. If neither succeeds, Obsidian write silently skips — local file is still written. No user intervention required; we accept a gap here rather than pause for input mid-fix.
- **Fix-reflect generating noisy proposals**: early runs might over-trigger if the agent generalizes from a single fix too aggressively. Mitigation: reuse the same exact-patch gate as `shelf:propose-manifest-improvement` (verbatim `current` match + grounded `why` citing the fix envelope). Monitor via M2/M3.
- **Team spawn latency**: `TeamCreate` + `TaskCreate` + agent spawn has non-trivial startup cost. For very quick fixes (typo-level), the recording stage may be slower than the fix itself. Mitigation: parallel spawn (FR-3) bounds the cost to the slower of the two teams; this is acceptable overhead for the durability benefit. If adoption reveals this as a real irritation, future work could add a `--no-record` flag to `/kiln:fix`.
- **`@manifest/types/fix.md` schema churn**: first version may need iteration as real fix records land and patterns emerge. Accepted — the manifest-improvement subroutine provides a natural channel for amending the type as gaps surface.
- **Escalated fixes as attack surface**: `status: escalated` records describe unfixed bugs. They should not leak credentials or internal IPs from debug diagnostics. Mitigation: the existing `/fix` skill already includes a credentials-handling section (Step 2b) — the envelope composed in FR-1 MUST NOT include any values from `.kiln/qa/.env.test`. Implementation must enforce this.

## Assumptions

- The Obsidian manifest vault MCP (`mcp__claude_ai_obsidian-manifest__*`) is the canonical write path. Same assumption as `shelf:propose-manifest-improvement`.
- `.shelf-config` is the canonical source for `project_name` when present, aligning with `plugin-shelf` conventions.
- Claude Code agent teams (`TeamCreate` et al.) are reliably available in the consumer environment. This is now validated by `shelf:propose-manifest-improvement` (PR #114, merged) and the build-prd pipeline's retrospective flow.
- Maintainers triage `@inbox/open/` regularly enough that fix-reflect proposals don't accumulate stale. Same assumption as manifest-improvement.
- The team count added (2) does not exceed Claude Code's concurrent-team limit in consumer environments. Current pipelines run 6-8 teammates regularly without issue; 2 additional short-lived teams is a negligible increment.
- The `@manifest/types/mistake.md` pattern (frontmatter schema + H2 section shape + explicit enums) is a good template for authoring `@manifest/types/fix.md`.

## Open Questions

- **Should `fix-reflect` run before `fix-record` finishes, or wait?** The envelope from FR-1 is complete, so no real dependency. Defaulting to parallel (FR-3) for latency. Revisit only if fix-reflect benefits from reading the finished Obsidian note.
- **Should the local `.kiln/fixes/` file be committed to git by default, or gitignored?** Leaning gitignored (like `.kiln/issues/` partially is, and `.kiln/qa/` fully is) to keep PR diffs clean. Maintainers can opt-in per-project by removing the gitignore line. Final answer goes in the spec.
- **Should `fix-reflect` also be invokable as a standalone step (separate from `/kiln:fix`)?** Mirrors `shelf:propose-manifest-improvement`'s standalone SKILL.md. Low-cost to add; defer decision to implementation unless the spec author sees a reason to force it now.
- **Tag vocabulary for `@manifest/types/fix.md`**: mistake.md uses a three-axis tag lint (`mistake/*`, `topic/*`, stack/*`). Fix.md probably needs similar but with `fix/*` axis values to be defined (e.g., `fix/runtime-error`, `fix/regression`, `fix/test-failure`, `fix/build-failure`, `fix/ui`). Specifier to propose the initial vocabulary; iterate post-launch.
