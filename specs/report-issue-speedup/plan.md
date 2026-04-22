# Plan: Report-Issue Speedup

**Spec**: `specs/report-issue-speedup/spec.md`
**PRD**: `docs/features/2026-04-22-report-issue-speedup/PRD.md`
**Status**: Draft
**Date**: 2026-04-22

## Goal

Restructure `/kiln:kiln-report-issue` so the foreground path does only the essential work (file issue + single Obsidian note) and offloads `shelf-sync` + `shelf-propose-manifest-improvement` to a fire-and-forget background sub-agent gated by a counter.

## Technical approach

This is a workflow refactor + one new sub-workflow + a `.shelf-config` schema addition + a small bash helper library. No changes to the wheel engine itself, no changes to Obsidian MCP, no new runtime dependencies.

### Component inventory

| # | Component | Location | Kind | Change |
|---|-----------|----------|------|--------|
| 1 | `shelf_full_sync_counter` / `shelf_full_sync_threshold` keys | `.shelf-config` schema | config | NEW |
| 2 | Counter helper library | `plugin-shelf/scripts/shelf-counter.sh` | bash lib | NEW |
| 3 | `shelf-write-issue-note` sub-workflow | `plugin-shelf/workflows/shelf-write-issue-note.json` | wheel JSON | NEW |
| 4 | `shelf-sync` workflow | `plugin-shelf/workflows/shelf-sync.json` | wheel JSON | EDIT — remove inline `propose-manifest-improvement` step |
| 5 | `kiln-report-issue` workflow | `plugin-kiln/workflows/kiln-report-issue.json` | wheel JSON | EDIT — replace steps 3 & 4 with `write-issue-note` + `dispatch-background-sync` |
| 6 | Background sub-agent launcher | `plugin-shelf/scripts/dispatch-bg-sync.sh` (helper) + agent-step instruction in the kiln workflow | bash + prompt | NEW |
| 7 | Background sub-agent log helper | `plugin-shelf/scripts/append-bg-log.sh` | bash lib | NEW |
| 8 | Scaffold defaults for new keys | `plugin-shelf/scaffold/.shelf-config.template` (or init path that writes `.shelf-config`) | template | EDIT — add two default keys |
| 9 | CLAUDE.md + SKILL.md updates | `CLAUDE.md`, `plugin-kiln/skills/report-issue/SKILL.md`, `plugin-shelf/skills/shelf-sync/SKILL.md` | docs | EDIT |

### Phased implementation

- **Phase A** — `.shelf-config` schema + counter helpers (items 1, 2, 8).
- **Phase B** — `shelf-write-issue-note` sub-workflow JSON (item 3).
- **Phase C** — Remove inline `propose-manifest-improvement` from `shelf-sync` (item 4).
- **Phase D** — Update `kiln-report-issue` workflow to use new steps (item 5).
- **Phase E** — Background sub-agent launcher (item 6).
- **Phase F** — Log helper (item 7).
- **Phase G** — Documentation (item 9).
- **Phase H** — Smoke test (10 consecutive invocations).

## Resolving the two critical unknowns

### Unknown 1 — Background sub-agent dispatch mechanism

**Choice: Option (a) — agent-type wheel step whose prompt uses the Claude Code `Agent` tool with `run_in_background: true`.**

**Why**:

1. The wheel engine already uses this exact pattern successfully in `plugin-wheel/lib/dispatch.sh:1731` for spawning teammate sub-agents. The pattern works: the outer agent calls `Agent` with `run_in_background: true`, writes its output file, and wheel advances to the next step when the output file appears — the inner sub-agent continues running independently in the background.

2. Option (b) — `command`-type step that runs `claude -p "<prompt>" >/dev/null 2>&1 &` as a disowned subshell — has two problems:
   - **MCP surface**: A detached `claude -p` process starts a fresh Claude Code session that does NOT inherit the MCP servers from the current session. The background sub-agent needs Obsidian MCP to run `shelf-sync` → that path would fail at the `obsidian-apply` step.
   - **Context transfer**: The command step would need to pass the shelf-config path, counter lockfile path, log path, and instructions as CLI args or env vars to `claude -p`, instead of simply describing them in a prompt.

3. The `agent`-type step pattern is already the house style in this codebase for spawning sub-agents inside wheel workflows. Staying with it keeps the change surface small and reuses existing infrastructure (context injection, output file detection, step advance).

**Concrete prototype** for the dispatch step in `kiln-report-issue.json`:

```json
{
  "id": "dispatch-background-sync",
  "type": "agent",
  "instruction": "You are dispatching a fire-and-forget background sub-agent to perform counter-gated reconciliation.\n\n1. Spawn ONE sub-agent via the Agent tool with:\n   - `run_in_background: true`\n   - `mode: bypassPermissions`\n   - `prompt`: (see below)\n\n2. IMMEDIATELY after spawning, write a one-line confirmation to your output file `.wheel/outputs/dispatch-background-sync.txt`:\n   `background sync dispatched | counter=<current-counter-before-increment> | threshold=<threshold>`\n\n   (Read the counter and threshold from `.shelf-config` using `bash ${WORKFLOW_PLUGIN_DIR}/scripts/shelf-counter.sh read` — display-only; do NOT increment here. The background sub-agent owns the increment.)\n\n3. DO NOT wait on the sub-agent. DO NOT call any other tools after spawning it. Write the output file and stop.\n\nSub-agent prompt (pass verbatim to Agent tool):\n\n  You are a background reconciliation sub-agent for kiln-report-issue. Run these steps in order:\n\n  1. bash ${WORKFLOW_PLUGIN_DIR}/scripts/shelf-counter.sh increment-and-decide\n     (This script: acquires flock on .shelf-config.lock, reads counter + threshold, increments counter, decides action, writes counter back, releases lock, echoes JSON {before, after, threshold, action: \"increment\"|\"full-sync\"}.)\n\n  2. Parse the JSON. Call bash ${WORKFLOW_PLUGIN_DIR}/scripts/append-bg-log.sh <before> <after> <threshold> <action> to log.\n\n  3. If action == \"increment\": exit 0.\n\n  4. If action == \"full-sync\":\n     a. Invoke /shelf:shelf-sync via SkillRun or equivalent, wait for completion.\n     b. Invoke /shelf:shelf-propose-manifest-improvement, wait for completion.\n     c. Exit 0.\n\n  If any step fails, write a line to .kiln/logs/report-issue-bg-<YYYY-MM-DD>.md with `action=error | notes=<message>` and exit 0 (never hang, never retry — FR-008).\n\nTerminal: true — this step ends the foreground workflow.",
  "context_from": ["create-issue", "write-issue-note"],
  "output": ".wheel/outputs/dispatch-background-sync.txt",
  "terminal": true
}
```

**Why this returns immediately to the user**: wheel's `dispatch_agent` (`plugin-wheel/lib/dispatch.sh:510`) marks the step `done` as soon as the output file is written. The outer agent writes the output file right after the `Agent` tool call returns (which returns immediately because `run_in_background: true`). The inner sub-agent is a separate background process and is NOT awaited. Wheel archives state, and the user sees the foreground return.

**Fallback plan if (a) doesn't actually fire-and-forget in practice**: during implementation Phase E, if a smoke test shows the foreground blocks on the background sub-agent, switch the dispatch step from `type: agent` to `type: command` running a disowned subshell. The command would be:

```bash
nohup bash "${WORKFLOW_PLUGIN_DIR}/scripts/dispatch-bg-sync.sh" >/dev/null 2>&1 &
disown
echo "background sync dispatched"
```

...where `dispatch-bg-sync.sh` invokes a detached Claude Code with the necessary env vars and prompt. This fallback is documented but NOT the primary path — implementation starts with option (a).

### Unknown 2 — Counter concurrency under flock

**`.shelf-config` format** (verified against existing file):

```
# Shelf configuration — maps this repo to its Obsidian project
base_path = @second-brain/projects
slug = ai-repo-template
dashboard_path = @second-brain/projects/ai-repo-template/ai-repo-template.md
```

Key-value lines, padded equals (` = `), `#` comments. New keys follow the same convention:

```
shelf_full_sync_counter = 0
shelf_full_sync_threshold = 10
```

**Lock file**: sibling file `.shelf-config.lock` (NOT `.shelf-config` itself, because the config file is read by multiple skills and locking it would block reads; and the lockfile needs to be creatable even if `.shelf-config` is read-only in exotic setups).

**`.gitignore`**: `.shelf-config.lock` MUST be added to `.gitignore` (if a repo-root `.gitignore` exists) — it is transient. Implementation task in Phase A.

**Increment-and-decide primitive** — `plugin-shelf/scripts/shelf-counter.sh` exposes three subcommands:

```bash
# Usage: shelf-counter.sh read
#   Prints current counter + threshold as JSON, no lock taken. Display-only.
# Output: {"counter": N, "threshold": N}

# Usage: shelf-counter.sh increment-and-decide
#   Atomically: read → increment → decide action → write back → release lock.
#   Output (stdout): {"before": N, "after": N, "threshold": N, "action": "increment"|"full-sync"}
#   When action == "full-sync", the counter is written back as 0. When action == "increment", the counter is written back as `after`.

# Usage: shelf-counter.sh ensure-defaults
#   If .shelf-config is missing either key, appends it with the default value.
#   Idempotent. Called by the init path + on first read.
```

**Bash prototype for `increment-and-decide` (core of the primitive)**:

```bash
SHELF_CONFIG="${SHELF_CONFIG:-.shelf-config}"
LOCK_FILE="${SHELF_CONFIG}.lock"

# Portable exclusive lock using flock (Linux/macOS with util-linux-flock installed).
# Fallback path: if flock not found, proceed without a lock (±1 drift accepted per FR-006).
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  flock -x 9
  TRAP_CLEANUP='flock -u 9 2>/dev/null; rm -f "$LOCK_FILE" 2>/dev/null'
  trap "$TRAP_CLEANUP" EXIT
fi

# Ensure defaults (idempotent — does nothing if keys already present)
_ensure_key() {
  local key="$1" default="$2"
  if ! grep -qE "^${key}[[:space:]]*=" "$SHELF_CONFIG" 2>/dev/null; then
    printf '%s = %s\n' "$key" "$default" >> "$SHELF_CONFIG"
  fi
}
_ensure_key "shelf_full_sync_counter" "0"
_ensure_key "shelf_full_sync_threshold" "10"

# Read values (tolerant of spaces)
_read_key() {
  local key="$1" default="$2"
  local v
  v=$(grep -E "^${key}[[:space:]]*=" "$SHELF_CONFIG" | tail -1 | sed -E 's/^[^=]+=[[:space:]]*//' | tr -d ' \t')
  [[ -z "$v" ]] && v="$default"
  printf '%s\n' "$v"
}

BEFORE=$(_read_key "shelf_full_sync_counter" "0")
THRESHOLD=$(_read_key "shelf_full_sync_threshold" "10")

AFTER=$((BEFORE + 1))
if [[ "$AFTER" -ge "$THRESHOLD" ]]; then
  ACTION="full-sync"
  NEW_VAL=0
else
  ACTION="increment"
  NEW_VAL="$AFTER"
fi

# Write back — in-place replace the counter line
#   Use a tmp file + mv for atomicity.
TMP=$(mktemp)
awk -v key="shelf_full_sync_counter" -v val="$NEW_VAL" '
  BEGIN { replaced = 0 }
  $0 ~ "^" key "[[:space:]]*=" { print key " = " val; replaced = 1; next }
  { print }
  END { if (!replaced) print key " = " val }
' "$SHELF_CONFIG" > "$TMP"
mv "$TMP" "$SHELF_CONFIG"

# Release lock explicitly (trap handles abnormal exit)
[[ -n "${TRAP_CLEANUP:-}" ]] && eval "$TRAP_CLEANUP" && trap - EXIT

printf '{"before":%d,"after":%d,"threshold":%d,"action":"%s"}\n' \
  "$BEFORE" "$((ACTION == "full-sync" ? THRESHOLD : AFTER))" "$THRESHOLD" "$ACTION"
```

