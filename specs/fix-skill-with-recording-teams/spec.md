# Feature Specification: Fix Skill with Recording Teams

**Feature Branch**: `build/fix-skill-with-recording-teams-20260420`
**Created**: 2026-04-20
**Status**: Draft
**Input**: PRD: `docs/features/2026-04-20-fix-skill-with-recording-teams/PRD.md`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Successful fix produces a durable record (Priority: P1)

A developer invokes `/kiln:fix` on a real bug. The debug loop runs in main chat (collaborative, redirectable), a fix is identified, tests pass, and a commit lands. Immediately after the commit, the skill composes a complete fix envelope in main chat, writes a local fix record, and spawns two parallel agent teams — `fix-record` writes the corresponding Obsidian note under `@projects/<project>/fixes/`, and `fix-reflect` considers whether the fix reveals a manifest/template gap and (only if so) files a proposal in `@inbox/open/`. The developer returns to their work; both artifacts exist automatically.

**Why this priority**: This is the primary flow and the feature's core value. Without it, fix knowledge continues to die at the commit boundary. P1 because every other story depends on this pipeline existing.

**Independent Test**: Invoke `/kiln:fix` on a reproducible test-failure bug, let the loop fix it, and verify that `.kiln/fixes/<YYYY-MM-DD>-<slug>.md` exists locally, that a matching note exists at `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` in the vault, and that both teams were deleted on completion.

**Acceptance Scenarios**:

1. **Given** a reproducible bug and a clean repo, **When** `/kiln:fix` runs the debug loop in main chat to a successful commit, **Then** a local file is written at `.kiln/fixes/<YYYY-MM-DD>-<slug>.md` **before** any team is spawned.
2. **Given** the local record exists, **When** `/kiln:fix` spawns the `fix-record` and `fix-reflect` teams, **Then** the two teams are created in the same skill step (parallel, not serial) and both receive the complete fix envelope.
3. **Given** the fix-record team runs, **When** it writes via `mcp__claude_ai_obsidian-manifest__create_file`, **Then** exactly one note appears at `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` with frontmatter `type: fix` and five H2 sections in the fixed order.
4. **Given** both teams have reached a terminal state, **When** `/kiln:fix` hands control back to the user, **Then** both teams have been shut down via `TeamDelete` and no orphans remain.

---

### User Story 2 - Escalated fix still produces a record (Priority: P1)

A developer invokes `/kiln:fix` on a stubborn bug. The debug loop exhausts its 9 attempts without landing a passing fix. Instead of silently giving up, the skill composes an envelope with `status: escalated`, `commit_hash: null`, `fix_summary` describing the techniques tried, and `files_changed` listing the files inspected. It then runs the same recording pipeline as a successful fix — local record + Obsidian note + optional manifest-improvement reflection — so the investigation is preserved as training data for future agents.

**Why this priority**: Escalated fixes are exactly the signal worth capturing — another agent hitting the same bug should not re-derive the same failed approaches. P1 because dropping escalated fix records is the biggest missed-signal case today.

**Independent Test**: Force the debug loop to escalate (e.g., run against a bug the debugger cannot fix in 9 attempts or invoke with a simulated-escalation path). Verify both the local file and the Obsidian note exist, both with `status: escalated`, `commit: null`, and a populated `## Escalation notes` section.

**Acceptance Scenarios**:

1. **Given** the debug loop exhausts 9 attempts with no passing fix, **When** `/kiln:fix` composes the envelope, **Then** `status: escalated`, `commit_hash: null`, `fix_summary` describes techniques tried, and `files_changed` lists files inspected (not modified).
2. **Given** an escalated envelope, **When** the local record is written, **Then** the file has `status: escalated` frontmatter and a populated `## Escalation notes` section (techniques + diagnostics), with `## Files changed` listing inspected files.
3. **Given** an escalated envelope, **When** the `fix-record` team writes to Obsidian, **Then** the Obsidian note carries the same `status: escalated` frontmatter and escalation-notes body as the local record.
4. **Given** an escalated envelope, **When** `fix-reflect` evaluates it, **Then** the same reflect + exact-patch gate rules apply — no special-cased behavior because the fix failed.

---

### User Story 3 - Debug loop stays in main chat (Priority: P1)

A developer invokes `/kiln:fix` on a bug they need to collaborate on — mid-loop they want to redirect the debugger ("no, check `auth.ts` instead", "try logging the header value"). The debug loop runs entirely in main chat exactly as it does today — no sub-agent, no wheel workflow, no team spawn during diagnosis or fix. Only after the commit (or escalation) does any team appear. Redirecting mid-loop works identically to pre-feature behavior.

