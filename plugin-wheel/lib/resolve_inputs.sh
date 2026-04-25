#!/usr/bin/env bash
# resolve_inputs.sh — wheel-step inputs resolver + output-schema extractor.
#
# Implements Themes G2 + G3 of
#   specs/wheel-step-input-output-schema/spec.md
# under the contract
#   specs/wheel-step-input-output-schema/contracts/interfaces.md §1, §2, §3, §7.
#
# Public entrypoints:
#   _parse_jsonpath_expr <expr>                                       (FR-G2-5; contract §1)
#   resolve_inputs       <step_json> <state_json> <workflow_json> <registry_json>   (FR-G3-1, FR-G3-4; contract §2)
#   extract_output_field <upstream_output> <output_schema_json> <field_name>         (FR-G1-2; contract §3)
#
# Single source of truth for the JSONPath subset grammar (I-PJ-3):
# `workflow.sh::workflow_validate_inputs_outputs` MUST source this file
# and call `_parse_jsonpath_expr` for shape-only validation. The resolver
# and the workflow-load validator share the SAME grammar function so
# error strings stay byte-identical (cross-plugin-resolver dual-gate
# pattern, lifted into this PRD per plan.md §3.A).
#
# Re-source guard: aligns with registry.sh / resolve.sh / preprocess.sh so
# engine.sh (and workflow.sh) can unconditionally `source` this file.

if [[ -n "${WHEEL_RESOLVE_INPUTS_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
WHEEL_RESOLVE_INPUTS_SH_LOADED=1

# -----------------------------------------------------------------------------
# Allowlist — NFR-G-7 / OQ-G-1 Candidate A (default-deny, explicit opt-in).
#
# Spec-phase decision (specs/wheel-step-input-output-schema/spec.md §OQ-G-1):
# v1 ships with the small set below. Adding a key requires editing this file
# with a security-justification comment and going through code review with
# the `security` label per project policy (I-AL-3).
#
# JSON-file form `<file>:<jq-path>` is NOT allowlisted — the literal jq path
# in the workflow JSON is itself the auditable artifact (per spec §OQ-G-1).
# -----------------------------------------------------------------------------
declare -gA CONFIG_KEY_ALLOWLIST=(
  [".shelf-config:shelf_full_sync_counter"]="non-secret integer counter (full-sync cadence state)"
  [".shelf-config:shelf_full_sync_threshold"]="non-secret integer threshold (full-sync cadence config)"
  [".shelf-config:slug"]="non-secret project slug (used in Obsidian path computation)"
  [".shelf-config:base_path"]="non-secret filesystem path (Obsidian vault base)"
  [".shelf-config:obsidian_vault_path"]="non-secret filesystem path (full vault location)"
)

# -----------------------------------------------------------------------------
# _parse_jsonpath_expr — FR-G2-1..FR-G2-5 / contract §1.
#
# Pure function. Sets _PARSED_KIND / _PARSED_ARG1 / _PARSED_ARG2 globals on
# success; sets _PARSED_ERROR on failure. Silent on stdout AND stderr —
# callers decide whether to print the error.
#
# Grammar table (interfaces.md §1):
#   ^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$   → dollar_steps  (step-id, field)
#   ^\$config\(([^:)]+):([^)]+)\)$                            → dollar_config (file, key)
#   ^\$plugin\(([A-Za-z0-9_-]+)\)$                            → dollar_plugin (plugin-name, "")
#   ^\$step\(([A-Za-z0-9_-]+)\)$                              → dollar_step   (step-id, "")
#
# Args:
#   $1  expr   — JSONPath subset expression string
#
# Globals set on success (exit 0):
#   _PARSED_KIND, _PARSED_ARG1, _PARSED_ARG2
# Globals set on failure (exit 1):
#   _PARSED_ERROR
# -----------------------------------------------------------------------------
_parse_jsonpath_expr() {
  local expr="$1"

  # Reset all globals — idempotency invariant I-PJ-2.
  _PARSED_KIND=""
  _PARSED_ARG1=""
  _PARSED_ARG2=""
  _PARSED_ERROR=""

  # Pattern 1: $.steps.<step-id>.output.<field>
  if [[ "$expr" =~ ^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$ ]]; then
    _PARSED_KIND="dollar_steps"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2="${BASH_REMATCH[2]}"
    return 0
  fi

  # Pattern 2: $config(<file>:<key>)
  if [[ "$expr" =~ ^\$config\(([^:\)]+):([^\)]+)\)$ ]]; then
    _PARSED_KIND="dollar_config"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2="${BASH_REMATCH[2]}"
    return 0
  fi

  # Pattern 3: $plugin(<name>)
  if [[ "$expr" =~ ^\$plugin\(([A-Za-z0-9_-]+)\)$ ]]; then
    _PARSED_KIND="dollar_plugin"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2=""
    return 0
  fi

  # Pattern 4: $step(<step-id>)
  if [[ "$expr" =~ ^\$step\(([A-Za-z0-9_-]+)\)$ ]]; then
    _PARSED_KIND="dollar_step"
    _PARSED_ARG1="${BASH_REMATCH[1]}"
    _PARSED_ARG2=""
    return 0
  fi

  # Anything else → loud failure (FR-G2-5).
  _PARSED_ERROR="unsupported expression"
  return 1
}

