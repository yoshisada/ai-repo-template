# Implementer friction notes — fix-skill-with-recording-teams

Date: 2026-04-20
Branch: `build/fix-skill-with-recording-teams-20260420`

## What went well

- Contracts in `contracts/interfaces.md` were precise enough to implement straight through. Every helper was unambiguous from its header comment. No back-and-forth needed with the specifier.
- Tasks ordered by dependency chain — setup → foundational → MVP → polish — meant I never got blocked waiting on a cross-cutting concern. The one exception (see "T012 depends on both briefs" below) was trivially handled by drafting both briefs in one session.
- Pure-bash `.sh` test convention fit the work well. Zero test infra to configure. Each helper + test landed in one commit.
- The portability test (T016) caught exactly the class of regression it was designed for — my first SKILL.md draft had three prose references to repo-relative plugin paths; the test flagged them; I rewrote the prose; the test cleared.

## Friction points

### T012 + T014 serialize-on-SKILL.md

Tasks.md orders T011 (fix-record brief) in Phase 3 and T014 (fix-reflect brief) in Phase 5, but T012's note reads "Commit only after both templates (T011 + T013) are drafted". T013 is the escalated-case test extension — not a brief. This wording suggested the SKILL.md edit should wait for Phase 4, but the dependency graph (and common sense) says T014's brief is what T012 needs to reference. I interpreted it as "T011 AND T014" (both briefs) and drafted T014 in Phase 3 so the SKILL.md edit could wire both brief paths in one commit.

**Suggestion for future tasks.md**: say "Commit only after T011 and T014 are drafted" — naming T014 explicitly eliminates the ambiguity.

### Prose-path lint is stricter than the real portability invariant

FR-025 is about runtime path resolution — no hardcoded `plugin-shelf/scripts/...` or `plugin-kiln/skills/...` in actual substitution values. The T016 test greps the raw skill/brief text for these literals. That's a conservative lint: it also flags prose mentions ("team briefs live under `plugin-kiln/skills/fix/team-briefs/`" in an explainer paragraph), which are not runtime paths and would not cause a portability bug.

The test does allow HTML comment blocks and non-shell fenced code, but inline-backtick code spans in prose still trip it. I rewrote the prose to avoid the literals ("Both briefs are static files shipped with this skill under `team-briefs/`") — slightly less precise for human readers, but unambiguously portable.

**Suggestion for future tasks.md / test-skill-portability.sh**: either (a) allow inline `backticked` literals in prose paragraphs, or (b) explicitly tell the implementer "Do not reference `plugin-shelf/scripts/...` literals anywhere in the skill, even in explanatory prose — the test is stricter than FR-025 on purpose."

### `.kiln/qa/` and `.kiln/mistakes/` are NOT gitignored in this repo

Tasks.md T001 says "add `.kiln/fixes/` to `.gitignore` (one line after the existing `.kiln/qa/` entry)". There is no existing `.kiln/qa/` entry in `.gitignore` — `.kiln/qa/` and `.kiln/mistakes/` are currently tracked in the repo. I added `.kiln/fixes/` as a standalone entry under the "Workflow outputs" section.

This is not a blocker for the feature — the FR-021 intent (fixes not in PR diffs) is satisfied. But the spec's assumption that `.kiln/` children are already gitignored is wrong for this repo.

**Suggestion for future specs**: either fix the repo's gitignore proactively (gitignore all `.kiln/` children with `!.kiln/<kept>/` exceptions) or spec the new entry without cross-referencing an assumed-existing entry.

### Obsidian MCP not available in implementer environment

T015 requires writing `@manifest/types/fix.md` to the Obsidian vault via `mcp__claude_ai_obsidian-manifest__create_file`. That MCP is not in my tool surface this session. I authored the staging copy at `specs/.../assets/manifest-types/fix.md` (review-able in the PR) and documented the deferral in `blockers.md`.

This is the spec's anticipated fallback path — "If the MCP is unavailable at implementation time, note this in a `blockers.md` and continue — the staging copy is authoritative." Worked as designed.

### T018–T020 quickstart walks cannot run in non-interactive implementer environment

T018–T020 require a live `/kiln:fix` invocation on a seeded bug, MCP connectivity, and a consumer-repo setup. The implementer's environment cannot run these. Per the plan's Constitution Check Principle V ("True E2E for this feature would require a real Claude Code team-spawn in CI"), these walks are meant to be human-executed, not implementer-executed. I've left T018–T020 as `[ ]` with a blockers.md entry documenting the deferral.

**Suggestion for future tasks.md**: mark manual-only tasks with a `[HUMAN]` tag (parallel to `[P]`) so the implementer pipeline doesn't treat them as blockable on implementer completion.

## Tool failures

None. `jq`, `grep -F`, `awk`, `git`, `bash` all behaved as expected. The version-bump hook auto-incremented VERSION's 4th segment as the SKILL.md edit landed, which is the expected Claude Code kiln hook behavior.

## Template friction

### `compose-envelope.sh` flag naming

Originally the contract had `--project-name` listed alongside other flags. A close reading of the contract comment showed `resolve-project-name.sh` is invoked internally, not accepted as a flag. I removed `--project-name` from the flag list in the script and made the contract match its comment note. If a future caller needs to override, adding `--project-name "<override>"` would be a clean forward extension.

### write-local-record.sh and SHELF_SCRIPTS_DIR coupling

The helper must invoke `derive-proposal-slug.sh` which lives in `plugin-shelf/scripts/`. Per FR-014 + FR-025, the helper does this through the `SHELF_SCRIPTS_DIR` env var, exported by the skill before invocation. That means the helper is not standalone-runnable without setting `SHELF_SCRIPTS_DIR` first. Test setup handles this cleanly, but a reader outside this feature's context would need to know.

**Suggestion**: if the helper starts getting invoked from other skills, add a `SHELF_SCRIPTS_DIR` resolution fallback matching the one in SKILL.md. For now, the coupling is fine.

## Summary

MVP + Phases 1–7 + T017 complete and tested. Unit tests 8/8 green. Manual smoke walks (T018–T020) and Obsidian MCP write for `@manifest/types/fix.md` (T015 MCP step) are documented in `blockers.md` for auditor/human completion.