**Why this priority**: This is the constraint that ruled out the wheel-workflow approach. If collaborative debugging regresses, the feature has destroyed more value than it added. P1 because the "no regression" promise is the thing making the rest of this feature palatable.

**Independent Test**: Run five interactive `/fix` sessions where the user redirects mid-loop at least once. Verify that (a) each redirect lands in the same main-chat debug loop the user sees today, (b) no `TeamCreate` / `TaskCreate` / wheel-activate call occurs before the commit step, and (c) main-chat message flow is visually indistinguishable from pre-feature.

**Acceptance Scenarios**:

1. **Given** a `/kiln:fix` invocation is in the debug loop, **When** the skill is inspecting the conversation's tool-use log up to and including the commit, **Then** no `TeamCreate`, `TaskCreate`, `SendMessage` (team-directed), or wheel-workflow dispatch appears.
2. **Given** a user message mid-loop redirects the agent ("try X"), **When** the skill continues, **Then** the debugger agent receives the redirect in main chat and adapts without any team-spawn step interposed.
3. **Given** the fix commit lands, **When** the skill proceeds to the recording step, **Then** that step is the first place in the invocation where team primitives are used.

---

### User Story 4 - Reflect is silent when no manifest improvement is warranted (Priority: P2)

A developer invokes `/kiln:fix` on a straightforward typo bug. The debug loop fixes it, records run, and `fix-reflect` considers the envelope. Nothing about this fix reveals a schema or template gap in `@manifest/`. The reflect team emits `{"skip": true}`, the exact-patch gate confirms no actionable improvement, and no file is written to `@inbox/open/`. No log line. No user-visible artifact. The local record and Obsidian note still exist — the reflection was simply a no-op.

**Why this priority**: Noise in `@inbox/open/` is the failure mode that would cause maintainers to stop triaging the channel. P2 because User Stories 1–3 define the happy-path pipeline; this story defends the quality bar.

**Independent Test**: Invoke `/kiln:fix` on a trivial typo fix (context unlikely to reveal a manifest gap). Verify `.kiln/fixes/` and `@projects/<project>/fixes/` gain a file, but `@inbox/open/` gains nothing and no `fix-reflect` log line surfaces in main chat.

**Acceptance Scenarios**:

1. **Given** `fix-reflect` produces `{"skip": true}`, **When** its exact-patch gate runs, **Then** no file is written to `@inbox/open/` and no user-visible log line is emitted.
2. **Given** `fix-reflect` produces `skip: false` but `current` does not appear verbatim in the target file, **When** the gate runs, **Then** the decision is forced to skip and no file is written.
3. **Given** `fix-reflect` produces `skip: false` targeting a path outside `@manifest/types/*.md` / `@manifest/templates/*.md`, **When** the gate runs, **Then** the decision is forced to skip and no file is written.

---

### User Story 5 - Reflect produces a proposal when a manifest gap is grounded in the fix (Priority: P2)

A developer invokes `/kiln:fix` on a bug whose root cause involves a schema-level gap — e.g., the `@manifest/types/project-dashboard.md` type lacks a field that would have prevented the bug from being filed ambiguously. `fix-reflect` identifies the gap, names the target file, extracts the verbatim `current` text it wants to replace, writes the exact proposed text, and grounds the `why` in a specific artifact from the fix envelope (issue text, commit hash, or file path). The proposal lands at `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` and follows the same four-section schema as proposals from `shelf:propose-manifest-improvement`. A maintainer can accept it in one edit.

**Why this priority**: This is where the feature's reflection value surfaces. P2 because it piggybacks on the existing manifest-improvement gate and so has a limited blast radius — the bar is already defined.

**Independent Test**: Seed a `/fix` run whose envelope clearly names a manifest-type file (or template) as the preventable root cause. Verify a single file appears at `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` with `type: proposal`, `target: <path>`, `date: <YYYY-MM-DD>` in frontmatter and four H2 sections `## Target`, `## Current`, `## Proposed`, `## Why` in order. The `current` text must exist verbatim in the target file at write time.

**Acceptance Scenarios**:

1. **Given** `fix-reflect` outputs `skip: false` with all fields populated and the target matching `@manifest/types/*.md` or `@manifest/templates/*.md`, **When** the exact-patch gate validates, **Then** exactly one file is written at `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md`.
2. **Given** the proposal file exists, **When** a maintainer opens it, **Then** it contains YAML frontmatter with `type: proposal`, `target: <path>`, `date: <YYYY-MM-DD>`, followed by four H2 sections in exact order: `## Target`, `## Current`, `## Proposed`, `## Why`.
3. **Given** the proposal's `why` sentence, **When** the slug is derived, **Then** it matches the slug `plugin-shelf/scripts/derive-proposal-slug.sh` produces for the same input (deterministic, kebab-case, ≤50 chars).

