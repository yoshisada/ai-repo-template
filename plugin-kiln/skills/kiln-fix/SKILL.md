---
name: "kiln-fix"
description: "Fix a bug without creating a new PRD or spec. Describe the issue (or pass a GitHub issue number) and the debugger will diagnose, fix, and verify it using the existing spec as context."
---

# Fix

Fix a bug in an already-implemented feature. No new PRD, no new spec, no kiln ceremony — just find the bug and fix it.

```text
$ARGUMENTS
```

## Usage

```
/kiln:kiln-fix The login button doesn't redirect to the dashboard after successful auth
/kiln:kiln-fix #42
/kiln:kiln-fix https://github.com/owner/repo/issues/42
/kiln:kiln-fix Tests are failing with "Cannot read property 'map' of undefined" in UserList component
/kiln:kiln-fix The app is slow when loading the settings page — takes 8+ seconds
/kiln:kiln-fix Build fails with TS2322 in src/components/Header.tsx
```

## Step 1: Parse the Issue

### If a GitHub issue number or URL was provided:
```bash
# Fetch the issue details
gh issue view [number] --json title,body,labels,comments
```
Extract: title, description, reproduction steps, labels (bug/enhancement), and any discussion.

### If a text description was provided:
Use it directly as the issue description.

### If no arguments:
Ask the user: "What's the bug? Include the error message, what you expected, and what actually happened."

## Step 2: Find the Spec Context

The bug is in something that was already built. Find the spec that covers it:

```bash
# Search specs for related FRs or user stories
grep -r "[keyword from issue]" specs/ 2>/dev/null
# Check which feature spec covers this area
ls specs/*/spec.md
```

Read the relevant `spec.md`, `plan.md`, and `contracts/interfaces.md` to understand what the code SHOULD do. This is your oracle — the gap between spec and reality is the bug.

**If no spec exists**: That's fine. Work from the user's description and the code itself. Not everything goes through kiln.

## Step 2b: Check for Credentials / Real Account Data

Before attempting to reproduce, check if the issue involves authenticated flows, real user data, or external services that require credentials.

### Detection — ask the user if ANY of these are true:
- The bug is behind a login wall or requires authentication
- The issue involves a specific user account, role, or permission level
- The bug only happens with real/production data (not mock data)
- An external API, database, or third-party service is involved
- The issue mentions OAuth, SSO, tokens, API keys, or sessions
- The bug is in an admin panel, dashboard, or gated feature

### If credentials are needed:

Ask the user directly — do NOT guess or skip this:

```
This issue appears to involve [authenticated flows / real account data / external service].

To debug this, I'll need credentials. Please provide them in `.kiln/qa/.env.test`:

```env
# Debug Credentials — DO NOT COMMIT (gitignored)
#
# Fill in whatever applies to this issue:
#
# Account credentials
QA_TEST_USER_EMAIL=
QA_TEST_USER_PASSWORD=
#
# If the bug is role-specific:
QA_ADMIN_EMAIL=
QA_ADMIN_PASSWORD=
#
# If external services are involved:
QA_API_KEY=
QA_DATABASE_URL=
#
# If the bug needs a specific account/data:
QA_TARGET_USER_ID=
QA_TARGET_RESOURCE_ID=
```

Specifically, I need:
- [ ] [credential 1 — what and why]
- [ ] [credential 2 — what and why]

I'll wait for you to fill in `.kiln/qa/.env.test` before proceeding with reproduction.
If you'd prefer to provide them another way, let me know.
```

### While waiting for credentials:
- Continue with Steps 2 (spec context) — you can read specs without credentials
- Follow `plugin-kiln/scripts/debug/diagnose.md` on what you CAN inspect (code analysis, stack traces, config)
- Do NOT attempt to reproduce auth-dependent flows without credentials — you'll get false negatives
- Do NOT hardcode, guess, or fabricate credentials

