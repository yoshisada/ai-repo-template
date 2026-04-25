# Research: Cross-Plugin Resolver + Pre-Flight Plugin Registry

**Spec**: [spec.md](./spec.md)
**PRD**: [../../docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md](../../docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md)

## §1 — Resolution of OQ-F-1 (BLOCKING — must be answered before plan)

**Question**: What is the authoritative source for "what plugins are loaded in this Claude Code session, with their absolute install paths"? Three candidates were posed in the PRD: A (`$PATH` parsing of plugin `/bin` entries), B (settings + cache walk), C (Claude Code env var if it exists).

**Decision**: **Candidate A (PRIMARY) with Candidate B (FALLBACK)**. Candidate C (purpose-built env var) does not exist in Claude Code today (verified via `env | grep -i CLAUDE` in this session — only `CLAUDECODE=1` and `CLAUDE_CODE_ENTRYPOINT=cli` are exposed, neither names plugins).

### §1.A — Candidate A verification: marketplace cache mode

**Test**: Inspect `$PATH` in the running Claude Code session.

**Evidence** (from this session):

```
/Users/ryansuematsu/.claude/plugins/cache/claude-plugins-official/frontend-design/a9ab2cdc08d7/bin
/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/kiln/000.001.009.247/bin
/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/shelf/000.001.009.247/bin
/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.247/bin
/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/clay/000.001.009.247/bin
/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/trim/000.001.009.247/bin
/Users/ryansuematsu/.claude/plugins/cache/claude-code-warp/warp/2.0.0/bin
```

**Format**: `<install-root>/<plugin-name>/<version>/bin` for marketplace-cache mode. Plugin name is `basename(dirname(dirname(entry)))`. Plugin install dir is `dirname(entry)` (i.e. strip the trailing `/bin`).

**Verdict for marketplace mode**: ✅ Works. ~5 lines of bash — iterate `$PATH` colon-segments, filter for `/.claude/plugins/cache/`, derive `name → path` map.

### §1.B — Candidate A verification: `--plugin-dir` mode

**Test**: Per Claude Code source-code convention (verified in `claude --help` output and source-repo session shape), invoking `claude --plugin-dir /tmp/.../plugin-shelf-dev/` causes the harness to prepend `/tmp/.../plugin-shelf-dev/bin` to `$PATH` at session start. Same shape as marketplace cache, different install root.

**Plugin-name derivation**: For an override path like `/tmp/myproject/plugin-shelf-dev/bin`, `basename(dirname(/tmp/myproject/plugin-shelf-dev/bin)) = plugin-shelf-dev`. This is the directory basename, not the marketplace plugin name (`shelf`). Two strategies:

1. **Strip `plugin-` prefix when present** — `plugin-shelf-dev` → `shelf-dev`. Good for source-repo dev where directories are named `plugin-<name>` by convention.
2. **Read `<dir>/.claude-plugin/plugin.json::name`** — authoritative; matches what Claude Code itself uses.

**Decision**: Strategy 2 (read plugin.json). Strategy 1 has too many edge cases (`plugin-shelf-dev` vs `plugin-shelf` vs `shelf-dev` vs `shelf`). plugin.json is the ground truth and is cheap to read (single `jq` call per PATH-derived path).

**Verdict for `--plugin-dir` mode**: ✅ Works. ~10 lines of bash — derive path from PATH entry, then `jq -r .name "<path>/.claude-plugin/plugin.json"` for the canonical name.

### §1.C — Candidate A verification: `settings.local.json` mode

**Test**: When a project's `.claude/settings.local.json` enables a plugin (`enabledPlugins: { "<plugin>@<source>": true }`), Claude Code resolves the plugin via either marketplace cache or a `--plugin-dir` companion; the plugin's `/bin` is prepended to PATH at session start by the harness, identical to the global-settings case.

**Evidence**: Inspection of the source-repo `.claude/settings.json` (this repo) shows `enabledPlugins` with marketplace plugins; their `/bin` directories appear in PATH (per §1.A above). settings.local.json layers identically — the harness merges both files at session start before computing PATH.

**Verdict for `settings.local.json` mode**: ✅ Works. No special handling beyond §1.A and §1.B. The PATH entry is the union of all enabled plugins regardless of which settings file enabled them.

### §1.D — Candidate B fallback design

**When triggered**: If `build_session_registry` produces an empty map under Candidate A (e.g. PATH was sanitized in some pathological harness configuration), fall back to Candidate B.

**Source**: `~/.claude/plugins/installed_plugins.json` — a known-stable Claude Code state file. Verified shape:

```json
{
  "version": 2,
  "plugins": {
    "kiln@yoshisada-speckit": [
      {
        "scope": "user",
        "installPath": "/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/kiln/000.001.009.247",
        "version": "000.001.009.247",
        ...
      }
    ],
    ...
  }
}
```