---

### User Story 6 - Main-chat token overhead stays tiny (Priority: P2)

A developer invokes `/kiln:fix` and watches the main-chat transcript. After the commit lands, they see: one brief team-spawn block (fix-record team brief), one brief team-spawn block (fix-reflect team brief), and — only if needed — one or two terse `SendMessage` escape-hatch exchanges. Total visible team-related traffic is ≤3k tokens per invocation. The bulk of each team's work (Obsidian writes, reflect reasoning, validator output) lives inside each team's own context and never surfaces to main chat.

**Why this priority**: The entire reason this is two agent teams instead of inline main-chat work is to keep main chat small. P2 because it is a quality constraint rather than a correctness one — the feature still works if overhead is higher, just worse.

**Independent Test**: Transcribe 10 representative `/fix` invocations and measure the total tokens of team-related message traffic visible in main chat per run. Assert mean ≤3000 tokens and no outliers exceed 5000.

**Acceptance Scenarios**:

1. **Given** a `/fix` run producing a successful fix with no team disambiguation, **When** team traffic visible in main chat is measured, **Then** it is under 3k tokens.
2. **Given** the `fix-record` team hits a path-resolution ambiguity, **When** it uses the `SendMessage` escape hatch, **Then** the message is a single short disambiguation ask, not a full state dump.
3. **Given** the envelope is complete per FR-001, **When** the teams run, **Then** `SendMessage` is used zero times in the common case.

---

### User Story 7 - Context isolation: teams see the envelope and nothing else (Priority: P2)

A developer is curious about what each team can see. The `fix-record` team's brief contains only the envelope fields it needs (plus the shared path-resolution and MCP call instructions). The `fix-reflect` team's brief contains only the envelope fields it needs (plus the reflect + exact-patch instructions). Neither team has access to the main-chat debug-loop transcript, the prior `diagnose`/`fix`/`verify` tool results, or any file beyond what the envelope references. If a team needs something outside the envelope, it has one escape hatch — `SendMessage` to main — and the envelope is designed so that need is rare.

**Why this priority**: Isolation is the mechanism that makes token overhead tiny and reasoning tight. P2 because it's the implementation contract for User Story 6's outcome.

**Independent Test**: Inspect each team's task brief as authored by the skill. Verify no brief contains the raw debug-loop transcript, `debug-log.md`, or file reads beyond the paths the envelope names. Verify the briefs are static text parameterized only by envelope fields.

**Acceptance Scenarios**:

1. **Given** the skill composes a team brief, **When** the brief is inspected, **Then** it contains only envelope fields + static instructions — no main-chat transcript, no debugger tool output, no prior agent reasoning.
2. **Given** a team is spawned, **When** its first tool call is inspected, **Then** it does not read `debug-log.md` or any main-chat artifact beyond what the envelope references.
3. **Given** a team needs clarification, **When** it chooses between a `SendMessage` ask and expanding its own file reads, **Then** the brief's explicit instruction is to prefer the escape hatch for path/project-name ambiguity only.

---

### User Story 8 - Obsidian MCP unavailability is non-blocking (Priority: P3)

A developer invokes `/kiln:fix` in an environment where the Obsidian MCP is not connected (Obsidian closed, vault not bound, etc.). The debug loop runs, the fix lands, and the local record at `.kiln/fixes/` is written successfully. When the `fix-record` team attempts the MCP call, it fails. The team emits one warning, exits 0, and the skill reports the fix as successful. No partial file is written, no retry burns time.

**Why this priority**: MCP availability is best-effort; losing one Obsidian note per offline run is acceptable. P3 because blocking the fix on MCP availability would be a much worse failure mode.

**Independent Test**: Disable the Obsidian MCP (or simulate its unavailability) and run `/kiln:fix`. Verify the local record exists, exactly one warning surfaces in main chat (via `SendMessage`), the skill reports success, and `TeamDelete` still runs for both teams.

**Acceptance Scenarios**:

1. **Given** the Obsidian MCP is unavailable, **When** `fix-record` attempts `mcp__claude_ai_obsidian-manifest__create_file`, **Then** the team emits exactly one warning, exits 0, and does NOT retry.
2. **Given** the MCP is unavailable, **When** the skill finishes, **Then** the local file at `.kiln/fixes/` still exists and the skill's user-facing report marks the fix as successful.
3. **Given** either team hits an internal error that would normally stall, **When** the skill cleans up, **Then** `TeamDelete` still runs for both teams — no orphaned teams remain.

