# Interface Contracts: Vision Tooling

**Constitution Article VII** — every exported helper script and skill orchestrator entry point below is documented with EXACT invocation signature, env vars, stdout shape, exit codes, side-effects, and error shape. All implementation MUST match these signatures verbatim. Signature changes MUST update this file FIRST.

Contracts are organised by theme. All scripts are bash, executable, and live under `plugin-kiln/scripts/<subdir>/`. Skills are markdown files under `plugin-kiln/skills/<skill>/SKILL.md`.

Conventions:

- Every script reads positional args via `$1..$N` and recognised flags via getopts/manual-parse — flags never collide with positionals across the contract surface.
- `KILN_TEST_MOCK_LLM_DIR` (env var, optional) — when set to a directory containing pre-baked LLM response fixtures, LLM-mediated helpers MUST consume the fixture instead of invoking `claude --print`. CLAUDE.md Rule 5 mock-injection contract.
- Exit codes: `0` success, `1` user error (bad args / contract violation), `2` validation refusal (e.g., flag conflict, missing section), `3` infrastructure error (lock contention, missing required file), `4` LLM failure (non-fatal; caller may degrade).
- All vision-mutating writes go through `vision-write-section.sh`. No script writes to `.kiln/vision.md` directly.
- All declined-record writes go through `vision-forward-decline-write.sh`. No script writes under `.kiln/roadmap/items/declined/` directly.

---

## Theme A — Simple-params CLI

### `plugin-kiln/scripts/roadmap/vision-section-flag-map.sh` *(FR-021)*

Single source of truth for the flag → section mapping table. Sourceable as a library; also runnable to print the table.

**Invocation (library mode)**: `source vision-section-flag-map.sh`. Exports two associative arrays:

- `VISION_FLAG_TO_SECTION` — keys = canonical flag (without leading `--`); values = literal section header line as it appears in `.kiln/vision.md` (e.g., `## Guiding constraints`).
- `VISION_FLAG_OP` — keys = same; values ∈ `{append-bullet, append-paragraph, replace-body}`.

**Invocation (CLI mode)**: `vision-section-flag-map.sh [--list]` — prints one line per supported flag in `flag\tsection\toperation` (tab-separated) format on stdout.

**Stdout (CLI mode)**: tab-separated, one line per flag, sorted alphabetically by flag name. Deterministic.

**Exit codes**: 0 always (CLI mode); function-return 0 (library mode).

**Side-effects**: none.

**Errors**: none.

---

### `plugin-kiln/scripts/roadmap/vision-flag-validator.sh` *(FR-005)*

Validates argv before any I/O. Asserts at most one `--add-*` OR one `--update-*` flag is present.