# -----------------------------------------------------------------------------
# extract_output_field — FR-G1-2 / contract §3.
#
# Args:
#   $1  upstream_output       — string, raw output of the upstream step
#   $2  output_schema_json    — single-line JSON, the upstream step's output_schema field
#   $3  field_name            — string, the field to extract
#
# Stdout (on exit 0): the extracted value as a string.
# Stderr (on exit 1): contract §3 / FR-G2 documented error string.
#
# Extractor types (interfaces.md §3):
#   "$.foo.bar"                       → JSON path; jq -r '.foo.bar'
#   {"extract": "regex:<pattern>"}    → text; first match wins; capture group 1 if present
#   {"extract": "jq:<expr>"}          → JSON; jq -r '<expr>'
# -----------------------------------------------------------------------------
extract_output_field() {
  local upstream_output="$1"
  local output_schema_json="$2"
  local field_name="$3"

  # Pull the field's directive from the output_schema. jq returns "null" on
  # missing — we treat that as "field not in schema" (defense-in-depth; the
  # workflow_validate_inputs_outputs caller already catches this statically,
  # but runtime defends in case of stale state files).
  local directive
  directive=$(printf '%s' "$output_schema_json" | jq -c --arg f "$field_name" '.[$f] // null')

  if [[ "$directive" == "null" ]]; then
    echo "extract_output_field: field '${field_name}' not in upstream output_schema" >&2
    return 1
  fi

  # Determine the directive shape:
  #   - String starting with `$.`        → direct JSON path
  #   - Object with "extract" key        → regex: or jq: directive
  local directive_type
  directive_type=$(printf '%s' "$directive" | jq -r 'type')

  case "$directive_type" in
    string)
      # Direct JSON path. Strip the leading/trailing quotes via jq -r.
      local jq_path
      jq_path=$(printf '%s' "$directive" | jq -r '.')
      if [[ "$jq_path" != \$.* ]]; then
        echo "extract_output_field: field '${field_name}' has malformed JSON-path directive: '${jq_path}' (must start with \$.)" >&2
        return 1
      fi
      # Translate JSONPath `$.foo.bar` → jq `.foo.bar` (strip leading `$`).
      # JSONPath is a stable subset chosen for spec-author readability; jq is
      # the runtime engine. Same shape used by extract_output_field's
      # internal jq-path branch + resolve_inputs $config(file:.jq.path).
      local jq_expr=".${jq_path#\$.}"
      # Run jq against the upstream output.
      local extracted
      if ! extracted=$(printf '%s' "$upstream_output" | jq -r "$jq_expr" 2>&1); then
        echo "extract_output_field: jq '${jq_expr}' failed against step output: ${extracted}" >&2
        return 1
      fi
      if [[ "$extracted" == "null" ]]; then
        echo "extract_output_field: field '${field_name}' resolved to null in upstream output" >&2
        return 1
      fi
      printf '%s' "$extracted"
      return 0
      ;;
    object)
      local extract_directive
      extract_directive=$(printf '%s' "$directive" | jq -r '.extract // empty')
      if [[ -z "$extract_directive" ]]; then
        echo "extract_output_field: field '${field_name}' object directive missing 'extract' key" >&2
        return 1
      fi

      if [[ "$extract_directive" == regex:* ]]; then
        local pattern="${extract_directive#regex:}"
        # First match wins (I-EX-1 / contract §3 table). If the pattern has
        # a capture group, return capture #1; otherwise the whole match.
        # We use python3 (already a wheel runtime dep) for reliable PCRE-ish
        # behavior across BSD/GNU grep variants.
        local extracted
        extracted=$(PATTERN="$pattern" UPSTREAM="$upstream_output" python3 -c '
import os, re, sys
pat = os.environ["PATTERN"]
text = os.environ["UPSTREAM"]
try:
    rx = re.compile(pat, re.MULTILINE)
except re.error as e:
    sys.stderr.write(f"regex compile error: {e}\n")
    sys.exit(1)
m = rx.search(text)
if not m:
    sys.exit(2)
if m.groups():
    sys.stdout.write(m.group(1))
else:
    sys.stdout.write(m.group(0))
' 2>&1)
        local rc=$?
        if [[ $rc -eq 2 ]]; then
          echo "extract_output_field: regex '${pattern}' did not match step output for field '${field_name}'" >&2
          return 1
        fi
        if [[ $rc -ne 0 ]]; then
          echo "extract_output_field: regex extractor failed for field '${field_name}': ${extracted}" >&2
          return 1
        fi
        printf '%s' "$extracted"
        return 0
      elif [[ "$extract_directive" == jq:* ]]; then
        local jq_expr="${extract_directive#jq:}"
        local extracted
        if ! extracted=$(printf '%s' "$upstream_output" | jq -r "$jq_expr" 2>&1); then
          echo "extract_output_field: jq '${jq_expr}' failed for field '${field_name}': ${extracted}" >&2
          return 1
        fi
        if [[ "$extracted" == "null" ]]; then
          echo "extract_output_field: jq extractor resolved to null for field '${field_name}'" >&2
          return 1
        fi
        printf '%s' "$extracted"
        return 0
      else
        echo "extract_output_field: field '${field_name}' has malformed extract directive: '${extract_directive}' (expected regex:<pattern> or jq:<expr>)" >&2
        return 1
      fi
      ;;
    *)
      echo "extract_output_field: field '${field_name}' has unsupported directive type '${directive_type}'" >&2
      return 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Internal — read upstream step's output content (FR-G2-1 / sub-workflow alias).