### Once credentials are provided:
1. Verify `.kiln/qa/.env.test` exists and has the needed values
2. Verify `.gitignore` includes `.kiln/qa/.env.test`
3. Load credentials in reproduction scripts via `dotenv` or `process.env`
4. NEVER log, screenshot, or record credentials in video output
5. Proceed to Step 3 (Reproduce)

### For future debugging sessions:
If `.kiln/qa/.env.test` already exists from a previous session, check if the credentials are still valid and sufficient for the current issue. If the new issue requires additional credentials (different role, different service), ask the user to add them.

## Step 3: Reproduce the Issue

Before diagnosing, confirm the bug is real and reproducible:

### For test failures:
```bash
npm test -- --grep "[relevant test]" 2>&1
```

### For runtime errors:
```bash
# Run the app and trigger the bug
npm run dev &
# Then reproduce the steps from the issue
```

### For visual/UI bugs:
```bash
# Check if QA infrastructure exists
ls .kiln/qa/playwright.config.ts 2>/dev/null
# If not, set it up
# Then run a targeted Playwright test to reproduce
```

### For build failures:
```bash
npm run build 2>&1
```

If the bug does NOT reproduce, tell the user: "I can't reproduce this. Here's what I tried: [steps]. Can you provide more details?"

## Step 4: Run the Debug Loop

Read `plugin-kiln/scripts/debug/diagnose.md` and follow its procedure with:
- The issue description
- The spec context (what SHOULD work)
- The reproduction result (how it actually fails)

Then read `plugin-kiln/scripts/debug/fix.md` and follow its procedure with the diagnosis.

The debug loop runs: diagnose → fix → verify → (repeat if needed, max 9 attempts). Both helpers are plain markdown procedural guides — read them at the start of each loop iteration.

See the `debugger` agent definition for full loop details.

### Step 4 (alternative): Spawn the `debugger` agent via the wheel resolver (FR-A5)

The inline loop above is the default. If you prefer to hand the loop off to a dedicated specialized sub-agent (e.g. to keep the main chat clean, or because the bug needs deeper context than fits here), you can spawn the `debugger` agent via wheel's resolver. This is the FR-A5 path from the `wheel-as-runtime` PRD — any kiln skill can now spawn a specialized agent without wrapping itself in a wheel workflow.

```bash
# Resolve the debugger spec via wheel's plugin-agnostic resolver primitive.
# Plugin-prefixed names (kiln:debugger) are the canonical form — the harness
# discovers them via filesystem scan at session start. The resolver passes
# them through; no central registry is consulted (post-2026-04-25 cleanup
# reversed FR-A1's central registry; agents own their consumer-plugin location).
SPEC=$(plugin-wheel/scripts/agents/resolve.sh kiln:debugger)
SUBAGENT_TYPE=$(printf '%s' "$SPEC" | jq -r '.subagent_type')
MODEL_DEFAULT=$(printf '%s' "$SPEC" | jq -r '.model_default // "sonnet"')
```

Then call the `Agent` tool with `subagent_type: "$SUBAGENT_TYPE"` (which will be `"kiln:debugger"`), passing the issue description, the spec context, and the reproduction result as the prompt.

Fallback: if the resolver exits 1 (`WORKFLOW_PLUGIN_DIR` unset in a bg context for path-form input, etc.), fall back to the inline debug loop above — do NOT silently drop the request. Plugin-prefixed-name passthrough never errors — `SPEC` always echoes back the input as `subagent_type`, and the Agent tool handles it directly via the harness's filesystem-discovered registration.

This path is opt-in. The inline loop remains the default for the skill. A skill-test under `plugin-kiln/tests/kiln-fix-resolver-spawn/` exercises the resolver-spawn path (see T045 in `specs/wheel-as-runtime/tasks.md`).

## Step 5: Verify and Commit

Once the fix passes verification:

1. **Run the full test suite** to check for regressions:
```bash
npm test 2>&1
```

2. **For visual bugs**: Run the relevant QA test to confirm:
```bash
cd .kiln/qa && npx playwright test --config=playwright.config.ts --grep "[test]" 2>&1
```