**Invocation**: `vision-flag-validator.sh -- "$@"` (where `"$@"` is the remainder of `kiln-roadmap`'s argv after `--vision`).

**Stdout**: on success, single line containing the canonical normalised flag (e.g., `--add-constraint`) followed by a tab and the value text. On any other case, empty stdout.

**Stderr**: on validation failure, one line `vision: <reason>` (e.g., `vision: --add-constraint and --add-non-goal are mutually exclusive`).

**Exit codes**:
- `0` exactly one supported simple-params flag with a non-empty value (stdout populated).
- `0` AND empty stdout — no simple-params flags present (caller dispatches the coached interview).
- `2` two or more simple-params flags, OR a flag with no value, OR an unrecognised `--add-*`/`--update-*` flag.

**Side-effects**: none. **MUST NOT** read or touch `.kiln/vision.md`.

---

### `plugin-kiln/scripts/roadmap/vision-write-section.sh` *(FR-001 / FR-002 / FR-003)*

Atomic temp+mv writer. Bumps `last_updated:` BEFORE the body change. Acquires `.kiln/.vision.lock` (flock-when-available; ±1 drift on macOS — same pattern as `plugin-shelf/scripts/shelf-counter.sh`).

**Invocation**: `vision-write-section.sh <flag> <text>` where `<flag>` is one of the canonical normalised flags from `vision-section-flag-map.sh`.

**Stdout**: on success, single line `vision: wrote <flag> at <YYYY-MM-DD>`. Deterministic given same inputs.

**Stderr**: on failure, `vision: <reason>` plus a non-zero exit.

**Exit codes**:
- `0` success — vision file mutated, last_updated bumped, write committed atomically.
- `2` flag's target section not found in `.kiln/vision.md` (FR-021 maintenance contract gap).
- `3` lock contention OR temp-write failure OR mv failure. **Vision file MUST be byte-identical to pre-invocation state on any non-zero exit.**

**Side-effects**:
- Reads `.kiln/vision.md`.
- Writes `.kiln/vision.md.tmp.<pid>` then atomically `mv` to `.kiln/vision.md`.
- Acquires/releases `.kiln/.vision.lock`.
- Updates the `last_updated:` value in YAML frontmatter to `date -u +%Y-%m-%d`. The bump happens to the in-memory copy BEFORE the body mutation; both land in the same atomic write.

**Inputs from environment**:
- `KILN_REPO_ROOT` (optional) — defaults to `$(git rev-parse --show-toplevel)`.

---

### `plugin-kiln/scripts/roadmap/vision-shelf-dispatch.sh` *(FR-004)*

Wraps the existing shelf mirror dispatch path. Warn-and-continue when `.shelf-config` is missing/incomplete.

**Invocation**: `vision-shelf-dispatch.sh` (no arguments).

**Stdout**: on dispatch fired, byte-identical to the existing coached-interview dispatch output. On warn-and-continue, single line `shelf: .shelf-config not configured; skipping mirror dispatch (warning shape matches kiln-roadmap)`.

**Stderr**: empty on the success-path; the existing dispatch's diagnostics on actual dispatch failures.

**Exit codes**:
- `0` always — dispatch fired OR warn-and-continue. The warn-path MUST NOT bubble up as failure (FR-004).

**Side-effects**: invokes existing `shelf:shelf-write-roadmap-note` MCP write through `claude --print` exactly as the coached path does. Reads `.shelf-config`. Does NOT mutate `.kiln/vision.md`.

---

## Theme B — Vision-alignment check

### `plugin-kiln/scripts/roadmap/vision-alignment-walk.sh` *(FR-006)*

Walks `.kiln/roadmap/items/*.md` and emits open-item paths.

**Invocation**: `vision-alignment-walk.sh`.

**Stdout**: one path per line, sorted alphabetically. Deterministic. Each line is a path RELATIVE to repo root (e.g., `.kiln/roadmap/items/2026-04-24-foo.md`).

**Filter**: `status != shipped` AND `state != shipped`. Items lacking either field are treated as open. Items under `.kiln/roadmap/items/declined/` ARE INCLUDED only if they don't carry `state: shipped` (declined-records have `kind: non-goal`; not auto-excluded — caller decides).

**Exit codes**: `0` always. Empty stdout = no open items.

**Side-effects**: none.

---

### `plugin-kiln/scripts/roadmap/vision-alignment-map.sh` *(FR-007)*

LLM-mediated. Maps a single item to ≥0 vision pillars.

**Invocation**: `vision-alignment-map.sh <item-path>`.

**Stdout**: zero or more lines, each a single pillar id (slug-form derived from the bullet text under `## Guiding constraints` — first dash-prefixed word phrase). Sorted alphabetically. Deterministic GIVEN a fixed LLM response (mock or real).

**Exit codes**:
- `0` — mapping returned (may be empty for a Drifter).
- `4` — LLM call failed; caller may treat as Drifter or retry. The orchestrator (`vision-alignment-render.sh`'s caller) treats `4` as Drifter for V1.

**Side-effects**: invokes `claude --print` with a prompt grounded by `read-project-context.sh` from PR #157 unless `KILN_TEST_MOCK_LLM_DIR` is set.

**Mock-injection (CLAUDE.md Rule 5)**: if `KILN_TEST_MOCK_LLM_DIR` is set, the script reads `${KILN_TEST_MOCK_LLM_DIR}/<basename-of-item>.txt` and emits its content verbatim on stdout. No LLM call.

---

### `plugin-kiln/scripts/roadmap/vision-alignment-render.sh` *(FR-008 / FR-009)*

Renders the 3-section report. Report-only — never mutates anything.

**Invocation**: `vision-alignment-render.sh` (reads piped input via stdin OR walks via `vision-alignment-walk.sh` when stdin is a tty).

**Stdin**: if not a tty, expected format = lines of `<item-path>\t<pillar-1>,<pillar-2>,...` (tab-separated; comma-separated pillar list; empty list for Drifters).

**Stdout**: the full report. Deterministic given fixed inputs:

```
Mappings are LLM-inferred; re-runs on unchanged inputs may differ. For deterministic mapping, declare addresses_pillar: explicitly per item (V2 schema extension).

## Aligned items

<item-id> → <pillar>
... (sorted by item-id ASC; one line per item-pillar pair; an item with N pillars produces N lines)

## Multi-aligned items

<item-id> → <pillar-1>, <pillar-2>, ...
... (sorted by item-id ASC; only items with ≥2 pillars; pillar list comma-separated, original mapping order preserved)

## Drifters

<item-id>
... (sorted by item-id ASC; items with ZERO pillars)
```

If a section has no items, the section header still emits and the body is the literal line `(none)`.

**Exit codes**: `0` always.

**Side-effects**: none. MUST NOT mutate any file.

---

## Theme C — Forward-looking coaching

### `plugin-kiln/scripts/roadmap/vision-forward-pass.sh` *(FR-010 / FR-011)*

Generates ≤5 forward-pass suggestions. Excludes any whose `(title, tag)` appears in the loaded declined-set.

**Invocation**: `vision-forward-pass.sh [--declined-set <path>]`. The `--declined-set` flag points to a file produced by `vision-forward-dedup-load.sh`; absent → no exclusions.

**Stdout**: zero to five suggestion blocks, separated by a single blank line. Each block is exactly four lines:

```
title: <one-line title, no tabs>
tag: <gap|opportunity|adjacency|non-goal-revisit>
evidence: <file-path-or-commit-hash>:<optional-anchor>
body: <one-line body summary, ≤200 chars>
```

**Exit codes**:
- `0` — suggestions generated (may be empty).
- `4` — LLM call failed; caller skips the forward pass.

**Mock-injection**: `KILN_TEST_MOCK_LLM_DIR` → reads `${KILN_TEST_MOCK_LLM_DIR}/forward-pass.txt` verbatim instead of calling `claude --print`.

---

### `plugin-kiln/scripts/roadmap/vision-forward-decision.sh` *(FR-012)*

Per-suggestion confirm-never-silent prompt. Reads ONE suggestion block (4 lines) on stdin and emits the chosen action on stdout.

**Invocation**: `vision-forward-decision.sh` (interactive — reads suggestion on stdin, prompts on stderr/tty, reads choice from stdin/tty).

**Stdin** (suggestion block, 4 lines): same shape as `vision-forward-pass.sh` stdout.

**Stdout**: single line `accept|decline|skip`.

**Stderr**: the rendered prompt (suggestion summary + the literal `[a]ccept / [d]ecline / [s]kip:` line).

**Exit codes**: `0` always (user chose). `2` if stdin is malformed.

**Side-effects**: none directly. Caller is responsible for invoking `vision-forward-decline-write.sh` (on `decline`) or the `--promote` hand-off (on `accept`).

---

### `plugin-kiln/scripts/roadmap/vision-forward-decline-write.sh` *(FR-013 / FR-022)*

Writes a `kind: non-goal` declined-record file under `.kiln/roadmap/items/declined/<date>-<slug>-considered-and-declined.md`.

**Invocation**: `vision-forward-decline-write.sh <title> <tag> <body> <evidence>`.

**Stdout**: single line `declined: <path-written>`. Path is repo-root-relative.

**Exit codes**:
- `0` success.
- `2` slug collision — file with the same `<date>-<slug>-considered-and-declined.md` already exists; appends a `-N` suffix and retries up to N=9 before failing with `2`.
- `3` filesystem error.

**Side-effects**: creates `.kiln/roadmap/items/declined/` if missing. Writes one new file. No other I/O.

**File shape**: YAML frontmatter `title:`, `tag:`, `kind: non-goal`, `state: declined`, `declined_date: <YYYY-MM-DD>`, `evidence: <evidence>`. Body = the `body` arg.

---

### `plugin-kiln/scripts/roadmap/vision-forward-dedup-load.sh` *(FR-013)*

Loads the declined-set into a tab-separated `<title>\t<tag>` index file consumable by `vision-forward-pass.sh`.

**Invocation**: `vision-forward-dedup-load.sh > /tmp/declined-set.txt`.

**Stdout**: zero or more lines `<title>\t<tag>`, sorted by title ASC. Deterministic.

**Exit codes**: `0` always (empty stdout when `.kiln/roadmap/items/declined/` is missing or empty).

**Side-effects**: none.

---

## Theme D — Win-condition scorecard

### `plugin-kiln/scripts/metrics/orchestrator.sh` *(FR-015 / FR-019)*

Walks the eight extractors, aggregates rows, writes the report to BOTH stdout AND `.kiln/logs/metrics-<UTC-timestamp>.md`.

**Invocation**: `orchestrator.sh`.

**Stdout**: the full report (caveat header + table). Deterministic given a frozen repo state.

**Report shape**:

```
# Vision Scorecard — <UTC-timestamp>

| signal | current_value | target | status | evidence |
|---|---|---|---|---|
| (a) | <v> | <t> | <on-track|at-risk|unmeasurable> | <cite> |
| (b) | ... |
| ... | (eight rows total, a..h, in alphabetical order) |
```

**Exit codes**: `0` always (FR-017 graceful degrade — extractor failures land as `unmeasurable` rows, NOT non-zero exit).

**Side-effects**:
- Creates `.kiln/logs/` if missing.
- Writes `.kiln/logs/metrics-<UTC-timestamp>.md` (timestamp format `%Y-%m-%d-%H%M%S`). Never overwrites an existing log; if a collision somehow occurs (sub-second double-invocation), appends `-N`.

**Inputs from environment**:
- `KILN_REPO_ROOT` (optional).
- `KILN_METRICS_NOW` (optional, for test-determinism) — overrides the timestamp.

---

### `plugin-kiln/scripts/metrics/render-row.sh` *(FR-016)*

Renders a single scorecard row in the prescribed pipe-delimited shape.

**Invocation**: `render-row.sh <signal-id> <current-value> <target> <status> <evidence>`.

**Stdout**: single line `| <signal-id> | <current-value> | <target> | <status> | <evidence> |`. Pipes inside argument values are escaped to `\|`.

**Exit codes**:
- `0` valid row.
- `2` `<status>` not in `{on-track, at-risk, unmeasurable}`.

**Side-effects**: none.

---

### `plugin-kiln/scripts/metrics/extract-signal-<a..h>.sh` *(FR-018)*

Eight scripts, one per signal. All eight share the SAME contract.

**Invocation**: `extract-signal-<x>.sh` (no arguments).

**Stdout** (success path — exit `0`): exactly one line, tab-separated:

```
<signal-id>\t<current-value>\t<target>\t<on-track|at-risk>\t<evidence>
```

**Stdout** (unmeasurable path — exit `4`): exactly one line:

```
<signal-id>\t-\t-\tunmeasurable\t<reason>
```

**Exit codes**:
- `0` measured value emitted.
- `4` unmeasurable — orchestrator passes through to the report row as `status: unmeasurable` with the reason as evidence. Orchestrator MUST NOT propagate `4` as overall failure (FR-017).
- `1` programmer error in the extractor itself (caught by orchestrator and converted to `unmeasurable` with `evidence: extractor error`).

**Side-effects**: read-only — extractors MUST NOT write to disk. They MAY shell out to `git`, `jq`, find/grep across `.kiln/`, `.wheel/history/`, `docs/features/`, `plugin-kiln/tests/` outputs.

**Per-signal evidence-source table** (informational, not normative beyond the contract):

| Signal | Evidence source |
|---|---|
| `(a)` | `git log --grep='Co-Authored-By: Claude' --merges` filtered for `build-prd` PRs that closed `idea-*` issues |
| `(b)` | `.wheel/history/*.jsonl` parse for `escalation` events over 90 days |
| `(c)` | `docs/features/*/PRD.md` `derived_from:` ↔ `.kiln/{issues,feedback,roadmap/items}` |
| `(d)` | `.kiln/mistakes/` ↔ Obsidian `@inbox/closed/` (read-only sync via shelf MCP) |
| `(e)` | `.kiln/logs/hook-*.log` (last 30 days) |
| `(f)` | `.shelf-config` audit + `.trim/` last-sync |
| `(g)` | `plugin-kiln/tests/` recent run records |
| `(h)` | `.kiln/roadmap/items/declined/` cross-referenced with `.kiln/feedback/` external-source flags |

---

## Skill orchestrator entry points

### `plugin-kiln/skills/kiln-roadmap/SKILL.md` (MODIFIED)

**Modified surface**: argv parsing for `--vision`. New dispatch tree:

1. Run `vision-flag-validator.sh -- "$@"`.
2. If validator returns a canonical `--add-*` or `--update-*` flag with value:
   - `vision-write-section.sh <flag> <text>`
   - `vision-shelf-dispatch.sh`
   - **MUST NOT** invoke the coached interview.
   - **MUST NOT** invoke `vision-forward-pass.sh` (FR-014 / SC-010).
   - exit with the underlying `vision-write-section.sh` exit code.
3. Else if `--check-vision-alignment` flag present:
   - `vision-alignment-walk.sh | while read item; do vision-alignment-map.sh <item> ...; done | vision-alignment-render.sh`
   - exit `0`.
4. Else (coached interview path — NFR-005 byte-identity preserved):
   - run the existing coached `--vision` interview verbatim.
   - on completion, emit the literal prompt `Want me to suggest where the system could go next? [y/N] ` (FR-010).
   - on `y`: run `vision-forward-pass.sh` → loop suggestions through `vision-forward-decision.sh` → on `accept` invoke existing `--promote` hand-off; on `decline` invoke `vision-forward-decline-write.sh`; on `skip` no-op.
   - exit normally.

**Help text (`--help`)**: enumerates the new flags and the `--check-vision-alignment` mode. Documents the section-flag mapping table (FR-021 maintenance contract surface).

---

### `plugin-kiln/skills/kiln-metrics/SKILL.md` (NEW)

**Surface**: `/kiln:kiln-metrics` (no flags in V1).

**Dispatch**: invokes `plugin-kiln/scripts/metrics/orchestrator.sh`. The orchestrator handles writing both stdout and the timestamped log; the SKILL.md is a thin wrapper.

**Help text**: explains the eight signals, the column shape, the `unmeasurable` graceful-degrade behaviour, and where the log lands (`.kiln/logs/metrics-<timestamp>.md`).

**Plugin manifest registration**: `plugin-kiln/.claude-plugin/plugin.json` MUST be patched to register the new skill. Existing skills' entries are NOT touched.

---

## Cross-cutting test-injection contract (CLAUDE.md Rule 5)

| Helper | Mock env-var | Mock fixture path |
|---|---|---|
| `vision-alignment-map.sh` | `KILN_TEST_MOCK_LLM_DIR` | `${KILN_TEST_MOCK_LLM_DIR}/<basename-of-item>.txt` |
| `vision-forward-pass.sh` | `KILN_TEST_MOCK_LLM_DIR` | `${KILN_TEST_MOCK_LLM_DIR}/forward-pass.txt` |
| `orchestrator.sh` (Theme D) | `KILN_METRICS_NOW` | string value (UTC timestamp override) |

No other helper invokes the LLM substrate. Theme A is fully deterministic without mocking.

---

## Determinism summary (NFR-001 audit)

| Surface | Deterministic | Notes |
|---|---|---|
| Theme A simple-params writes | YES | Atomic temp+mv; same input → byte-identical vision.md mutation. |
| Theme B report shape | YES | Sort order ASC, caveat header verbatim, section order fixed. |
| Theme B mappings | NO (LLM) | Caveat header surfaces this verbatim per FR-007. |
| Theme C suggestions | NO (LLM) | Per-suggestion confirm-never-silent + decline persistence per FR-012/013. |
| Theme D extractors | YES | Read-only deterministic shell. |
| Theme D orchestrator output | YES (modulo timestamp) | `KILN_METRICS_NOW` override locks it for fixtures. |