Two important properties:
- The lock is released BEFORE the caller runs `shelf-sync` (the caller's bg sub-agent shell invokes `shelf-counter.sh` in its own process; the lock dies with that process).
- If `flock` is absent, the script still runs — missing flock means no exclusive lock, accepting ±1 drift per FR-006.

**Concurrency invariant**: with flock, at most one increment-and-decide runs at a time; either sub-agent sees a distinct `before` value and writes a distinct `after` value. No lost updates.

**Fallback portability**: Bash-on-Windows (Git Bash) ships without `flock` in some builds. The script's `command -v flock` guard handles this — the script runs unlocked, and the FR-006 ±1 drift contract covers it.

## Design decisions

### Why a new sub-workflow instead of inlining the Obsidian write into `kiln-report-issue.json`?

`shelf-write-issue-note` is a distinct, reusable unit: it's the "write a single backlog issue to Obsidian" primitive. Future skills (`/kiln:kiln-todo`, `/kiln:kiln-mistake`) could call the same sub-workflow. Keeping it separate avoids Obsidian MCP logic bleeding into `plugin-kiln/`. It also makes the `kiln-report-issue` top-level workflow easier to read — four step IDs, each with a crisp purpose.

### Why remove the inline `propose-manifest-improvement` from `shelf-sync` instead of leaving it?

The current duplication (reflection runs inside `shelf-sync` AND as a top-level step of `kiln-report-issue`) is a bug on top of a performance problem. Once reflection moves to the background sub-agent, leaving it nested inside `shelf-sync` would cause two reflections per full-sync: one inside the nested call and one as a sibling. Cleaner to remove it from `shelf-sync` and treat reflection as a top-level concern that its caller orchestrates — which is exactly what the background sub-agent does.

### Why default threshold of 10?

Per PRD assumption: frequent enough that Obsidian drift stays bounded (≤10 un-reconciled issues at any time is acceptable), sparse enough to amortize the ~64.5k-token sync cost (ratio ~6.45k tokens per report-issue on average, vs. current 64.5k — matches SC-001's "≤25% of baseline" target comfortably).

### Why a per-day log file?

Per-day files stay small and are naturally bounded (rotating without explicit rotation logic). Grep by date is cheap (`grep ... .kiln/logs/report-issue-bg-2026-04-22.md`). Alternative of a single rolling file would grow unbounded; rotation would be an extra concern not worth solving for a debug log.

### Why dispatch as a standalone step instead of inlining "spawn sub-agent" at the end of `write-issue-note`?

Separation of concerns: `write-issue-note` is a pure content write; making it also spawn a sub-agent couples unrelated responsibilities. Discrete steps are easier to debug (wheel state shows exactly which step fired) and easier to test in isolation (`/wheel:wheel-run shelf:shelf-write-issue-note` works standalone).

## Assumptions

- The wheel `agent`-type step with `Agent` + `run_in_background: true` returns control to the foreground as soon as the outer agent writes its output file, NOT waiting for the background sub-agent to complete. This is based on the existing pattern in `plugin-wheel/lib/dispatch.sh:1731` + the `dispatch_agent` semantics in `plugin-wheel/lib/dispatch.sh:549` (step advances on output-file detection). Smoke test Phase H validates empirically.
- The Obsidian MCP surface (both projects and manifest scopes) is available to sub-agents spawned via the `Agent` tool in the same Claude Code session (inherited MCP — standard behavior). Smoke test Phase H validates.
- `flock` is present on macOS + Linux dev machines in typical kiln-user setups. Fallback handles exotic environments.
- The existing `.shelf-config` key-value format is stable and safe to append to. Verified against this repo's `.shelf-config` — no JSON/TOML, just plain k=v lines.

## Risks

| Risk | Mitigation |
|------|------------|
| `run_in_background: true` inside wheel `agent` step actually blocks foreground (unknown 1 manifests as a problem) | Phase E smoke test catches this. Fallback: switch to `command`-type disowned subshell (documented above). |
| Background sub-agent doesn't inherit MCP | Phase E smoke test exercises a triggered full-sync (counter=threshold-1 → run once). If MCP missing, the sub-agent fails at `obsidian-apply` and logs `action=error`. |
| Counter lockfile accumulates stale entries | Trap cleanup removes it on normal exit; on abnormal exit, next run recreates it — lockfile is idempotent. |
| Removing inline `propose-manifest-improvement` from `shelf-sync` surprises a consumer who relied on it | Documented in CLAUDE.md + `shelf-sync` SKILL.md. Scan via `grep -r 'shelf-sync' plugin-*/` pre-merge to confirm no internal automation depends on the nested behavior. |
| Two concurrent bg sub-agents both enter `full-sync` branch (counter=9 → both see 9 → both increment to 10 → both reset → both run shelf-sync) | Acceptable: `shelf-sync` is idempotent (upserts). The counter lock ensures they don't both see `before=9`; the first to acquire the lock sees `before=9`, writes 0; the second sees `before=0`, writes 1. Only one full-sync fires per 10 invocations. |
| `.wheel/outputs/dispatch-background-sync.txt` written before background sub-agent actually starts, causing wheel to archive state before the sub-agent is alive | In practice the `Agent` tool call returns synchronously once the sub-agent is spawned; only its execution is asynchronous. Writing the output file after the `Agent` tool call returns is safe. |

## Contracts

See `contracts/interfaces.md`. Three things have external surfaces:

1. The `shelf-write-issue-note` sub-workflow (inputs from caller, outputs).
2. The background sub-agent's side effects (`.shelf-config` mutation, log write, optional `shelf-sync`/`reflect` invocation).
3. The `.shelf-config` key schema additions.
