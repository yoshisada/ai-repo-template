#!/usr/bin/env bash
# resolve.sh — Pre-flight workflow dependency resolver (Theme F3)
# FR-F3-1..FR-F3-3 of specs/cross-plugin-resolver-and-preflight-registry/
#
# Public entrypoint: resolve_workflow_dependencies
#   Validates a workflow's requires_plugins declarations against a session
#   registry. Pure validation — no state mutation, no agent dispatch, no
#   side effects (I-V-1).
#
# Contract: specs/cross-plugin-resolver-and-preflight-registry/contracts/interfaces.md §2

if [[ -n "${WHEEL_RESOLVE_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
WHEEL_RESOLVE_SH_LOADED=1

# resolve_workflow_dependencies
# Args:
#   $1  workflow_json   — single-line JSON, output of workflow_load
#   $2  registry_json   — single-line JSON envelope from build_session_registry
# Stdout: empty on success.
# Stderr: documented FR-F3-3 error text on failure (one line).
# Exit: 0 on all-deps-satisfied, 1 on any failure.
#
# I-V-2: Error text matches FR-F3-3 EXACTLY (NFR-F-2 silent-failure tripwire
#        depends on these strings).
# I-V-3: Workflows without requires_plugins exit 0 silently (NFR-F-5
#        byte-identical backward-compat).
# I-V-4: Token-discovery scan walks every agent step's instruction; any
#        ${WHEEL_PLUGIN_<name>} reference whose name is not in
#        requires_plugins is an "unknown plugin token" error.
#        ${WORKFLOW_PLUGIN_DIR} is exempt (auto-resolved by preprocessor).
# I-V-5: Schema validation: each requires_plugins entry MUST be a non-empty
#        string matching [a-zA-Z0-9_-]+; duplicates fail.
resolve_workflow_dependencies() {
  local workflow_json="$1"
  local registry_json="$2"

  if [[ -z "$workflow_json" ]]; then
    echo "resolve: empty workflow_json argument" >&2
    return 1
  fi
  if [[ -z "$registry_json" ]]; then
    echo "resolve: empty registry_json argument" >&2
    return 1
  fi

  local name
  name=$(printf '%s\n' "$workflow_json" | jq -r '.name // "<unknown>"')

  # --- Schema check (I-V-5) ---
  # Get the requires_plugins array (or empty array if absent).
  local req_field
  req_field=$(printf '%s\n' "$workflow_json" | jq -c '.requires_plugins // []')

  # Must be an array.
  local req_type
  req_type=$(printf '%s\n' "$req_field" | jq -r 'type')
  if [[ "$req_type" != "array" ]]; then
    echo "Workflow '${name}' has malformed requires_plugins entry: top-level must be a JSON array, got ${req_type}." >&2
    return 1
  fi

  # Validate each entry: non-empty string matching [a-zA-Z0-9_-]+, no dupes.
  local entries_count
  entries_count=$(printf '%s\n' "$req_field" | jq 'length')

  local i entry entry_type
  declare -a req_names=()
  for ((i = 0; i < entries_count; i++)); do
    entry_type=$(printf '%s\n' "$req_field" | jq -r --argjson i "$i" '.[$i] | type')
    if [[ "$entry_type" != "string" ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: non-string at index ${i}." >&2
      return 1
    fi
    entry=$(printf '%s\n' "$req_field" | jq -r --argjson i "$i" '.[$i]')
    if [[ -z "$entry" ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: empty string at index ${i}." >&2
      return 1
    fi
    if ! [[ "$entry" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Workflow '${name}' has malformed requires_plugins entry: invalid name '${entry}' at index ${i} (must match [a-zA-Z0-9_-]+)." >&2
      return 1
    fi
    # Duplicate check.
    local existing
    for existing in "${req_names[@]+"${req_names[@]}"}"; do
      if [[ "$existing" == "$entry" ]]; then
        echo "Workflow '${name}' has malformed requires_plugins entry: duplicate name '${entry}'." >&2
        return 1
      fi
    done
    req_names+=("$entry")
  done

  # --- Registry check (FR-F3-2) ---
  # For each declared plugin, verify it's in the registry.plugins.
  local declared
  for declared in "${req_names[@]+"${req_names[@]}"}"; do
    if ! printf '%s\n' "$registry_json" | jq -e --arg k "$declared" '.plugins | has($k)' >/dev/null; then
      echo "Workflow '${name}' requires plugin '${declared}', but '${declared}' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir." >&2
      return 1
    fi
  done

  # --- Token-discovery scan (I-V-4) ---
  # Walk every agent step's instruction text for ${WHEEL_PLUGIN_<name>}
  # references. Any name not in req_names is an unknown-token error.
  # Skip ${WORKFLOW_PLUGIN_DIR} (auto-resolved by preprocessor).
  local instructions
  instructions=$(printf '%s\n' "$workflow_json" \
    | jq -r '.steps[] | select(.type=="agent") | .instruction // empty')

  if [[ -n "$instructions" ]]; then
    # Extract referenced plugin names. Pattern matches ${WHEEL_PLUGIN_<name>}
    # excluding the escaped form $${WHEEL_PLUGIN_<name>}.
    # We use grep -oE to pull the matches, then awk to strip the brackets.
    local -A referenced=()
    local line ref token_name

    # Strip escaped $${...} occurrences first so they don't match. We use
    # awk for portability across macOS BSD sed and GNU sed (BSD sed mangles
    # the brace-quantifier escape syntax in $${...} patterns).
    local stripped
    stripped=$(printf '%s\n' "$instructions" | awk '{
      out = ""
      while (length($0) > 0) {
        idx = index($0, "$${")
        if (idx == 0) { out = out $0; break }
        out = out substr($0, 1, idx - 1)
        rest = substr($0, idx + 3)
        cidx = index(rest, "}")
        if (cidx == 0) { out = out "$${"; $0 = rest; continue }
        $0 = substr(rest, cidx + 1)
      }
      print out
    }')

    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      token_name="${ref#\$\{WHEEL_PLUGIN_}"
      token_name="${token_name%\}}"
      referenced["$token_name"]=1
    done < <(printf '%s\n' "$stripped" | grep -oE '\$\{WHEEL_PLUGIN_[a-zA-Z0-9_-]+\}' || true)

    # Cross-check: any referenced name not in req_names is an error.
    local rname
    for rname in "${!referenced[@]}"; do
      local found=0
      local declared_name
      for declared_name in "${req_names[@]+"${req_names[@]}"}"; do
        if [[ "$declared_name" == "$rname" ]]; then
          found=1
          break
        fi
      done
      if [[ "$found" -eq 0 ]]; then
        echo "Workflow '${name}' references unknown plugin token '\${WHEEL_PLUGIN_${rname}}'. Add '${rname}' to requires_plugins." >&2
        return 1
      fi
    done

    # Optional: warn (not error) on declared-but-unused (per contract edge-case
    # table). We deliberately use stderr but exit 0; tests that care can grep.
    for declared_name in "${req_names[@]+"${req_names[@]}"}"; do
      if [[ -z "${referenced[$declared_name]:-}" ]]; then
        echo "resolve: warning — workflow '${name}' declares requires_plugins entry '${declared_name}' but never references \${WHEEL_PLUGIN_${declared_name}}." >&2
      fi
    done
  fi

  return 0
}