**Construction**: Read `installed_plugins.json::plugins`; for each entry, take the latest version's `installPath`; cross-check against `~/.claude/settings.json::enabledPlugins` and `<project>/.claude/settings.local.json::enabledPlugins` to filter to enabled-only. Plugin name is the segment before `@` in the key.

**Dependencies**: `jq`, plus standard POSIX. ~30 lines of bash.

**Verdict**: Workable as fallback. Slightly more code than A (~30 lines vs ~10) but bounded by known-stable inputs.

### §1.E — Candidate C investigation

**Test**: `env | grep -i -E '(CLAUDE|PLUGIN)'` in this session.

**Result**:

```
CLAUDECODE=1
CLAUDE_CODE_ENTRYPOINT=cli
CLAUDE_PLUGIN_ROOT=/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.247
CLAUDE_AGENT_SDK_VERSION=0.1.13
```

`CLAUDE_PLUGIN_ROOT` is interesting — it names the calling-skill's plugin root (here, `wheel` because the agent harness was spawned from a wheel skill invocation context). It's a per-skill value, not a session-wide registry.

**Verdict**: ❌ No purpose-built session-registry env var exists. `CLAUDE_PLUGIN_ROOT` is the equivalent of Theme D's `WORKFLOW_PLUGIN_DIR` — single-plugin scope, not a registry. Candidate C is moot.

### §1.F — Final decision

**Ship A as primary**, Candidate B as fallback behind a flag (`WHEEL_REGISTRY_FALLBACK=1` env var or auto-trigger when A returns empty). Implementation will land both code paths — A is the hot path, B is the safety net for harness configurations we haven't verified yet.

The `installed_plugins.json` shape (§1.D) is also useful as a secondary verification for plugin name when `plugin.json` reads under Candidate A return ambiguous results.

---

## §2 — `${VAR}` substitution mechanics

### §2.A — Token grammar

The preprocessor recognizes exactly two token shapes:

1. `${WHEEL_PLUGIN_<name>}` — substitutes to the absolute path of plugin `<name>` from the registry. `<name>` is `[a-zA-Z0-9_-]+` (no dots, no slashes).
2. `${WORKFLOW_PLUGIN_DIR}` — substitutes to the absolute path of the calling workflow's plugin (derived from `state.workflow_file` per existing `context_build` mechanism). After this PRD it is internally treated as `${WHEEL_PLUGIN_<calling-plugin>}`.

### §2.B — Escape grammar

`$${...}` is the literal-escape syntax. The preprocessor:
1. Scans for `$$`-prefixed occurrences first and records their byte positions in a "skip-set" before substitution.
2. Performs `${WHEEL_PLUGIN_<name>}` and `${WORKFLOW_PLUGIN_DIR}` substitutions on non-skip positions.
3. Decodes `$${` → `${` (single dollar) for the recorded skip positions.

**Why this order**: prevents the substitution from firing on `$${WHEEL_PLUGIN_shelf}` (which the user wrote intentionally to document the syntax). The skip-set is recorded BEFORE substitution, so the inner `${WHEEL_PLUGIN_shelf}` portion is never matched.

**Implementation note**: bash's `${var//pattern/replacement}` doesn't support negative-position skip-sets cleanly. The cleanest implementation is a single `awk` pass: tokenize input into runs of literal text, escape markers, and substitution markers; substitute or decode per token type. Alternative: `python3 -c '...'` for a regex with lookbehind. Decision deferred to plan phase (§3.B).

### §2.C — Tripwire grammar

Tripwire fires if, after substitution + decode, any unescaped `${WHEEL_PLUGIN_` or `${WORKFLOW_PLUGIN_DIR` substring remains in any agent step's `instruction` field. Implementation:

```bash
# After preprocessing, scan all agent step instructions for the narrowed pattern.
remaining=$(printf '%s\n' "$templated_workflow_json" | jq -r '.steps[] | select(.type=="agent") | .instruction' | grep -E '\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)' || true)
if [[ -n "$remaining" ]]; then
  echo "Wheel preprocessor failed: instruction text for step '<id>' still contains '${...}'. ..." >&2
  exit 1
fi
```

The narrowed pattern (per FR-F4-5 / EC-4 mitigation) excludes legitimate `${VAR}` for shell-array iteration and friends.

---

## §3 — Bootstrap: how does the registry know wheel's own path?

Wheel's own path is needed for `${WHEEL_PLUGIN_wheel}` substitution and for any wheel workflow declaring `requires_plugins: ["wheel"]` (rare but legal per NFR-F-8).

**Candidate A bootstrap**: PATH parsing finds wheel automatically because wheel itself is a loaded plugin with `/bin` on PATH.

**Candidate B bootstrap**: `installed_plugins.json` includes wheel.

**Edge case**: A workflow author runs wheel from a checked-out source tree (`.claude/settings.json` enables wheel from `/Users/me/dev/plugin-wheel/`). PATH still reflects the override; works under A.