#
# The state file records `steps[idx].output` as either a literal value OR a
# file path the agent wrote to. For `type: workflow` (sub-workflow) steps,
# the wheel-step itself often has no `output:` field — the sub-workflow
# writes its result under its OWN name (e.g. `shelf:shelf-write-issue-note`
# writes `.wheel/outputs/shelf-write-issue-note-result.json`). The resolver
# handles this aliasing transparently:
#
#   1. If state.steps[idx].output is a non-empty file path that exists, read it.
#   2. Else, if step.type == "workflow", derive the conventional sub-workflow
#      result path from step.workflow (`shelf:shelf-write-issue-note` →
#      `.wheel/outputs/shelf-write-issue-note-result.json`) and read that.
#   3. Else, treat state.steps[idx].output as a literal value.
#   4. On all-misses, return non-zero.
#
# Args:
#   $1  step_idx          — integer, index in state.steps[]
#   $2  state_json        — single-line JSON, parent state
#   $3  upstream_step_json — single-line JSON, the upstream step from workflow.steps[]
#
# Stdout: file contents OR literal value
# Exit:   0 on success, 1 if no readable upstream output
# -----------------------------------------------------------------------------
_read_upstream_output() {
  local step_idx="$1"
  local state_json="$2"
  local upstream_step_json="$3"

  local recorded
  recorded=$(printf '%s' "$state_json" | jq -r --argjson idx "$step_idx" '.steps[$idx].output // empty')

  if [[ -n "$recorded" && -f "$recorded" ]]; then
    cat "$recorded"
    return 0
  fi

  # Sub-workflow filename aliasing per researcher-baseline §Job 2.
  local upstream_type
  upstream_type=$(printf '%s' "$upstream_step_json" | jq -r '.type // ""')
  if [[ "$upstream_type" == "workflow" ]]; then
    local sub_wf
    sub_wf=$(printf '%s' "$upstream_step_json" | jq -r '.workflow // ""')
    # Strip plugin prefix: `shelf:shelf-write-issue-note` → `shelf-write-issue-note`.
    local sub_wf_name="${sub_wf##*:}"
    local conv_path=".wheel/outputs/${sub_wf_name}-result.json"
    if [[ -f "$conv_path" ]]; then
      cat "$conv_path"
      return 0
    fi
  fi

  # Last-resort fallback: treat recorded value as a literal (in-memory string).
  if [[ -n "$recorded" ]]; then
    printf '%s' "$recorded"
    return 0
  fi

  return 1
}