3. **Commit the fix**:
```bash
git add [changed files]
git commit -m "fix: [concise description]

Root cause: [one-line explanation]
Resolves: [issue number if provided]
Verified by: [test/command that confirms]"
```

4. **Report to the user**:
```
## Bug Fixed

**Issue**: [description]
**Root cause**: [what was wrong]
**Fix**: [what was changed, with file:line references]
**Verified by**: [test output or visual confirmation]
**Commit**: [hash]

### Debug summary
- Technique used: [technique name]
- Attempts: [N]
- Files changed: [list]
```

5. **Append the What's Next? block** (FR-007, FR-008). This block MUST appear on every successful terminal path — it is the last thing the user sees. Select bullets per the policy in Step 8 below.

   For the success path (commit landed), the selection is:
   - UI-adjacent fix (files_changed matches `.tsx|.jsx|.vue|.svelte|.css` OR a path under `components/|pages/|views/|layouts/|app/`): lead with `/kiln:kiln-qa-final`, then `/kiln:kiln-next`.
   - Non-UI fix: lead with `/kiln:kiln-next`.
   - If this run created a PR: include `review and ship the PR` as a bullet.
   - Always include a closing bullet such as `nothing urgent — you're done` when the above leave fewer than 2 bullets.

   Example (UI-adjacent success, no PR this run):

   ```
   ## What's Next?

   - `/kiln:kiln-qa-final` — re-run the full Playwright suite to catch regressions from the UI fix
   - `/kiln:kiln-next` — pick up where you left off
   - `/kiln:kiln-report-issue <follow-up>` — capture anything you noticed during the fix
   ```

   Example (non-UI success with a PR created this run):

   ```
   ## What's Next?

   - `/kiln:kiln-next` — pick up where you left off
   - review and ship the PR — it's on the feature branch, ready for review
   - `nothing urgent — you're done`
   ```

## Step 6: Handle Escalation

If the debug loop exhausts all strategies (9 attempts), present the user with everything collected:

```
## Debug Report — Could Not Fix Automatically

**Issue**: [description]
**Spec**: [which spec covers this, or "none"]

### What I Found
[Root cause hypothesis with evidence]

### What I Tried
1. [approach 1] — failed because [reason]
2. [approach 2] — failed because [reason]
3. [approach 3] — failed because [reason]

### Diagnostics
- [artifact paths]

### My Recommendation
[What the user should try manually, or whether this needs a spec update]
```

Append the `## What's Next?` block to the escalation report (FR-007, FR-008). For the escalation path, the selection is:

- Lead with `/kiln:kiln-report-issue <follow-up>` — capture the unresolved issue as a backlog entry so distill can pick it up later.
- Then `/kiln:kiln-next` — re-orient on what else is in flight.
- Optionally `nothing urgent — you're done` as a closing bullet.

Example:

```
## What's Next?

- `/kiln:kiln-report-issue <one-line follow-up>` — log what remained unresolved so it can be re-attacked later
- `/kiln:kiln-next` — re-orient on the next-priority work
- `nothing urgent — you're done`
```

## Step 7: Record the Fix (NON-NEGOTIABLE)

Steps 2b–5 MUST complete in main chat before this step begins (FR-020 — the debug loop stays in main chat; no `SendMessage` to a teammate, no wheel-activate call, and no MCP vault write MUST occur before the commit or escalation step is reached). Step 7 is the ONLY place in this skill that talks to the Obsidian vault.

This step composes a durable record of the fix, writes it locally, files the Obsidian fix note via a direct inline MCP call, and — if the reflect gate fires — files a single manifest-improvement proposal via a second inline MCP call. It runs whether the debug loop succeeded (commit landed) OR escalated (9 attempts exhausted). Do NOT skip it.

**Shape:** everything runs inline in the main chat — no team-spawn tool calls (the prior implementation's team primitives have been removed per FR-001/FR-005). The fix-note and reflect-proposal writes are two independent direct `mcp__claude_ai_obsidian-*__create_file` calls.

### 7.1 Determine status and commit_hash

Compare `git rev-parse HEAD` at skill start vs now. If HEAD advanced, the debug loop landed a commit: `STATUS=fixed` and `COMMIT_HASH=$(git rev-parse HEAD)`. If HEAD is unchanged and the debug loop exhausted 9 attempts: `STATUS=escalated` and `COMMIT_HASH=""` (null in the envelope).

### 7.2 Resolve SHELF_SCRIPTS_DIR and FIX_RECORDING_DIR (plugin portability, FR-025)

Export `SHELF_SCRIPTS_DIR` before invoking any shelf reflect-gate helper (`validate-reflect-output.sh`, `check-manifest-target-exists.sh`, `derive-proposal-slug.sh`). Hardcoding a repo-relative shelf path is a portability bug per `CLAUDE.md`.

```bash
SHELF_SCRIPTS_DIR="${WORKFLOW_PLUGIN_DIR:-}"
if [ -n "${SHELF_SCRIPTS_DIR}" ] && [ -d "${SHELF_SCRIPTS_DIR}/../plugin-shelf/scripts" ]; then
  SHELF_SCRIPTS_DIR="${SHELF_SCRIPTS_DIR}/../plugin-shelf/scripts"
elif [ -d "$(pwd)/plugin-shelf/scripts" ]; then
  SHELF_SCRIPTS_DIR="$(pwd)/plugin-shelf/scripts"
else
  SHELF_SCRIPTS_DIR="$(find "${HOME}/.claude/plugins/cache" -maxdepth 6 -type d -name 'scripts' -path '*/plugin-shelf/*' 2>/dev/null | head -1)"
fi
export SHELF_SCRIPTS_DIR
```

Also resolve `FIX_RECORDING_DIR` pointing at this plugin's `scripts/fix-recording/` directory (the kiln-internal helpers: `compose-envelope.sh`, `write-local-record.sh`).

```bash
FIX_RECORDING_DIR="${WORKFLOW_PLUGIN_DIR:-}"
if [ -n "${FIX_RECORDING_DIR}" ] && [ -d "${FIX_RECORDING_DIR}/scripts/fix-recording" ]; then
  FIX_RECORDING_DIR="${FIX_RECORDING_DIR}/scripts/fix-recording"
elif [ -d "$(pwd)/plugin-kiln/scripts/fix-recording" ]; then
  FIX_RECORDING_DIR="$(pwd)/plugin-kiln/scripts/fix-recording"
else
  FIX_RECORDING_DIR="$(find "${HOME}/.claude/plugins/cache" -maxdepth 6 -type d -name 'fix-recording' -path '*/plugin-kiln/scripts/*' 2>/dev/null | head -1)"
fi
export FIX_RECORDING_DIR
```

### 7.3 Compose the envelope (main chat, inline bash)

Write the changed-files list to a temp file, then invoke `compose-envelope.sh` with every required flag. The helper resolves `project_name` internally via `resolve-project-name.sh` (FR-013) and strips `.kiln/qa/.env.test` lines from every string field (FR-026).

```bash
mkdir -p .kiln/fixes
envelope_path=".kiln/fixes/.envelope-$(date +%s).json"

files_list=$(mktemp)
if [ "$STATUS" = "fixed" ] && [ -n "$COMMIT_HASH" ]; then
  git diff --name-only "${COMMIT_HASH}^".."${COMMIT_HASH}" > "$files_list"
else
  # Escalated: list files inspected during the debug loop, not modified.
  # Derive from the debug loop's diagnose artifacts if available; otherwise an empty list is acceptable.
  : > "$files_list"
fi

