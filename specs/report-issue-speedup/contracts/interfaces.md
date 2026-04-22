# Interface Contracts: Report-Issue Speedup

**Spec**: `specs/report-issue-speedup/spec.md`
**Plan**: `specs/report-issue-speedup/plan.md`

This feature is a workflow refactor, not a typed-library addition. "Interfaces" here are the external surfaces that callers and future maintainers rely on: the new sub-workflow's input/output contract, the background sub-agent's side-effect contract, and the `.shelf-config` key schema.

---

## 1. `shelf-write-issue-note` sub-workflow

**Location**: `plugin-shelf/workflows/shelf-write-issue-note.json`
**Invoked by**: `plugin-kiln/workflows/kiln-report-issue.json` (new `write-issue-note` step, `type: workflow`).
**Standalone invocation**: `/wheel:wheel-run shelf:shelf-write-issue-note` — supported but expects the context below to be present.

### Inputs (from parent workflow context_from)

Must receive via wheel's `context_from` mechanism:

| Key | Source step | Description |
|-----|-------------|-------------|
| `create-issue` output | `plugin-kiln/workflows/kiln-report-issue.json` step `create-issue` | The confirmation summary written by the create-issue agent. Includes: new issue file path, title, type, severity, category, github_issue (nullable). Format is the markdown blob currently at `.wheel/outputs/create-issue-result.md`. |
| `.shelf-config` | read by the sub-workflow's own `read-shelf-config` step | For `slug` + `base_path` — used to compute the Obsidian note target path. |

### Outputs

The final step of `shelf-write-issue-note` writes a JSON output to `.wheel/outputs/shelf-write-issue-note-result.json`:

```json
{
  "issue_file": ".kiln/issues/2026-04-22-example-slug.md",
  "obsidian_path": "@second-brain/projects/ai-repo-template/issues/2026-04-22-example-slug.md",
  "action": "created",
  "errors": []
}
```

| Field | Type | Description |
|-------|------|-------------|
| `issue_file` | string | Absolute-from-repo-root path to the local `.kiln/issues/<file>.md`. |
| `obsidian_path` | string | The Obsidian MCP path the note was written to. |
| `action` | enum `"created"` \| `"patched"` | `"created"` if new, `"patched"` if the note already existed (cold-start collision fallback). |
| `errors` | array of strings | Empty on success. |

### Side effects

- Exactly ONE Obsidian note write at `<base_path>/<slug>/issues/<basename-of-issue-file>`.
- No changes to `.kiln/issues/`, no dashboard update, no progress update, no GitHub fetch, no manifest-scope writes.

### Non-goals (enforced by step list)

- MUST NOT call `mcp__claude_ai_obsidian-manifest__*` tools.
- MUST NOT call `mcp__claude_ai_obsidian-projects__list_files`, `append_file`, or any other write other than `create_file` (with `patch_file` fallback on collision).
- MUST NOT invoke `shelf-propose-manifest-improvement`.

---

## 2. Background sub-agent

**Launched by**: `dispatch-background-sync` step of `plugin-kiln/workflows/kiln-report-issue.json` via the Claude Code `Agent` tool with `run_in_background: true`.
**Lifetime**: Independent of foreground workflow. May outlive the Stop event that ends the foreground skill.

### Inputs (env / prompt-embedded)

The outer dispatcher embeds these in the sub-agent's prompt — no external env vars required:

| Name | Source | Description |
|------|--------|-------------|
| `SHELF_CONFIG_PATH` | defaults to `.shelf-config` (repo root, relative to cwd at spawn time) | Config file to read/modify. |
| `COUNTER_LOCK_PATH` | defaults to `.shelf-config.lock` | Sibling lockfile. |
| `BG_LOG_DIR` | defaults to `.kiln/logs/` | Directory for per-day log files. |
| `WORKFLOW_PLUGIN_DIR` | inherited from wheel runtime | Used to resolve helper script paths. |

### Side effects

On every invocation, exactly one of:

**Increment path** (counter below threshold):
1. `.shelf-config` — `shelf_full_sync_counter` value updated by +1.
2. `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` — one line appended (see FR-009 format).

**Full-sync path** (counter reaches threshold):
1. `.shelf-config` — `shelf_full_sync_counter` reset to `0`.
2. `/shelf:shelf-sync` invoked to completion — writes issue notes, docs, dashboard, progress entries (all pre-existing `shelf-sync` side effects).
3. `/shelf:shelf-propose-manifest-improvement` invoked to completion — optionally writes one proposal file in `@inbox/open/` (silent no-op if no actionable improvement identified).
4. `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` — one line appended with `action=full-sync`.

