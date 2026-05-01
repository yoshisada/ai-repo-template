# Isolated Workflow Testing

How to run a wheel workflow end-to-end from inside an active Claude Code session without colliding with the parent's `.wheel/` state. Use this whenever you need to validate a workflow live — Phase 4 team workflows in particular cannot be tested in-session, because the parent's hooks see every state file in the parent's cwd.

## The collision

A `claude --print` subprocess launched from a Bash tool inside an active Claude Code session inherits the parent's session identity even with `--session-id <new-uuid>` set. The parent's `CLAUDECODE`, `AI_AGENT`, `CLAUDE_CODE_ENTRYPOINT`, and `CLAUDE_CODE_EXECPATH` env vars propagate, the subprocess detects "I'm inside another Claude Code session," and overrides `--session-id` to attach to the parent's session_id. The wheel hook then reports the parent's session_id in its hook payload, the subprocess's state file is owned by the parent, and the parent's `guard.sh` resolves the subprocess's state file as its own. Workflow state from the test pollutes the parent.

## The recipe

Three things together. Missing any one of them re-introduces the collision:

1. **Wipe the inheritance env vars** — `env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH` before invoking `claude`.
2. **Force a unique session_id** — `--session-id $(uuidgen | tr '[:upper:]' '[:lower:]')`.
3. **Separate cwd** — `cd /tmp/wheel-test-<uuid>` before `claude` runs. The wheel hook resolves its log path and state dir relative to cwd, so a fresh dir gives the test its own `.wheel/`.

```bash
TESTDIR=/tmp/wheel-test-$(uuidgen | head -c 8)
mkdir -p "$TESTDIR/.wheel" "$TESTDIR/workflows/tests"
cp workflows/tests/<workflow>.json "$TESTDIR/workflows/tests/"

NEW_SID=$(uuidgen | tr '[:upper:]' '[:lower:]')
env -u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH \
  bash -c "cd $TESTDIR && claude --print --dangerously-skip-permissions \
    --model sonnet --session-id $NEW_SID --max-budget-usd 3.00 \
    --output-format text < /tmp/test-prompt.md > /tmp/test-output.txt 2>&1"
```

## Verifying isolation

Look at three things during/after the run:

1. **Subprocess wheel.log** — should be at `$TESTDIR/.wheel/logs/wheel.log` (or `/private/tmp/.wheel/logs/wheel.log` if cwd resolves to `/tmp` symlink-wise). Entries should show the new session_id, e.g. `bd09b7b2|...|tool=Bash`.
2. **Parent wheel.log** — should have NO entries with the test's session_id, and NO state files matching `state_<new-sid>_*.json` in the parent's `.wheel/`.
3. **Subprocess state file** — `$TESTDIR/.wheel/state_<new-sid>_*.json` exists and `owner_session_id` matches the new UUID.

If the parent's `.wheel/` ever gains a state file during the test, isolation broke — re-check the env wipe.

## Test prompt template

The subprocess is a fresh Sonnet/Opus that sees only the prompt. It MUST be told concrete absolute paths and exact tool parameters — do NOT use placeholders like `<name>` or `<workflow>`, because the model will paste them literally.

```text
You are running workflow `<workflow>` in cwd $TESTDIR. The .wheel/ is empty.

1. Activate:
   bash /Users/<user>/.claude/plugins/cache/yoshisada-speckit/wheel/<version>/bin/activate.sh $TESTDIR/workflows/tests/<workflow>.json

2. Respond to hook prompts as instructed (TeamCreate, TeamDelete, Write outputs, Agent spawns).
   For Agent spawns, use literal worker names (worker-1, worker-2, worker-3) — never <name>.

3. When .wheel/state_*.json is gone, print:
   PHASE_RESULT: PASS|FAIL
   ARCHIVE: <path in .wheel/history/success|failure|stopped/>

Time budget: 5 min. If stuck for 90s, dump state and report blocker.
```

## Watching from the parent

Use `Monitor` (or a backgrounded `Bash` with an `until` loop) to watch the test directory's state and archives. Don't poll-sleep from the parent — that burns context and the harness blocks raw `sleep` chains.

```bash
# Monitor pattern that emits one event per state transition
prev=""
for i in $(seq 1 90); do
  if ls $TESTDIR/.wheel/state_*.json >/dev/null 2>&1; then
    cur=$(jq -r '"cursor=" + (.cursor|tostring) + " step=" + .steps[.cursor].id + "/" + .steps[.cursor].type + " status=" + .steps[.cursor].status' \
      $TESTDIR/.wheel/state_*.json | head -1)
  elif ls $TESTDIR/.wheel/history/success/*.json >/dev/null 2>&1; then
    cur="ARCHIVED-SUCCESS: $(ls -t $TESTDIR/.wheel/history/success/ | head -1)"
  elif ls $TESTDIR/.wheel/history/failure/*.json >/dev/null 2>&1; then
    cur="ARCHIVED-FAILURE: $(ls -t $TESTDIR/.wheel/history/failure/ | head -1)"
  else
    cur="no-state-no-archive"
  fi
  if [ "$cur" != "$prev" ]; then echo "[$(date +%H:%M:%S)] $cur"; prev="$cur"; fi
  case "$cur" in ARCHIVED-*) exit 0 ;; esac
  sleep 3
done
```

## Cleanup

```bash
rm -rf "$TESTDIR" /private/tmp/.wheel
rm -rf ~/.claude/teams/<any-team-name-the-test-created>
rm -f /tmp/test-prompt.md /tmp/test-output.txt
```

If the test created any teams via `TeamCreate`, the team config under `~/.claude/teams/<name>/` lingers across sessions and will cause "Already leading team" errors on re-runs. Always clean it up.

## Why not the wheel-test-runner harness

`plugin-wheel/scripts/harness/wheel-test-runner.sh` is the right tool when the test is **a fixture under `plugin-<name>/tests/<test>/` with a `test.yaml` and `assertions.sh`**. It already runs in a `/tmp/kiln-test-<uuid>/` scratch dir with proper isolation.

This isolated-workflow testing pattern is for ad-hoc workflow runs that DON'T have a fixture yet — debugging a workflow definition, reproducing a Phase 4 issue, exploratory testing of a new step type. Once the workflow is stable enough to deserve a fixture, fold it into the harness.

## When to use this pattern

- Validating any wheel workflow live, end-to-end, that touches multi-state-file scenarios (composition, teams) — the harness's snapshot assertions can't cover dynamic team behavior.
- Reproducing bugs that only manifest in a real Claude Code session (TeamCreate, Agent spawns, real hook routing).
- Iterating on a workflow JSON without filing a fixture for every change.

## When NOT to use this pattern

- For a stable workflow with deterministic output — write a `tests/<test>/` fixture and let the harness run it. CI requires harness-style fixtures.
- For commit-blocking validation — this pattern is interactive and budget-bounded; not suitable for hooks or pre-commit gates.