# -----------------------------------------------------------------------------
# resolve_inputs — FR-G3-1 / FR-G3-4 / contract §2.
#
# Iterates `step.inputs`, dispatches each via the JSONPath subset grammar,
# resolves each expression, returns a single-line JSON object with the
# resolved map.
#
# Implementation note (NFR-G-5 perf): the body delegates to a SINGLE
# python3 invocation that does parsing + resolution + extraction +
# allowlist gating. The earlier bash-and-jq implementation measured
# ~190ms median for 5 inputs (jq cold-start ≈ 10-15ms × ~9 invocations
# per dollar_steps input). The python3 path is dominated by the ~25ms
# python3 cold-start with sub-ms resolution work, leaving headroom in
# the 100ms gate. The bash `_parse_jsonpath_expr` and bash
# `extract_output_field` helpers above are STILL used by:
#   - workflow.sh::workflow_validate_inputs_outputs (load-time validation —
#     no perf gate, low FR count, jq is fine);
#   - external test fixtures (resolve-inputs-grammar/, output-schema-extract-*).
# So the grammar lives in two homes (python3 + bash) — both must move
# together. Mutation tripwires in both substrates guard against drift
# (NFR-G-2).
#
# Args:
#   $1  step_json       — single-line JSON, the agent step
#   $2  state_json      — single-line JSON, parent workflow state
#   $3  workflow_json   — single-line JSON, the templated workflow
#   $4  registry_json   — single-line JSON, output of build_session_registry
#
# Stdout (on exit 0): single-line JSON `{ "<VAR>": "<resolved>", ... }` or `{}`.
# Stderr (on exit 1): ONE line matching one of the contract §2 error shapes.
# -----------------------------------------------------------------------------
resolve_inputs() {
  local step_json="$1"
  local state_json="$2"
  local workflow_json="$3"
  local registry_json="$4"

  # No-op bash fast path (I-RI-5 / NFR-G-5 ≤5ms-class) — do not pay
  # python3 startup if step.inputs is absent or empty. Cheap bash regex
  # check instead of jq.
  if [[ "$step_json" != *'"inputs"'* ]] || [[ "$step_json" == *'"inputs":{}'* ]]; then
    echo '{}'
    return 0
  fi

  # Build allowlist as newline-delimited keys (known-safe charset; no JSON
  # escaping needed). The earlier per-key python3 invocation cost ~25ms each
  # × 5 keys, blowing the NFR-G-5 budget by itself.
  local allowlist_keys=""
  local _key
  for _key in "${!CONFIG_KEY_ALLOWLIST[@]}"; do
    allowlist_keys="${allowlist_keys}${_key}"$'\n'
  done

  # Single python3 invocation does everything. Pass big JSON blobs via env.
  local result_or_err
  result_or_err=$(
    STEP_JSON="$step_json" \
    STATE_JSON="$state_json" \
    WORKFLOW_JSON="$workflow_json" \
    REGISTRY_JSON="$registry_json" \
    ALLOWLIST_KEYS="$allowlist_keys" \
    python3 - <<'PY' 2>&1
import json, os, re, sys

step = json.loads(os.environ["STEP_JSON"])
state = json.loads(os.environ["STATE_JSON"])
workflow = json.loads(os.environ["WORKFLOW_JSON"])
registry = json.loads(os.environ.get("REGISTRY_JSON") or "{}")
allowlist = set(
    line for line in os.environ.get("ALLOWLIST_KEYS", "").split("\n") if line
)

wf_name = workflow.get("name", "unnamed")
step_id = step.get("id", "?")
inputs = step.get("inputs", {}) or {}

wf_steps = workflow.get("steps", [])
step_by_id = {s.get("id", ""): s for s in wf_steps}
state_steps = state.get("steps", [])

RE_DOLLAR_STEPS  = re.compile(r"^\$\.steps\.([A-Za-z0-9_-]+)\.output\.([A-Za-z0-9_-]+)$")
RE_DOLLAR_CONFIG = re.compile(r"^\$config\(([^:)]+):([^)]+)\)$")
RE_DOLLAR_PLUGIN = re.compile(r"^\$plugin\(([A-Za-z0-9_-]+)\)$")
RE_DOLLAR_STEP   = re.compile(r"^\$step\(([A-Za-z0-9_-]+)\)$")

def fail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

def err_unsupported(var, expr):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' uses unsupported expression: "
        f"'{expr}'. Supported: $.steps.<id>.output.<field>, $config(<file>:<key>), "
        f"$plugin(<name>), $step(<id>)."
    )

def err_missing_upstream(var, ups):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' references missing upstream "
        f"output: step '{ups}' has not run or has no output_schema declaration."
    )

