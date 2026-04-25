# Data Model: Wheel as Runtime

## Entities

### 1. Agent Definition

A markdown file under `plugin-wheel/agents/<name>.md` describing a specialized agent.

**Location (canonical)**: `plugin-wheel/agents/<name>.md`
**Location (pre-migration)**: scattered under `plugin-kiln/agents/`, `plugin-shelf/agents/`, etc. — relocated in FR-A2 with symlinks at old paths.

**Frontmatter** (consumed by resolver):
```yaml
---
name: <short-name>               # must match filename minus .md
subagent_type: <type>            # wheel-runner | general-purpose | ...
tools:                           # optional; if absent, inherits registry default
  - Read
  - Edit
  - Bash
model_default: haiku|sonnet|opus # optional; resolver passes through as model_default
---
```

**Body**: The agent's system prompt (plain markdown).

### 2. Agent Registry

**File**: `plugin-wheel/scripts/agents/registry.json`
**Schema**:
```json
{
  "version": 1,
  "agents": {
    "<short-name>": {
      "path": "plugin-wheel/agents/<name>.md",
      "subagent_type": "<type>",
      "tools": ["..."],
      "model_default": "haiku|sonnet|opus|null"
    }
  }
}
```

Generated/maintained alongside agent migrations. A unit test verifies every file under `plugin-wheel/agents/*.md` has a corresponding registry entry (and vice versa) — prevents drift.

### 3. Resolver Output (JSON spec)

Shape emitted by `plugin-wheel/scripts/agents/resolve.sh` on stdout:

```json
{
  "subagent_type": "<type>",
  "system_prompt_path": "<abs-or-WORKFLOW_PLUGIN_DIR-rooted>",
  "tools": ["..."],
  "source": "short-name | path | unknown",
  "canonical_path": "<plugin-wheel/agents/... or raw input>",
  "model_default": "haiku|sonnet|opus|null"
}
```

Consumed by: wheel dispatch, kiln skills invoking the resolver, the reference-walker test (SC-008).

### 4. Workflow JSON Agent Step (extended)

Extended with two optional additive fields:

```json
{
  "type": "agent",
  "name": "step-name",
  "agent_path": "<path-or-name>",     // NEW — optional (Theme A)
  "subagent_type": "...",              // existing
  "model": "haiku|sonnet|opus|<id>",   // NEW — optional (Theme B)
  "prompt": "...",
  "run_in_background": false
}
```

### 5. Consumer-Install Simulation

A test environment configuration used by FR-D2's smoke test:

- **Source-repo plugin dirs** (`plugin-shelf/`, `plugin-kiln/`, `plugin-trim/`, `plugin-clay/`, `plugin-wheel/`) — MOVED ASIDE (e.g. to `/tmp/source-repo-backup/`) or the test runs from a cloned subset.
- **Plugin install path** (where scripts ARE available): `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/`
- **`WORKFLOW_PLUGIN_DIR`** (set by wheel dispatch): absolute path to the install directory — NOT the source-repo path.
- **Success**: bg sub-agent resolves its scripts via `${WORKFLOW_PLUGIN_DIR}`, log line written, counter incremented.
- **Failure fingerprint**: the string `"WORKFLOW_PLUGIN_DIR was unset"` appearing in any log line written during the simulation.

### 6. Batched Step Wrapper

**File pattern**: `plugin-<name>/scripts/step-<stepname>.sh`
**Shape**: See `contracts/interfaces.md` §6.

**Outputs**:
- Per-action log lines to stderr/stdout with prefix `wheel:<stepname>: action=<name> | start|ok`.
- Final JSON to stdout: `{"step": "<name>", "status": "ok", "actions": ["..."]}`.
- Exit code: 0 on success, non-zero (from `set -e`) on first action failure.

### 7. Batching Audit Document

**File**: `.kiln/research/wheel-step-batching-audit-<YYYY-MM-DD>.md`

**Structure**:
- Table enumerating every `"type": "agent"` step across the five plugin workflow directories, with columns:
  - Step name
  - Workflow JSON path
  - # of internal bash calls (approximate)
  - Deterministic post-kickoff? (yes/no/partial)
  - Recommended action: batch / leave / split
- Before/after measurement block for the chosen prototype step (raw wall-clock numbers, ≥3 samples each).
- Environment block (OS, Bash version, harness version).
- Negative-result allowance: if no speedup, the audit documents the finding and narrows FR-E scope accordingly.

### 8. Regression Fingerprint String

A canonical string used as a silent-failure tripwire:

- Value: `"WORKFLOW_PLUGIN_DIR was unset"`
- Written by: nothing, ever, post-PRD (its absence is the assertion).
- Asserted by: `git grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/report-issue-bg-*.md` returning zero matches for lines dated after the PRD ships (SC-007).

## Relationships

- **Agent Definition** → **Agent Registry**: 1-to-1, filename determines short name; drift enforced by registry-completeness test.
- **Agent Registry** + **input (path|name|unknown)** → **Resolver Output**: resolver is a pure function over (registry, input, env).
- **Workflow JSON Agent Step** → **Resolver Output**: dispatcher consumes `agent_path:` → resolver output → Agent tool call spec.
- **Workflow JSON Agent Step** → **concrete model id**: dispatcher consumes `model:` → `resolve-model.sh` → id attached to Agent tool call.
- **Consumer-Install Simulation** → **FR-D2 Smoke Test**: simulation is the environment; smoke test is the assertion runner.
