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

## Step 7: Record the Fix (NON-NEGOTIABLE)

Steps 2b–5 MUST complete in main chat before this step begins (FR-020 — the debug loop stays in main chat; no `TeamCreate`, `TaskCreate`, `SendMessage` to a teammate, or wheel-activate call MUST occur before the commit or escalation step is reached). Step 7 is the first and only place in this skill that spawns teams.

This step composes a durable record of the fix, writes it locally, and spawns two parallel short-lived teams that file the Obsidian note and (optionally) a manifest-improvement proposal. It runs whether the debug loop succeeded (commit landed) OR escalated (9 attempts exhausted). Do NOT skip it.

### 7.1 Determine status and commit_hash

Compare `git rev-parse HEAD` at skill start vs now. If HEAD advanced, the debug loop landed a commit: `STATUS=fixed` and `COMMIT_HASH=$(git rev-parse HEAD)`. If HEAD is unchanged and the debug loop exhausted 9 attempts: `STATUS=escalated` and `COMMIT_HASH=""` (null in the envelope).

### 7.2 Resolve SHELF_SCRIPTS_DIR (plugin portability, FR-025)

Export `SHELF_SCRIPTS_DIR` before any helper or team invocation, via the three-step fallback below. This variable is the ONLY way team briefs reference shelf scripts — hardcoding a repo-relative shelf script path is a portability bug per `CLAUDE.md`.

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

Also resolve `FIX_RECORDING_DIR` pointing at this plugin's `scripts/fix-recording/` directory (the kiln-internal helpers). Same fallback logic, but looking for `plugin-kiln/scripts/fix-recording`.

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

### 7.4 Write the local record (inline, before team spawn — FR-002, FR-020)

```bash
local_record_path=$(bash "$FIX_RECORDING_DIR/write-local-record.sh" "$envelope_path")
```

Capture `local_record_path` — the final user report in 7.10 references it.

### 7.5 Render both team briefs

Both briefs are static files shipped with this skill under `team-briefs/`. Render them via `render-team-brief.sh` to substitute the six placeholders (`ENVELOPE_PATH`, `SCRIPTS_DIR`, `SLUG`, `DATE`, `PROJECT_NAME`, `TEAM_KIND`).

```bash
today=$(date -u +%Y-%m-%d)
slug=$(basename "$local_record_path" .md | sed "s/^${today}-//; s/-[0-9]*$//")
project_name=$(jq -r '.project_name // ""' "$envelope_path")
abs_envelope=$(cd "$(dirname "$envelope_path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$envelope_path")")

record_brief_src="$FIX_RECORDING_DIR/../../skills/fix/team-briefs/fix-record.md"
reflect_brief_src="$FIX_RECORDING_DIR/../../skills/fix/team-briefs/fix-reflect.md"

record_brief=$(bash "$FIX_RECORDING_DIR/render-team-brief.sh" \
  --envelope-path "$abs_envelope" \
  --scripts-dir   "$SHELF_SCRIPTS_DIR" \
  --slug          "$slug" \
  --date          "$today" \
  --project-name  "$project_name" \
  --team-kind     "fix-record" \
  < "$record_brief_src")

reflect_brief=$(bash "$FIX_RECORDING_DIR/render-team-brief.sh" \
  --envelope-path "$abs_envelope" \
  --scripts-dir   "$SHELF_SCRIPTS_DIR" \
  --slug          "$slug" \
  --date          "$today" \
  --project-name  "$project_name" \
  --team-kind     "fix-reflect" \
  < "$reflect_brief_src")
```

### 7.6 Spawn both teams in parallel (FR-003 — same tool-call batch)

Issue **both** `TeamCreate` + `TaskCreate` pairs in the same assistant message, as a single batch of tool calls (Decision R2). This is what "parallel" means here — both teams are created before either finishes.

- `TeamCreate` name `fix-record-<timestamp>`, teammate `recorder` (model: `haiku`), task brief = rendered `record_brief`.
- `TeamCreate` name `fix-reflect-<timestamp>`, teammate `reflector` (model: `sonnet`), task brief = rendered `reflect_brief`.
- `TaskCreate` for each team, passing the rendered brief as the task description.

### 7.7 Poll to completion

Use `TaskList` to poll both teams until each task reaches `completed`. If a teammate uses `SendMessage` to escape for path ambiguity (FR-010 / FR-011) or MCP unavailability (FR-016), handle the reply inline — one short message per escape. Keep main-chat traffic minimal (SC-004 budget: ≤3k tokens per invocation).

### 7.8 TeamDelete regardless of outcome (FR-017)

After both tasks reach any terminal state — success, silent skip, MCP-unavailable warn, or internal error — issue `TeamDelete` for `fix-record-<timestamp>` and `fix-reflect-<timestamp>`. No orphans MUST remain when the skill returns control to the user.

### 7.9 Cleanup transient scratch

```bash
rm -f "$envelope_path"
rm -f .kiln/fixes/.reflect-output-*.json
```

The local record at `$local_record_path` is NOT deleted — it persists alongside the Obsidian note.

### 7.10 User-facing report (extends Step 5)

Append these lines to the Step 5 report:

```
Local record: <local_record_path>
Obsidian note: <@projects/<project>/fixes/<date>-<slug>.md OR "skipped (MCP unavailable)" OR "skipped (project_name null)">
Manifest proposal: <@inbox/open/... OR "none (no gap identified)">
```

### Constraints enforced by this step (cross-reference)

- FR-019: Step 7 MUST NOT invoke `shelf:shelf-sync` or any wheel workflow. The Obsidian write in Step 7.6 is the only vault-write mechanism.
- FR-020: Steps 2b–5 complete in main chat first; no team-spawn before 7.6.
- FR-023: No wheel workflow is added or modified by this step.
- FR-025: All script paths come from `$SHELF_SCRIPTS_DIR` / `$FIX_RECORDING_DIR`; no repo-relative plugin path literal appears anywhere in the live substitution values.
- FR-017: `TeamDelete` runs for both teams on every terminal outcome — success, silent skip, MCP-unavailable warn, or internal error. No early return skips 7.8.

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