def err_field_not_in_schema(var, field, ups):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' references field '{field}' "
        f"of step '{ups}' but '{field}' is not in that step's output_schema."
    )

def err_regex_no_match(var, ups):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' resolves regex extractor "
        f"against step '{ups}' output but pattern did not match."
    )

def err_allowlist(var, fil, key):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' resolves $config({fil}:{key}) "
        f"but '{key}' is not in the safe-key allowlist for {fil}. Add it to "
        f"plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST after security review, "
        f"or use $step()/$.steps.* for non-config values."
    )

def err_cfg_file(var, fil, key):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' resolves $config({fil}:{key}) "
        f"but config file '{fil}' not found."
    )

def err_cfg_key(var, fil, key):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' resolves $config({fil}:{key}) "
        f"but key '{key}' not found in '{fil}'."
    )

def err_plugin(var, name):
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' resolves $plugin({name}) "
        f"but '{name}' is not in this session's registry."
    )

def read_upstream_output(ups_id):
    """FR-G2-1 + sub-workflow filename aliasing per researcher-baseline §Job 2."""
    ups_step = step_by_id.get(ups_id)
    if ups_step is None:
        return None
    idx = None
    for i, s in enumerate(state_steps):
        if s.get("id") == ups_id:
            idx = i
            break
    if idx is None:
        return None
    rec = state_steps[idx].get("output") or ""
    if rec and os.path.isfile(rec):
        with open(rec, encoding="utf-8", errors="replace") as f:
            return f.read()
    if ups_step.get("type") == "workflow":
        sub_wf = ups_step.get("workflow", "")
        sub_wf_name = sub_wf.split(":")[-1]
        conv = f".wheel/outputs/{sub_wf_name}-result.json"
        if os.path.isfile(conv):
            with open(conv, encoding="utf-8", errors="replace") as f:
                return f.read()
    if rec:
        return rec
    return None

def extract_field(upstream_output, output_schema, field, var, ups_id):
    if not output_schema or field not in output_schema:
        err_field_not_in_schema(var, field, ups_id)
    directive = output_schema[field]
    if isinstance(directive, str):
        if not directive.startswith("$."):
            fail(
                f"Workflow '{wf_name}' step '{step_id}' input '{var}' references field '{field}' "
                f"of step '{ups_id}' but its output_schema directive is malformed: '{directive}'."
            )
        try:
            payload = json.loads(upstream_output)
        except json.JSONDecodeError:
            fail(
                f"Workflow '{wf_name}' step '{step_id}' input '{var}' could not parse "
                f"step '{ups_id}' output as JSON for direct path extraction."
            )
        path_parts = directive[2:].split(".") if directive != "$." else []
        cur = payload
        for part in path_parts:
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                fail(
                    f"Workflow '{wf_name}' step '{step_id}' input '{var}' resolves direct path "
                    f"'{directive}' against step '{ups_id}' output but path did not match."
                )
        if cur is None:
            fail(
                f"Workflow '{wf_name}' step '{step_id}' input '{var}' direct path '{directive}' "
                f"resolved to null in step '{ups_id}' output."
            )
        return str(cur)
    if isinstance(directive, dict):
        ext = directive.get("extract", "")
        if ext.startswith("regex:"):
            pat = ext[len("regex:"):]
            m = re.search(pat, upstream_output, re.MULTILINE)
            if not m:
                err_regex_no_match(var, ups_id)
            return m.group(1) if m.groups() else m.group(0)
        if ext.startswith("jq:"):
            expr = ext[len("jq:"):]
            if not re.match(r"^\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$", expr):
                fail(
                    f"Workflow '{wf_name}' step '{step_id}' input '{var}' uses jq extractor "
                    f"'{expr}' which is outside the v1 dotted-path subset; full jq expressions "
                    f"are not supported in resolve_inputs (NFR-G-5 perf budget). Use a JSON-path "
                    f"directive ('$.foo.bar') instead."
                )
            try:
                payload = json.loads(upstream_output)
            except json.JSONDecodeError:
                fail(
                    f"Workflow '{wf_name}' step '{step_id}' input '{var}' could not parse "
                    f"step '{ups_id}' output as JSON for jq-form extraction."
                )
            cur = payload
            for part in expr.lstrip(".").split("."):
                if isinstance(cur, dict) and part in cur:
                    cur = cur[part]
                else:
                    fail(
                        f"Workflow '{wf_name}' step '{step_id}' input '{var}' jq path '{expr}' "
                        f"did not match step '{ups_id}' output."
                    )
            if cur is None:
                fail(
                    f"Workflow '{wf_name}' step '{step_id}' input '{var}' jq extractor "
                    f"resolved to null in step '{ups_id}' output."
                )
            return str(cur)
        fail(
            f"Workflow '{wf_name}' step '{step_id}' input '{var}' has malformed extract "
            f"directive: '{ext}' (expected regex:<pattern> or jq:<expr>)."
        )
    fail(
        f"Workflow '{wf_name}' step '{step_id}' input '{var}' has unsupported directive type."
    )