**Error path** (any helper script or sub-skill fails):
1. One line appended to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` with `action=error` and short `notes` field.
2. Sub-agent exits 0 — never hangs, never retries, never bubbles an error up.

### Idempotence

- Overlapping background sub-agents are safe: the counter lock (see §4) serializes the critical section; both `shelf-sync` and `shelf-propose-manifest-improvement` are re-entrant (upserts + silent-no-op behavior).
- If two bg sub-agents race to the full-sync branch (both see `before=threshold-1`), the lock ensures only one observes that value. The second sees `before=0` and takes the increment path.

### Observability

`.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` line format (pipe-delimited, grep-friendly):

```
<ISO-8601 UTC timestamp> | counter_before=<N> | counter_after=<N> | threshold=<N> | action=<increment|full-sync|error> | notes=<string-or-empty>
```

---

## 3. Counter helper library — `plugin-shelf/scripts/shelf-counter.sh`

Three subcommands. All are shell-level primitives; no other external callers are expected beyond the background sub-agent and the dispatch step.

### `shelf-counter.sh read`

**Purpose**: display-only read of counter + threshold. No lock, no mutation.

**Arguments**: none.

**Stdout**: JSON `{"counter": N, "threshold": N}`.

**Exit**: 0 always.

**Side effects**: none (except auto-writing defaults if keys are missing — see FR-005).

### `shelf-counter.sh increment-and-decide`

**Purpose**: the critical section. Atomically read counter + threshold, increment, decide action, write back, release lock.

**Arguments**: none.

**Stdout** (single JSON line):
```json
{"before": N, "after": N, "threshold": N, "action": "increment" | "full-sync"}
```

- `before` — counter value before increment.
- `after` — counter value written back (equal to `before+1` on `increment` action, equal to `0` on `full-sync` action).
- `threshold` — from config.
- `action` — `"increment"` if `before+1 < threshold`, `"full-sync"` if `before+1 >= threshold`.

**Exit**: 0 on success.

**Side effects**: `.shelf-config` mutated (single key rewritten atomically via tempfile+mv).

**Locking**: acquires exclusive `flock` on `$COUNTER_LOCK_PATH`. Releases before stdout is written. If `flock` unavailable, proceeds unlocked with ±1 drift accepted (per FR-006).

### `shelf-counter.sh ensure-defaults`

**Purpose**: idempotent addition of defaults to `.shelf-config` if missing. Called by init path.

**Arguments**: none.

**Stdout**: optional human-readable confirmation.

**Exit**: 0 always.

**Side effects**: appends `shelf_full_sync_counter = 0` and/or `shelf_full_sync_threshold = 10` to `.shelf-config` if either key is missing.

---

## 4. Log helper — `plugin-shelf/scripts/append-bg-log.sh`

**Purpose**: append one line to the per-day background log file.

**Arguments** (positional):

1. `counter_before` (integer)
2. `counter_after` (integer)
3. `threshold` (integer)
4. `action` (string: `increment`, `full-sync`, or `error`)
5. `notes` (optional string, default empty)

**Stdout**: none (or one line echoing the appended line — OK either way).

**Exit**: 0 always (log failures don't crash the bg sub-agent).

**Side effects**: creates `.kiln/logs/` if missing, creates per-day file if missing, appends one line in the FR-009 format.

---

## 5. `.shelf-config` key schema additions

Both keys follow the existing format convention (`key = value`, spaces around `=`, `#` comments supported).

| Key | Type | Default | Added by | Read by |
|-----|------|---------|----------|---------|
| `shelf_full_sync_counter` | integer (≥0) | `0` | scaffold (new projects), `ensure-defaults` (existing projects) | `shelf-counter.sh read`, `shelf-counter.sh increment-and-decide` |
| `shelf_full_sync_threshold` | integer (≥1) | `10` | same as above | same as above |

**Auto-upgrade rule**: when either helper is called and either key is missing, the default value is APPENDED to `.shelf-config` (no reformatting of existing keys, no loss of comments). Subsequent calls are no-ops.

**Parsing tolerances** (matches existing format):
- Whitespace around `=` permitted (zero or more spaces/tabs).
- Integer value with no surrounding quotes.
- Lines starting with `#` are ignored.
- Last occurrence wins (duplicate keys — tolerated but not generated).

---

## 6. Foreground workflow top-level contract

**`plugin-kiln/workflows/kiln-report-issue.json`** after this feature:

| Step index | id | type | terminal? | notes |
|------------|-----|------|-----------|-------|
| 0 | `check-existing-issues` | command | no | unchanged |
| 1 | `create-issue` | agent | no | unchanged |
| 2 | `write-issue-note` | workflow | no | new; invokes `shelf:shelf-write-issue-note` |
| 3 | `dispatch-background-sync` | agent | YES | new; fire-and-forget spawn; output file `.wheel/outputs/dispatch-background-sync.txt` |

No other steps. The removed steps (`propose-manifest-improvement`, `full-sync`) are gone.

**`plugin-shelf/workflows/shelf-sync.json`** after this feature: unchanged except the step with `id: propose-manifest-improvement` is removed. All other step IDs and `context_from` references remain valid.