---

### User Story 9 - New manifest type `fix.md` shipped with the feature (Priority: P2)

A maintainer reviewing the vault sees a new file at `@manifest/types/fix.md` that defines the schema for all fix records. Frontmatter requirements are listed: `type: fix`, `date`, `status: fixed | escalated`, `commit`, `resolves_issue`, `files_changed`, `tags` (drawn from a published axis). Body sections are listed in their fixed order: `## Issue`, `## Root cause`, `## Fix`, `## Files changed`, `## Escalation notes`. The type file models the `@manifest/types/mistake.md` structure so existing review tooling and conventions apply without special-casing.

**Why this priority**: Without an authored type, the fix records flowing into the vault are schema-less and drift immediately. P2 because the pipeline can function for a short time without the type file but quality degrades without it.

**Independent Test**: After the feature lands, read `@manifest/types/fix.md`. Verify the frontmatter schema, the five H2 sections in order, a published tag-axis vocabulary (`fix/*`, `topic/*`, plus one of `language/*|framework/*|lib/*|infra/*|testing/*`), and prose guidance paralleling `@manifest/types/mistake.md`. Verify every file written by `fix-record` is schema-conformant against this type.

**Acceptance Scenarios**:

1. **Given** the feature has been deployed, **When** `@manifest/types/fix.md` is read, **Then** it declares required frontmatter fields, enumerates the five H2 body sections in order, and names the initial tag axes.
2. **Given** a fix-record team writes a note, **When** the note is validated against `@manifest/types/fix.md`, **Then** every required field and section is present, in the mandated order, with the correct types.
3. **Given** a maintainer already knows `@manifest/types/mistake.md`, **When** they read `fix.md`, **Then** the structure is visibly parallel — same frontmatter-then-sections shape, same tag-axis discipline.

---

### User Story 10 - Plugin portability: fix-reflect scripts resolve in consumer repos (Priority: P3)

A consumer installs the kiln plugin into a repo that does NOT have `plugin-kiln/` or `plugin-shelf/` checked out. A developer in that repo runs `/kiln:fix`. The `fix-reflect` team invokes the exact-patch gate via `check-manifest-target-exists.sh` and `validate-reflect-output.sh`. The team resolves these scripts from the plugin cache path (via `${WORKFLOW_PLUGIN_DIR}` or the skill-portable equivalent), not via a repo-relative `plugin-shelf/scripts/...` path that would silently be missing.

**Why this priority**: The portability rule is non-negotiable per CLAUDE.md. P3 because this feature does not introduce new wheel workflows — it reuses existing shelf scripts through the kiln skill. The risk is that a quick-and-dirty implementation references `plugin-shelf/scripts/...` directly.

**Independent Test**: Install the kiln plugin into a clean consumer repo (no plugin source checked out). Invoke `/kiln:fix` with an envelope that would otherwise produce a reflect proposal. Verify the exact-patch gate scripts are found and executed — no `No such file or directory` errors, no silent empty-output failure.

**Acceptance Scenarios**:

1. **Given** the `fix-reflect` team brief references the exact-patch gate scripts, **When** the brief is inspected, **Then** every script path resolves via a plugin-dir-aware mechanism — no hardcoded `plugin-shelf/scripts/...` or `plugin-kiln/skills/...` path.
2. **Given** a consumer repo with the kiln plugin installed via cache, **When** `/kiln:fix` runs to the reflect stage, **Then** the script execution succeeds with no "No such file or directory" error.
3. **Given** the team-brief prompts contain shell snippets, **When** the snippets are parsed, **Then** they rely on variables the skill exports before team spawn (envelope path, scripts path) rather than on cwd-relative paths.

---

### Edge Cases

