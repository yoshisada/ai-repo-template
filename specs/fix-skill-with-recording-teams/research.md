# Research: Fix Skill with Recording Teams

Phase 0 research consolidated for `/plan`. Each decision is also referenced inline in plan.md.

## R1 — Plugin-scripts path discovery in consumer repos

**Decision**: Skill-level fallback chain that resolves `SHELF_SCRIPTS_DIR` from (a) `${WORKFLOW_PLUGIN_DIR}` if exported, (b) `./plugin-shelf/scripts` in source-repo runs, (c) the Claude plugin cache via a bounded `find` search.

**Rationale**: CLAUDE.md requires plugin portability via `${WORKFLOW_PLUGIN_DIR}`, but that variable is exported by the wheel dispatch layer, and this feature is explicitly not a wheel workflow (FR-023). Replicating the discovery in-skill keeps the reuse of shelf scripts while avoiding a wheel-workflow scope creep.

**Alternatives considered**:
- Hardcoding `plugin-shelf/scripts/...`: rejected (the silent-break pattern CLAUDE.md calls out as the exact portability bug).
- Copying the three shelf scripts into `plugin-kiln/scripts/`: rejected (duplicates logic, violates PRD Absolute Must #7 reuse directive).
- Shelling to a kiln CLI that resolves the path: rejected (no such CLI and adding one is out of scope).

## R2 — Parallel team spawn

**Decision**: Issue both `TeamCreate` + `TaskCreate` pairs in the same skill step (single main-chat tool-call batch). The teams then run their own agents concurrently.

**Rationale**: Skills are prompts that issue tool calls; "parallel" at this layer means "both spawn requests issued before either result is awaited." Matches the pattern established by `shelf:propose-manifest-improvement` and build-prd.

**Alternatives considered**:
- Serial spawn: rejected; doubles wall-clock.
- Shell backgrounding: inapplicable — we are not in a shell loop.

## R3 — Authoring `@manifest/types/fix.md`

**Decision**: Implementer commits a staging copy at `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md` AND writes the same content to the vault via `mcp__claude_ai_obsidian-manifest__create_file` during implementation.

**Rationale**: Obsidian vault files are outside the git tree, so a pure-MCP write leaves nothing for PR reviewers to critique. Staging the copy in the feature's spec dir keeps the authored schema reviewable and diff-able; dual-writing prevents drift.

**Alternatives considered**:
- MCP-only write: rejected; no PR artifact.
- Commit-only without MCP: rejected; `fix-record` team has nothing to validate against at runtime.
- Wheel sync integration: rejected; forbidden by FR-023.

## R4 — Team-brief template placement

**Decision**: Start inline in SKILL.md. If the edited SKILL.md exceeds 500 lines total, factor the two briefs into `plugin-kiln/skills/fix/team-briefs/{fix-record,fix-reflect}.md`.

**Rationale**: Inline templates maximize reviewer visibility of the exact prompts sent to each team. Factoring only on size overflow respects Principle VI without a premature abstraction.

**Alternatives considered**:
- Always inline: rejected preemptively (could violate 500-line ceiling).
- Always sibling files: rejected; extra indirection when templates are short.

## R5 — Envelope persistence path

**Decision**: `.kiln/fixes/.envelope-<timestamp>.json` — transient scratch file, gitignored (by FR-021 covering `.kiln/fixes/` as a whole), deleted after `TeamDelete`.

**Rationale**: Team briefs must stay small to respect SC-004's 3k-token ceiling. Referencing the envelope by path keeps brief text under a kilobyte even when the envelope's `fix_summary` or `files_changed` arrays are long.

**Alternatives considered**:
- Inline envelope in brief: rejected; bloats main-chat traffic.
- `.wheel/outputs/`: rejected; not a wheel workflow (FR-023).
- Team-create structured params: Claude Code's team-create API does not expose them.

## R6 — Testing strategy

**Decision**: Unit-test every helper script with pure bash `.sh` scripts under `plugin-kiln/scripts/fix-recording/__tests__/`. For team-agent behavior (actual `TeamCreate` + MCP call), rely on the manual smoke test in `quickstart.md`. The plugin's CI lacks team-spawn primitives, so fully automated E2E is not tractable in this pass.

**Rationale**: Mocking agent teams and MCPs in bash would require building a large parallel emulator — out of scope. The deterministic surfaces (envelope compose, slug, local writer, brief renderer, collision suffix, credential strip, project-name resolver) are fully testable and cover the feature's correctness-critical paths.

**Alternatives considered**:
- Mock-MCP harness: rejected; too much surface area for v1.
- Skip manual smoke: rejected; we would not know the end-to-end flow works.
- Write the tests in `bats`: rejected; `bats` is not installed in the repo (FR-024).

## R7 — Escalation detection

**Decision**: Compute `status` by comparing `git rev-parse HEAD` at skill start vs. after the debug loop. No new commit + 9-attempt exhaustion → `status = "escalated"` with `commit_hash = null`.

**Rationale**: Avoids adding new state tracking. `/kiln:debug-fix` already counts attempts; the absence of a new commit after the loop is the canonical "escalated" signal.

**Alternatives considered**:
- Track attempt count in a new state file: rejected; duplicates debug-fix's existing bookkeeping.
- Parse `debug-log.md`: rejected; it's free-form and not meant to be machine-read.

## R8 — Credential-stripping mechanism

**Decision**: `strip-credentials.sh` uses `grep -F -x -v -f <filtered-env-file>` after removing comment and blank lines from `.kiln/qa/.env.test`. Full-line match (`-x`) avoids over-stripping when a credential substring legitimately appears in a diagnostic.

**Rationale**: `.kiln/qa/.env.test` is line-oriented by construction — each line is either a `KEY=VALUE` or a comment or blank. Full-line equality is the strictest safe filter.

**Alternatives considered**:
- Substring match: rejected; false-positive risk strips legitimate text.
- Regex match on `[A-Z_]+=`: rejected; brittle against non-conforming credential shapes.
- No stripping (rely on prompt discipline): rejected; FR-026 mandates the filter.

## R9 — Collision handling semantics (FR-015)

**Decision**: `unique-filename.sh` tests `test -e` against each candidate, increments a numeric suffix (`-2`, `-3`, …) up to 999 before hard-stopping. Both local (`.kiln/fixes/`) and Obsidian (`@projects/<project>/fixes/`) callers use the same script for consistency.

**Rationale**: Maintains filename determinism from the same-slug starting point. 999 is a safety cap far exceeding any realistic same-day fix rate.

**Alternatives considered**:
- Timestamp suffix: rejected; produces noisier filenames and departs from the `-N` convention already used by `shelf:propose-manifest-improvement` (FR-019 there).
- Random suffix: rejected; non-deterministic, hurts reviewability.

## R10 — Reflect output path

**Decision**: `fix-reflect` writes its structured output to `.kiln/fixes/.reflect-output-<timestamp>.json` (not `.wheel/outputs/...`). The existing `validate-reflect-output.sh` does not care about the input path — it accepts the file as argv[1].

**Rationale**: Keeps the file out of `.wheel/outputs/` (we are not a wheel workflow per FR-023). Under `.kiln/fixes/` it inherits FR-021's gitignore.

**Alternatives considered**:
- `.wheel/outputs/reflect-output.json`: rejected; pollutes the wheel state area with non-wheel work.
- Inline JSON in `SendMessage`: rejected; cannot invoke `validate-reflect-output.sh` on stdin.