bash "$FIX_RECORDING_DIR/compose-envelope.sh" \
  --issue             "<one-line issue summary>" \
  --root-cause        "<one-sentence root cause>" \
  --fix-summary       "<1–3 sentence description of the change (fixed) or techniques tried (escalated)>" \
  --files-changed-file "$files_list" \
  --commit-hash       "$COMMIT_HASH" \
  --feature-spec-path "<specs/<feature>/spec.md or empty>" \
  --resolves-issue    "<gh issue ref or empty>" \
  --status            "$STATUS" \
  > "$envelope_path"
```

### 7.4 Write the local record (inline — FR-002, FR-020)

```bash
local_record_path=$(bash "$FIX_RECORDING_DIR/write-local-record.sh" "$envelope_path")
```

Capture `local_record_path` — the final user report in 7.8 references it.

### 7.5 Derive fix-note variables from the envelope

The downstream inline MCP call writes the Obsidian fix note. Derive the four variables it needs — `today`, `slug`, `project_name`, `abs_envelope` — from the envelope and the local record path composed above.

```bash
today=$(date -u +%Y-%m-%d)
slug=$(basename "$local_record_path" .md | sed "s/^${today}-//; s/-[0-9]*$//")
project_name=$(jq -r '.project_name // ""' "$envelope_path")
abs_envelope=$(cd "$(dirname "$envelope_path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$envelope_path")")

issue=$(jq -r '.issue // ""' "$envelope_path")
root_cause=$(jq -r '.root_cause // ""' "$envelope_path")
fix_summary=$(jq -r '.fix_summary // ""' "$envelope_path")
status_val=$(jq -r '.status // ""' "$envelope_path")
commit_hash=$(jq -r '.commit_hash // ""' "$envelope_path")
resolves_issue=$(jq -r '.resolves_issue // ""' "$envelope_path")
feature_spec_path=$(jq -r '.feature_spec_path // ""' "$envelope_path")
files_changed=$(jq -r '.files_changed // [] | .[]' "$envelope_path")
```

### 7.6 Write the Obsidian fix note (inline MCP call)

If `project_name` is empty, skip this sub-step silently and record `obsidian_note_result="skipped (project_name null)"` — `resolve-project-name.sh` already returned null, which means the project is not registered in the vault (FR-013 case 3).

Otherwise, issue ONE direct `mcp__claude_ai_obsidian-projects__create_file` call from main chat (NOT via a spawned teammate) with:

- **path**: `@projects/<project_name>/fixes/<today>-<slug>.md`. On collision (target already exists), retry with `<today>-<slug>-2.md`, `<today>-<slug>-3.md`, … up to 9 attempts (FR-015). Use the `mcp__claude_ai_obsidian-projects__list_files` primitive on the parent folder to pre-check when available; otherwise rely on `create_file`'s "already exists" error signal.
- **content**: the body shape below, derived from the envelope variables set in 7.5.

```markdown
---
type: fix
date: <today>
status: <status_val>
commit: <commit_hash or null>
resolves_issue: <resolves_issue or null>
files_changed:
  - <path>
  - ...
tags:
  - fix/<class>                # pick exactly one: fix/runtime-error, fix/regression,
                               # fix/test-failure, fix/build-failure, fix/ui,
                               # fix/performance, fix/documentation
  - topic/<topic>              # at least one, free-form (topic/auth, topic/routing, …)
  - <stack-axis-tag>           # exactly one of language/*, framework/*, lib/*, infra/*, testing/*
---

## Issue
<issue>