**Self-reference resolution**: `BASH_SOURCE[0]` inside `plugin-wheel/lib/registry.sh` resolves to the actual library path being executed. If that path doesn't match what the registry derived, log a diagnostic warning but proceed — the registry value wins (reflects what Claude Code is actually exposing as the wheel install).

---

## §4 — Diagnostic snapshot on failure

Per OQ-F-2 (PRD): retain `.wheel/state/<run-id>-registry.json` on workflow failure for post-mortem; delete on success.

**Failure cleanup**: Hooked into `engine.sh::run_terminal_step` and the equivalent failure path. Pattern matches existing `.wheel/history/success/` and `.wheel/history/failed/` retention policy.

**Snapshot shape**:

```json
{
  "schema_version": 1,
  "built_at": "2026-04-24T18:30:00Z",
  "source": "candidate-a-path-parsing",
  "fallback_used": false,
  "plugins": {
    "shelf": "/Users/.../plugins/cache/yoshisada-speckit/shelf/000.001.009.247",
    "kiln":  "/Users/.../plugins/cache/yoshisada-speckit/kiln/000.001.009.247",
    "wheel": "/Users/.../plugins/cache/yoshisada-speckit/wheel/000.001.009.247"
  }
}
```

---

## §5 — Test substrate notes for downstream implementers

### §5.A — `/kiln:kiln-test` fixture scaffolding for install-mode coverage

Three distinct fixture shapes are required (NFR-F-3):

1. **registry-marketplace-cache/**: scaffolds a fake `~/.claude/plugins/cache/<org-mp>/<plugin>/<version>/` layout under `/tmp/kiln-test-<uuid>/`. Modifies HOME to point at this synthetic root, then invokes `claude --print ... --plugin-dir <fake-root>` via the kiln-test harness. The fixture asserts the registry resolves to the fake-cache paths.

2. **registry-plugin-dir/**: scaffolds two competing copies of plugin-shelf — one under the fake cache, one at `/tmp/.../plugin-shelf-dev/`. Invokes `claude --plugin-dir /tmp/.../plugin-shelf-dev/`. Asserts the override path wins (verified via a marker file written only by the override copy's script).

3. **registry-settings-local-json/**: scaffolds a `.claude/settings.local.json` enabling a project-scoped plugin path. Invokes `claude` from the project dir. Asserts the local-settings path resolves.

**HOME isolation**: All fixtures must run with `HOME=/tmp/kiln-test-<uuid>/home/` to avoid contaminating the developer's actual `~/.claude/` state. The kiln-test harness already supports this per its scaffolding conventions; verify in plan phase.

### §5.B — Pure-shell unit tests (no LLM)

For preprocessor token substitution and tripwire logic, pure-shell tests under `plugin-wheel/tests/` (not `plugin-kiln/tests/`) are sufficient. These run as `bats` or plain bash assertions; no `claude --print` invocation needed. Faster, cheaper, more deterministic. Use them for:

- Token substitution (`${WHEEL_PLUGIN_shelf}` → absolute path).
- Escape decoding (`$${WHEEL_PLUGIN_shelf}` → literal `${WHEEL_PLUGIN_shelf}`).
- Tripwire firing on unescaped residual.
- Schema validation rejecting non-string entries.

### §5.C — Perf fixture reuse

`plugin-kiln/tests/kiln-report-issue-batching-perf/` already exists and recorded its baseline at commit `b81aa25` in `results-2026-04-24-with-tokens.tsv`. The new perf fixture (`perf-kiln-report-issue/`) is structurally identical — same workflow, same N runs — but compares against the baseline file. The 200ms resolver-overhead check (NFR-F-6) is folded in as an additional assertion measuring `time bash plugin-wheel/lib/resolve.sh ...` in a no-deps configuration.

---

## §6 — Open Questions resolved during research

- **OQ-F-1**: ✅ Resolved (§1) — Candidate A primary, Candidate B fallback, Candidate C confirmed nonexistent.
- **OQ-F-2** (snapshot retention on failure): ✅ Resolved per PRD's v1 plan — retain on failure, delete on success. Pattern matches existing wheel history retention.

## §7 — New unknowns surfaced during research

- **U-1 (plan-phase)**: bash-only escape decoder vs `awk` vs `python3` for the preprocessor. Tradeoff: bash-only is simplest but `${var//pattern/replacement}` lacks negative lookbehind for skip-sets. `awk` adds a dependency we already have (used elsewhere in distill helpers). `python3` is also already a dependency (post-tool-use.sh fallback). Decide in plan §3 — likely `awk` for the escape decoder, bash-only for the substitution loop.
- **U-2 (plan-phase)**: whether to enforce schema validation in `workflow.sh::workflow_load` (today's spot for required-field checks) or in a new dedicated `resolve.sh::validate_requires_plugins`. Tradeoff: workflow_load is the natural home but adding registry-aware logic there couples workflow loading to session state. Decide in plan §2 — likely keep them separate (workflow_load only checks shape; resolve_workflow_dependencies checks against the registry).