- **Debug loop escalation mid-commit-attempt**: the 9th attempt produced a commit that then failed verification. Treat as escalated (no successful fix state), carry the commit hash in `fix_summary` as "last attempted commit" but set `commit_hash: null` and `status: escalated`.
- **No `feature_spec_path`** found: the bug does not correspond to any spec in `specs/`. Envelope sets `feature_spec_path: null`; Obsidian note omits the spec wikilink; no user prompt is required.
- **No `resolves_issue`** provided: the developer invoked `/fix` with a free-text description, no issue number. Envelope sets `resolves_issue: null`; note body omits the issue wikilink.
- **Same-day same-slug collision**: two `/fix` invocations the same day whose issue summaries derive the same slug — disambiguate with `-2`, `-3`, … suffix; never overwrite.
- **Project-name unresolvable**: no `.shelf-config`, no git repo, or `basename` returns empty. Local write still succeeds (write goes to `.kiln/fixes/` regardless); Obsidian write silently skips with a one-line warn; skill still reports success.
- **`.shelf-config` present but malformed**: file exists but has no `project_name=<slug>` line. Fall through to `basename` per FR-013.
- **MCP partially available** (connected to wrong vault): treat as unavailable — warn once, exit 0, local file persists. Same pattern as `shelf:propose-manifest-improvement` FR-015.
- **Envelope contains credential-looking string**: a diagnostic output from `.kiln/qa/.env.test` leaks into `fix_summary`. The skill MUST strip or refuse to compose an envelope whose `fix_summary` contains any line from `.kiln/qa/.env.test`.
- **Very fast typo fix**: the recording stage wall-clock may exceed the debug loop itself. Accepted — no `--no-record` flag in v1; future work per PRD.
- **Team reads beyond its brief**: a team attempts to read `debug-log.md` or the main-chat transcript. Team briefs MUST explicitly forbid this and declare the envelope as the complete input (FR-018 in PRD).
- **Reflect identifies multiple improvements**: only one proposal per `/fix` invocation in v1, matching `shelf:propose-manifest-improvement`. Extras are dropped.
- **Malformed reflect output**: if the `fix-reflect` agent produces unparseable JSON, treat as skip (no file, exit 0). Same semantics as `validate-reflect-output.sh` FR-018.

## Requirements *(mandatory)*

### Functional Requirements

#### Absolute musts (carried from PRD)

- **FR-001**: `/kiln:fix` MUST, after the debug loop terminates (successful commit OR 9-attempt escalation), compose a complete fix envelope containing these fields in this order: `issue`, `root_cause`, `fix_summary`, `files_changed` (array), `commit_hash` (hash or null), `feature_spec_path` (path or null), `project_name` (string or null), `resolves_issue` (ref or null), `status` (`fixed` | `escalated`).
- **FR-002**: `/kiln:fix` MUST, before spawning either team, append a local fix record at `.kiln/fixes/<YYYY-MM-DD>-<slug>.md`. This write happens inline in the skill (bash block), NOT inside either team.
- **FR-003**: `/kiln:fix` MUST spawn `fix-record` and `fix-reflect` as two independent agent teams in parallel after the local write lands. Both teams MUST be given the complete envelope from FR-001 as their sole data input.
- **FR-004**: The `fix-record` team MUST write exactly one file to `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` via `mcp__claude_ai_obsidian-manifest__create_file`. Direct filesystem writes to the vault are prohibited.
- **FR-005**: The feature MUST author a new manifest type at `@manifest/types/fix.md` modeled on `@manifest/types/mistake.md`.
- **FR-006**: `@manifest/types/fix.md` MUST define:
  - Required frontmatter fields: `type: fix`, `date: <YYYY-MM-DD>`, `status: fixed | escalated`, `commit: <hash or null>`, `resolves_issue: <ref or null>`, `files_changed: [<path>, ...]`, `tags: [...]`.
  - Required tag axes (initial vocabulary, may refine post-launch):
    - `fix/*` one of: `fix/runtime-error`, `fix/regression`, `fix/test-failure`, `fix/build-failure`, `fix/ui`, `fix/performance`, `fix/documentation`.
    - `topic/*` free-form topic axis (inherited convention).
    - One of `language/*` | `framework/*` | `lib/*` | `infra/*` | `testing/*` (stack axis, inherited convention).
  - Body sections in this fixed order: `## Issue`, `## Root cause`, `## Fix`, `## Files changed`, `## Escalation notes` (the last section is `_none_` for successful fixes, populated for escalated fixes).
- **FR-007**: The Obsidian fix note body MUST include:
  - A wikilink to the feature spec, if `feature_spec_path` is non-null.
  - A wikilink or explicit reference to the resolving issue, if `resolves_issue` is non-null.
  - The commit hash as plain text (not a wikilink — commits live outside the vault).
- **FR-008**: The `fix-reflect` team MUST use the same exact-patch gate as `shelf:propose-manifest-improvement`:
  - Target path MUST match `@manifest/types/*.md` or `@manifest/templates/*.md`. Any target outside these globs forces `skip: true`.
  - The `current` text MUST appear verbatim (byte-for-byte) in the target file at write time; otherwise `skip: true`.
  - The `why` sentence MUST cite at least one concrete artifact from the fix envelope (issue text, commit hash, a `files_changed` entry, `root_cause` phrase, or `feature_spec_path`). Generic opinions force `skip: true`.
  - The gate MUST reuse `plugin-shelf/scripts/check-manifest-target-exists.sh` + `plugin-shelf/scripts/validate-reflect-output.sh` (no reimplementation).