(if resolves_issue non-null) Resolves [[#<resolves_issue>]] or <URL>.
(if feature_spec_path non-null) Related spec: [[<feature_spec_path>]].
(if commit_hash non-null) Commit: <commit_hash>    # plain text — not a wikilink (commits live outside the vault, FR-007).

## Root cause
<root_cause>

## Fix
<fix_summary>

## Files changed
- <path>
- ...
(or `_none_` when files_changed is empty)

## Escalation notes
_none_     (when status_val == fixed)
<multi-line notes>     (when status_val == escalated — derive from fix_summary + any techniques tried)
```

Record the outcome:

- Success → `obsidian_note_result="@projects/<project_name>/fixes/<today>-<slug>.md"` (with suffix applied on collision).
- MCP unavailable (FR-006 / FR-016) → `obsidian_note_result="skipped (MCP unavailable)"`. Do NOT retry more than once. Local record is the sole artifact.
- `project_name` empty → `obsidian_note_result="skipped (project_name null)"`. No MCP call attempted.

### 7.7 Reflect gate (deterministic) and optional manifest proposal

Evaluate the reflect gate against the envelope. Gate fires if ANY of the three conditions in `specs/kiln-capture-fix-polish/contracts/interfaces.md` Contract 2 holds:

1. Any `envelope.files_changed` entry matches regex `^plugin-[^/]+/(templates/|skills/[^/]+/SKILL\.md$)` — a template file or a skill definition was touched.
2. `envelope.issue` OR `envelope.root_cause` contains (case-insensitive) substring `@manifest/` OR `manifest/types/`.
3. `envelope.fix_summary` contains a template path — regex `plugin-[^/]+/templates/` OR whole-word `templates/` preceded by `^` or a non-alphanumeric.

```bash
reflect_fires() {
  local env="$1"
  if jq -e '.files_changed[]? | select(test("^plugin-[^/]+/(templates/|skills/[^/]+/SKILL\\.md$)"))' "$env" >/dev/null 2>&1; then
    return 0
  fi
  if jq -e '(.issue, .root_cause) | test("@manifest/|manifest/types/"; "i")' "$env" >/dev/null 2>&1; then
    return 0
  fi
  if jq -e '.fix_summary | test("plugin-[^/]+/templates/|(^|[^a-zA-Z])templates/")' "$env" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if reflect_fires "$envelope_path"; then
  reflect_verdict="write"
else
  reflect_verdict="skip"
fi
```

If `reflect_verdict="skip"`: set `proposal_result="none (no gap identified)"` and proceed to 7.8. Do NOT emit any user-visible log.

If `reflect_verdict="write"`: identify the concrete `@manifest/types/*.md` or `@manifest/templates/*.md` target that this fix improves, read its verbatim `current` text via `mcp__claude_ai_obsidian-manifest__read_file` (read-only, exactly once on the target), compose `proposed` and a one-sentence `why` grounded in the envelope (cite `issue`, `commit_hash`, a `files_changed` entry, a phrase from `root_cause`, or `feature_spec_path`), then run the exact-patch gate and write the proposal:

```bash
reflect_output=".kiln/fixes/.reflect-output-$(date +%s).json"
# Compose the reflect output JSON with {skip:false, target, section, current, proposed, why}
# then validate:
bash "$SHELF_SCRIPTS_DIR/validate-reflect-output.sh" "$reflect_output"
# If verdict is "write", verify the target file+current still exists verbatim:
current_tmp=$(mktemp)
jq -r '.current' "$reflect_output" > "$current_tmp"
target=$(jq -r '.target' "$reflect_output")
bash "$SHELF_SCRIPTS_DIR/check-manifest-target-exists.sh" "$target" "$current_tmp"  # exit 0 = ok; exit 1 = force-skip
why=$(jq -r '.why' "$reflect_output")
proposal_slug=$(printf '%s\n' "$why" | bash "$SHELF_SCRIPTS_DIR/derive-proposal-slug.sh")
proposal_path="@inbox/open/${today}-manifest-improvement-${proposal_slug}.md"
```

If `check-manifest-target-exists.sh` exits 1 (force-skip), set `proposal_result="none (no gap identified)"` and proceed to 7.8 — no MCP write.

Otherwise, issue ONE direct `mcp__claude_ai_obsidian-manifest__create_file` call with `path=<proposal_path>` and content matching the four-section proposal shape:

```markdown
---
type: proposal
target: <@manifest/types/<file>.md or @manifest/templates/<file>.md>
date: <today>
---

## Target
<target path>

## Current
<verbatim current text>

## Proposed
<verbatim proposed text>

## Why
<one-sentence citation grounded in envelope>
```

Record the outcome:

- Success → `proposal_result="<proposal_path>"`.
- MCP unavailable (FR-006) → `proposal_result="skipped (MCP unavailable)"`. Do NOT retry beyond once.

Cleanup:

```bash
rm -f "$envelope_path"
rm -f .kiln/fixes/.reflect-output-*.json
```

The local record at `$local_record_path` is NOT deleted — it persists alongside the Obsidian note.

### 7.8 User-facing report (extends Step 5 or Step 6)

Append these lines to whichever terminal report template was emitted (Step 5 "Bug Fixed" or Step 6 "Debug Report"):

```
Local record: <local_record_path>
Obsidian note: <obsidian_note_result>
Manifest proposal: <proposal_result>
```

Then render the `## What's Next?` block per the policy in Step 8 (FR-007). On the Obsidian-skipped terminal path (either `skipped (MCP unavailable)` or `skipped (project_name null)` for the fix note, or `skipped (MCP unavailable)` for the proposal), add ONE bullet noting the skip so the user knows what to do about it:

- If MCP was unavailable this run, include `\`/kiln:kiln-fix\` — retry after MCP reconnects` as an extra bullet (still within the 4-bullet cap).
- If `project_name` was null (the project isn't registered in the vault), include `register this project in the Obsidian vault and re-run` as a prose bullet.
- If everything wrote cleanly, no extra bullet is added for Step 7 — just the normal Step 5 or Step 6 `## What's Next?` block.

### Constraints enforced by this step (cross-reference)

- FR-001: Step 7 runs inline in main chat; no team-spawn primitives are invoked anywhere in this skill.
- FR-005: All recording logic — envelope compose, local record, Obsidian fix-note write, reflect gate, optional manifest proposal — happens inline. No team-briefs, no teammate spawn.
- FR-006: On MCP unavailability, the local record is preserved and the report line reads `skipped (MCP unavailable)`. No crash, no retry loop.
- FR-019: Step 7 MUST NOT invoke `shelf:shelf-sync` or any wheel workflow. The two direct MCP `create_file` calls in 7.6 and 7.7 are the only vault-write mechanisms.
- FR-020: Steps 2b–5 complete in main chat first; no vault write or teammate message is issued before 7.6.
- FR-023: No wheel workflow is added or modified by this step.
- FR-025: All script paths come from `$SHELF_SCRIPTS_DIR` / `$FIX_RECORDING_DIR`; no repo-relative plugin path literal appears anywhere in the live substitution values.

## Step 8: What's Next? (selection policy — FR-007, FR-008)

Every terminal path of this skill — success (Step 5), escalation (Step 6), Obsidian-skipped (Step 7.8) — MUST end its final report with a `## What's Next?` block shaped per `specs/kiln-capture-fix-polish/contracts/interfaces.md` Contract 4:

- Minimum 2 bullets, maximum 4.
- Each bullet's primary command (or action phrase) MUST come from this allowed set:
  - `/kiln:kiln-next`
  - `/kiln:kiln-qa-final`
  - `/kiln:kiln-report-issue <follow-up>`
  - `/kiln:kiln-fix` (for the MCP-unavailable retry case only)
  - `/kiln:kiln-distill` (only when the backlog has 3+ open items)
  - `review and ship the PR` (only when this run created a PR)
  - `nothing urgent — you're done`

### Selection policy (dynamic)

Evaluate these branches in order; the first matching branch sets the lead bullet.

| Terminal path               | Lead bullet                              | Trailing bullets (pick 1–3 from allowed set)                                                   |
|-----------------------------|------------------------------------------|-----------------------------------------------------------------------------------------------|
| Escalation (Step 6)         | `/kiln:kiln-report-issue <follow-up>`    | `/kiln:kiln-next`, optionally `nothing urgent — you're done`                                   |
| UI-adjacent success         | `/kiln:kiln-qa-final`                    | `/kiln:kiln-next`, `/kiln:kiln-report-issue <follow-up>` if you noticed anything tangential    |
| Default success             | `/kiln:kiln-next`                        | `review and ship the PR` if a PR was created this run; `/kiln:kiln-report-issue <follow-up>`; `nothing urgent — you're done` |
| Obsidian-skipped (MCP down) | same as above, prepend skip-note bullet  | `\`/kiln:kiln-fix\` — retry after MCP reconnects`                                             |
| Obsidian-skipped (no project)| same as above, prepend skip-note bullet | register the project in the vault and re-run                                                   |

**UI-adjacent detection** — treat the fix as UI-adjacent if any entry in `envelope.files_changed` matches:

- Extensions: `.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`.
- Paths: any segment of `components/`, `pages/`, `views/`, `layouts/`, `app/`.

If `envelope.files_changed` is empty (common on the escalation path), skip the UI detection and use the escalation-path branch.

**PR detection** — if this run created a PR (e.g., via `gh pr create`), include the `review and ship the PR` bullet. If no PR was created, omit it.

### Rendering rules

- Each bullet is a single line.
- Commands go in backticks; prose bullets (`nothing urgent — you're done`, `review and ship the PR`) are plain text.
- Add a short trailing clause (after an em dash) explaining why the command is relevant *this* run — no generic filler.
- Do not exceed 4 bullets total. If you have more candidates than slots, keep the lead bullet and drop the least-relevant trailing ones.

## UI Issues — QA Engineer is MANDATORY (NON-NEGOTIABLE)

If the issue involves the UI in ANY way — layout, styling, visual regression, component behavior, responsiveness, "looks wrong", button doesn't work, page doesn't render — the QA engineer MUST run as part of verification. This is not optional.

### Detection

An issue is a UI issue if ANY of these are true:
- The user mentions anything visual (layout, CSS, styling, responsive, looks wrong, misaligned, overlapping)
- The issue references a UI component, page, or route
- The error occurs in a `.tsx`, `.jsx`, `.vue`, `.svelte`, or template file
- The issue mentions user interaction (click, hover, scroll, navigate, form submit)
- Screenshots or videos are attached showing the problem
- The affected file is in a `components/`, `pages/`, `views/`, `layouts/`, or `app/` directory

### Required Flow for UI Issues

1. **Setup** (if not already done): Run `/kiln:kiln-qa-setup` to install Playwright and scaffold test infra
2. **Reproduce**: Write a Playwright test that reproduces the bug (captures the failure on video)
3. **Diagnose + Fix**: Run the normal debug loop (`scripts/debug/diagnose.md` → `scripts/debug/fix.md`)
4. **Verify via QA (MANDATORY)**: After the fix, run `/kiln:kiln-qa-final` to:
   - Re-run the specific failing test (must now pass)
   - Run ALL existing E2E flows to check for regressions
   - Record video of every flow (pass and fail)
   - Produce the QA report at `.kiln/qa/latest/QA-REPORT.md`
5. **The fix is NOT verified until QA passes.** A unit test passing is insufficient for UI bugs — you must see it working in a real browser.

Do NOT skip QA for UI issues. Do NOT treat a passing unit test as sufficient verification. The QA engineer runs E2E across the full application to catch regressions your fix may have introduced in other flows.

## Rules

- Do NOT require a new PRD or spec — the whole point is to fix bugs without ceremony
- DO read existing specs for context — they tell you what the code should do
- **UI issues ALWAYS require QA verification** — no exceptions, no shortcuts
- The kiln hooks may block src/ edits — existing specs should satisfy the gates. If not, check that spec artifacts exist for the feature.
- Log everything in `debug-log.md` — it helps the retrospective and future debugging
- If the bug reveals a gap in the original spec (the feature was never supposed to handle this case), tell the user. They may want to update the spec before fixing.
- If the fix is trivial (typo, obvious one-line fix), just fix it directly without the full diagnose→fix loop. Use judgment. But if it's a UI fix, still run QA.
- Always run the full test suite after fixing to catch regressions