def read_config_flat(file_path, key):
    try:
        with open(file_path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == key:
                    return v.strip()
    except OSError:
        return None
    return None

def read_config_json_jq(file_path, jq_path):
    try:
        with open(file_path, encoding="utf-8") as f:
            payload = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None
    if not jq_path.startswith("."):
        return None
    parts = jq_path.lstrip(".").split(".") if jq_path != "." else []
    cur = payload
    for part in parts:
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    if cur is None:
        return None
    return str(cur)

resolved = {}
plugins = registry.get("plugins", {}) if isinstance(registry, dict) else {}

for var, expr in inputs.items():
    if not isinstance(expr, str):
        err_unsupported(var, str(expr))
    m = RE_DOLLAR_STEPS.match(expr)
    if m:
        ups_id, field = m.group(1), m.group(2)
        ups_step = step_by_id.get(ups_id)
        if ups_step is None:
            err_missing_upstream(var, ups_id)
        ups_state = next((s for s in state_steps if s.get("id") == ups_id), None)
        if not ups_state or ups_state.get("status") != "done":
            err_missing_upstream(var, ups_id)
        ups_schema = ups_step.get("output_schema")
        if not ups_schema:
            err_missing_upstream(var, ups_id)
        upstream_output = read_upstream_output(ups_id)
        if upstream_output is None:
            err_missing_upstream(var, ups_id)
        resolved[var] = extract_field(upstream_output, ups_schema, field, var, ups_id)
        continue
    m = RE_DOLLAR_CONFIG.match(expr)
    if m:
        cfg_file, cfg_key = m.group(1), m.group(2)
        is_jq_path = cfg_key.startswith(".")
        if not is_jq_path:
            allow_lookup = f"{cfg_file}:{cfg_key}"
            if allow_lookup not in allowlist:
                err_allowlist(var, cfg_file, cfg_key)
        if not os.path.isfile(cfg_file):
            err_cfg_file(var, cfg_file, cfg_key)
        if is_jq_path:
            val = read_config_json_jq(cfg_file, cfg_key)
        else:
            val = read_config_flat(cfg_file, cfg_key)
        if val is None:
            err_cfg_key(var, cfg_file, cfg_key)
        resolved[var] = val
        continue
    m = RE_DOLLAR_PLUGIN.match(expr)
    if m:
        name = m.group(1)
        path = plugins.get(name) if isinstance(plugins, dict) else None
        if not path:
            err_plugin(var, name)
        resolved[var] = path
        continue
    m = RE_DOLLAR_STEP.match(expr)
    if m:
        ups_id = m.group(1)
        ups_step = step_by_id.get(ups_id)
        ups_state = next((s for s in state_steps if s.get("id") == ups_id), None)
        rec = (ups_state or {}).get("output") or ""
        if not rec and ups_step and ups_step.get("type") == "workflow":
            sub_wf = ups_step.get("workflow", "")
            rec = f".wheel/outputs/{sub_wf.split(':')[-1]}-result.json"
        if not rec:
            err_missing_upstream(var, ups_id)
        resolved[var] = rec
        continue
    err_unsupported(var, expr)

sys.stdout.write(json.dumps(resolved, separators=(",", ":")))
PY
  )
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s\n' "$result_or_err" >&2
    return 1
  fi
  printf '%s' "$result_or_err"
  return 0
}