- **FR-009**: The `fix-reflect` team MUST write to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` if and only if the exact-patch gate approves. Otherwise it MUST be silent — no file, no log line, no user-visible artifact.
- **FR-010**: The `fix-reflect` team MAY `SendMessage` main chat and/or the `fix-record` teammate for disambiguation. Such messages MUST be the exception, not the default. The envelope from FR-001 is designed to make zero back-talk the common case.
- **FR-011**: The `fix-record` team MAY `SendMessage` main chat ONLY for path-resolution escape (ambiguous project name, missing `feature_spec_path`). It MUST NOT ask main to compose or review the note body.
- **FR-012**: On 9-attempt escalation, `/kiln:fix` MUST still run the complete recording pipeline (FR-002 local write + FR-003 two-team spawn). The envelope carries `status: escalated`, `commit_hash: null`, `fix_summary` describes techniques tried, `files_changed` lists files inspected.
- **FR-013**: Project-name resolution MUST follow this order:
  1. Read `project_name=<slug>` from `.shelf-config` at repo root if present and non-empty.
  2. Else `basename "$(git rev-parse --show-toplevel)"`.
  3. Else `project_name: null` — Obsidian write silently skips with a one-line warn; local write always proceeds.
- **FR-014**: Slug derivation for both local and Obsidian filenames MUST be produced by `plugin-shelf/scripts/derive-proposal-slug.sh`. The skill and the teams MUST NOT reimplement slug logic. If an equivalent is needed from a new callsite, it MUST invoke the script directly.
- **FR-015**: Same-day filename collisions (local or Obsidian) MUST disambiguate by appending `-2`, `-3`, … to the slug portion. Existing files MUST NEVER be overwritten.
- **FR-016**: Obsidian MCP unavailability MUST NOT block the skill. If `mcp__claude_ai_obsidian-manifest__create_file` is unavailable, the `fix-record` team MUST emit a single warning (via `SendMessage` to main or a brief task-result line), exit 0, and the local `.kiln/fixes/` file persists. The skill reports the fix as successful.
- **FR-017**: Both teams MUST be shut down via `TeamDelete` after reaching terminal state (success, silent skip, MCP-unavailable warn, or internal error). No orphaned teams MUST remain when `/kiln:fix` returns control to the user.
- **FR-018**: Teams MUST NOT read the main-chat transcript, any `debug-log.md` file, prior tool results, or any file beyond what the envelope references. Team briefs MUST declare the envelope as the complete input and forbid out-of-brief reads.
- **FR-019**: `/kiln:fix` MUST NOT invoke `shelf:shelf-full-sync` (or any wheel workflow that in turn invokes it) at any point in this flow. Direct Obsidian write via MCP is the only vault-write mechanism.
- **FR-020**: The debug loop (Steps 2b–5 of the current `/kiln:fix` skill) MUST remain in main chat unchanged. No `TeamCreate`, `TaskCreate`, `SendMessage` to a teammate, or wheel-activate call MUST occur before the commit (or escalation) step.

#### Implementation-level requirements derived from absolute musts

- **FR-021**: `.kiln/fixes/` MUST be added to `.gitignore` (alongside the existing `.kiln/qa/` entry) so fix records do not clutter every PR diff.
- **FR-022**: The feature MUST NOT introduce new dependencies, new package.json entries, new scripting languages, or new test frameworks. Existing bash, existing MCPs, existing agent-teams primitives are the full tech surface.
- **FR-023**: The feature MUST NOT introduce a wheel workflow. No file under `plugin-kiln/workflows/` or `plugin-shelf/workflows/` is added or modified by this feature.
- **FR-024**: The feature MUST NOT introduce a `bats`, `vitest`, or `pytest` suite. Tests MUST be pure bash `.sh` scripts (the repo does not have bats installed).
- **FR-025**: Any script path referenced in the skill or team briefs MUST resolve in a consumer repo without `plugin-shelf/` or `plugin-kiln/` checked out. Specifically: the skill MUST export a `SHELF_SCRIPTS_DIR` (or equivalent) before team spawn, resolved via `${WORKFLOW_PLUGIN_DIR}`-style discovery (or the nearest skill-portable equivalent), and team briefs MUST reference scripts via that variable — never a hardcoded `plugin-shelf/scripts/...` path.
- **FR-026**: The envelope composition MUST strip any line from `.kiln/qa/.env.test` out of `fix_summary` and `root_cause` before the envelope is used. Raw credentials MUST NOT leave main chat, the local record, or any team brief.
- **FR-027**: The envelope JSON MUST be persisted to a file (e.g., `.kiln/fixes/.envelope-<timestamp>.json`) accessible to both teams. That file is transient scratch state and MUST be gitignored (covered by FR-021 — the whole `.kiln/fixes/` tree is gitignored). Team briefs reference the envelope by path; this bounds team-brief token size to roughly the brief text itself.
- **FR-028**: The two team-brief prompts MUST be authored as two separate, static prompt strings stored in the skill (no dynamic generation per-run beyond substituting the envelope path, the scripts-dir path, and the per-run slug/date). Test-ability and review-ability rely on the briefs being inspectable as literal text.
- **FR-029**: `/kiln:fix` MUST ensure the directory `.kiln/fixes/` exists (creating it if absent) before the local write in FR-002.
- **FR-030**: Tests for this feature MUST cover, at minimum: (a) envelope composition produces the FR-001 shape for a successful fix, (b) envelope composition produces `status: escalated` + `commit_hash: null` for an escalated run, (c) envelope composition strips credentials per FR-026, (d) local-record writer produces the FR-006 section shape for successful and escalated envelopes, (e) slug derivation invokes `derive-proposal-slug.sh` and produces the same output as the shelf script, (f) collision disambiguator produces `-2`/`-3` suffix and never overwrites, (g) Obsidian-unavailability path writes local file and returns success, (h) team briefs reference scripts via the portable variable and do not hardcode `plugin-shelf/scripts/...`.

### Key Entities

- **Fix Envelope**: The canonical record of one `/kiln:fix` terminal state. Composed in main chat after the debug loop terminates. Fields: `issue`, `root_cause`, `fix_summary`, `files_changed[]`, `commit_hash` (nullable), `feature_spec_path` (nullable), `project_name` (nullable), `resolves_issue` (nullable), `status` (`fixed`|`escalated`). Persisted to a transient file under `.kiln/fixes/` and passed by path to both teams. Not user-visible (developers see the rendered fix-record note, not the JSON).
- **Local Fix Record**: The markdown file at `.kiln/fixes/<YYYY-MM-DD>-<slug>.md`. Written inline by the skill. Gitignored. Mirrors the Obsidian note's content 1:1.
- **Obsidian Fix Note**: The markdown file at `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md`. Written by the `fix-record` team via Obsidian MCP. Schema-conformant to `@manifest/types/fix.md`.
- **Manifest Type `fix.md`**: The new schema file at `@manifest/types/fix.md` authored by this feature, modeled on `@manifest/types/mistake.md`. Defines frontmatter fields, body sections, and tag axes for fix notes.
- **Manifest-Improvement Proposal (fix-sourced)**: The optional markdown file at `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` written by the `fix-reflect` team when the exact-patch gate approves. Identical shape to proposals from `shelf:propose-manifest-improvement`.
- **Fix-Record Team**: Short-lived agent team spawned after the local write. Sole responsibility: write the Obsidian fix note via MCP. Deleted on terminal state.
- **Fix-Reflect Team**: Short-lived agent team spawned after the local write, in parallel with fix-record. Sole responsibility: produce a reflect output, run the exact-patch gate, and (if approved) write one proposal file to `@inbox/open/`. Deleted on terminal state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001 — Recording coverage (PRD M1)**: 100% of terminal `/kiln:fix` invocations (successful AND escalated) produce a local file at `.kiln/fixes/<YYYY-MM-DD>-<slug>.md`, measured over the first 30 days following feature deployment. Obsidian coverage is 100% for invocations where `project_name` resolved to a non-null value (per FR-013); invocations falling through to case (3) silent-skip are excluded.
- **SC-002 — Reflect silent rate (PRD M2)**: ≥70% of `fix-reflect` runs produce no file in `@inbox/open/`. Parallels `shelf:propose-manifest-improvement`'s silent-on-no-op expectation. Measured monthly.
- **SC-003 — Reflect precision (PRD M3)**: ≥80% of `fix-reflect`-authored `@inbox/open/` proposals are accepted by the maintainer (merged into `@manifest/` as-written, possibly with minor edits) within 7 days of being written. Measured monthly over the first 90 days.
- **SC-004 — Main-chat token overhead (PRD M4)**: Mean team-related message traffic visible in main chat is ≤3k tokens per `/kiln:fix` invocation. No outlier exceeds 5k tokens. Measured by inspecting transcripts of 10 representative runs.
- **SC-005 — Zero main-chat debug regression (PRD M5)**: Collaborative-debug user flows work end-to-end. 5 interactive `/kiln:fix` sessions where the user redirects the debugger mid-loop ("try X") all land the redirect in the same main-chat debug loop as pre-feature runs.
- **SC-006 — Silent-on-no-improvement invariant**: 0 files are created in `@inbox/open/` on `/fix` runs where `fix-reflect` emits `skip: true` or the exact-patch gate rejects. Measured over 20 consecutive steady-state runs — zero variance tolerated.
- **SC-007 — Schema conformance**: 100% of fix notes written by `fix-record` validate against `@manifest/types/fix.md` — required frontmatter fields present, five H2 sections in the mandated order, tag axes populated. Any deviation is a defect.
- **SC-008 — Plugin portability**: `/kiln:fix` runs successfully in at least one consumer repo that does not have `plugin-kiln/` or `plugin-shelf/` checked out. Scripts are found, executed, and the full pipeline completes — no "No such file or directory" errors.
- **SC-009 — No orphan teams**: 0 `/kiln:fix` invocations leave behind a living team (neither `fix-record` nor `fix-reflect`) after control returns to the user. Verified by a post-run check listing active teams after 20 consecutive runs.
- **SC-010 — Non-blocking MCP outage**: 100% of `/fix` runs invoked with the Obsidian MCP unavailable still complete successfully, with the local record written and exactly one warning surfaced to main chat. Measured on 5 forced-outage runs.

## Assumptions

- The Obsidian manifest vault MCP (`mcp__claude_ai_obsidian-manifest__create_file`) is the canonical write path for vault files — same assumption as `shelf:propose-manifest-improvement`.
- `.shelf-config` is the canonical source for `project_name` when present, aligning with `plugin-shelf` conventions.
- Claude Code agent teams (`TeamCreate` / `TaskCreate` / `SendMessage` / `TeamDelete`) are reliably available in consumer environments — validated by `shelf:propose-manifest-improvement` (PR #114, merged) and the build-prd pipeline's retrospective flow.
- Maintainers triage `@inbox/open/` at least weekly so fix-reflect proposals do not accumulate stale — same assumption as `shelf:propose-manifest-improvement`.
- The Claude Code concurrent-team limit comfortably accommodates two additional short-lived teams. Current pipelines run 6–8 teammates; two more are negligible.
- `@manifest/types/mistake.md` is a reasonable template for `@manifest/types/fix.md`: same frontmatter-then-sections shape, same tag-axis discipline.
- The existing shelf scripts `derive-proposal-slug.sh`, `check-manifest-target-exists.sh`, and `validate-reflect-output.sh` are stable and suitable for reuse as-is — no forks, no wrappers beyond the path-resolution variable.
- The `/kiln:fix` debug loop's existing post-commit state (working tree clean, commit hash reachable, last-attempted files in git) is reliable enough to compose the envelope without new instrumentation.
- Credential-stripping (FR-026) is tractable with a `grep -v` against lines of `.kiln/qa/.env.test` — the test-env file is short and line-oriented by construction.
- Shell-level parallelism (two `TeamCreate` calls issued in the same skill step) is sufficient for "parallel" — we do not need a job-control primitive.
- Developers invoking `/kiln:fix` expect the recording stage to add small but noticeable wall-clock time (team spawn + MCP write). Acceptable in v1; a `--no-record` flag is out of scope.

## Open Questions — Resolved

The PRD's Open Questions section raised four items; all are resolved in this spec per team-lead guidance:

1. **Parallel vs serial team spawn**: **Parallel** (FR-003). Envelope is complete; no data dependency between teams.
2. **`.kiln/fixes/` gitignored vs committed**: **Gitignored** (FR-021). Matches `.kiln/qa/` and `.kiln/mistakes/` conventions; keeps PR diffs clean.
3. **Standalone `fix-reflect` skill**: **Deferred**. Embedded in `/kiln:fix` only for v1. If maintainers ask for standalone invocation later, the reflect prompt + exact-patch gate wiring factor cleanly into a sibling skill.
4. **Tag vocabulary for `fix.md`**: Published in FR-006 — `fix/runtime-error`, `fix/regression`, `fix/test-failure`, `fix/build-failure`, `fix/ui`, `fix/performance`, `fix/documentation`, plus inherited `topic/*` and one of `language/*|framework/*|lib/*|infra/*|testing/*`. Refinement is allowed post-launch via the normal manifest-improvement channel.
