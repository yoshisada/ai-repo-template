#!/usr/bin/env bash
# registry.sh — Plugin registry build (Theme F1)
# FR-F1-1..FR-F1-5 of specs/cross-plugin-resolver-and-preflight-registry/
#
# Public entrypoint: build_session_registry
#   Emits a single-line JSON map of {name -> absolute_path} for every plugin
#   currently loaded+enabled in the Claude Code session.
#
# Discovery strategy (research §1.F):
#   Candidate A (PRIMARY): parse $PATH for plugin /bin entries (marketplace
#     cache + --plugin-dir + settings.local.json all surface here because
#     Claude Code prepends each enabled plugin's /bin to PATH at session start).
#   Candidate B (FALLBACK): read ~/.claude/plugins/installed_plugins.json,
#     cross-check against settings.json::enabledPlugins. Triggered when A
#     returns empty OR when WHEEL_REGISTRY_FALLBACK=1.
#
# Contract: specs/cross-plugin-resolver-and-preflight-registry/contracts/interfaces.md §1
# Self-bootstrap: per I-R-3, wheel itself is appended from BASH_SOURCE when
# PATH parsing happens to miss it.

# Guard against double-source.
if [[ -n "${WHEEL_REGISTRY_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
WHEEL_REGISTRY_SH_LOADED=1

# _internal_path_parse — Candidate A: scan $PATH for plugin /bin entries.
# Output (stdout): JSON object {plugin_name: absolute_path, ...} (single line).
#   Empty `{}` if no plugin /bin entries found.
# Stderr: diagnostic warnings (missing plugin.json, etc.).
# Exit: 0 (always — empty result is a valid signal to fall back).
#
# FR-F1-2: Candidate A primary discovery source.
# FR-F1-4: PATH order = priority order; first occurrence wins for duplicates.
# I-R-2:   Plugin keys are unique even if multiple PATH entries match.
_internal_path_parse() {
  local path_entries
  IFS=':' read -ra path_entries <<<"${PATH:-}"

  # Use a flat key=value record stream then collapse via jq for first-wins
  # semantics (PATH-order priority).
  local -a discovered=()
  local entry plugin_dir plugin_name candidate_manifest

  for entry in "${path_entries[@]}"; do
    [[ -z "$entry" ]] && continue
    # We care about entries shaped like "<...>/bin" — strip the trailing /bin
    # to get the plugin install dir.
    [[ "$entry" != */bin ]] && continue

    plugin_dir="${entry%/bin}"

    # Only treat this as a plugin entry if the directory hosts a
    # .claude-plugin/plugin.json manifest. This is the authoritative shape
    # for both marketplace-cache and --plugin-dir installs.
    candidate_manifest="${plugin_dir}/.claude-plugin/plugin.json"
    if [[ ! -f "$candidate_manifest" ]]; then
      continue
    fi

    # Plugin-name resolution per research §1.B Strategy 2: read
    # plugin.json::name (authoritative). Fall back to directory basename
    # if the field is missing.
    plugin_name=$(jq -r '.name // empty' "$candidate_manifest" 2>/dev/null)
    if [[ -z "$plugin_name" || "$plugin_name" == "null" ]]; then
      plugin_name=$(basename "$plugin_dir")
      echo "registry: warning — ${candidate_manifest} missing .name field, using basename '${plugin_name}'" >&2
    fi

    # Skip plugin dirs that don't actually exist on disk anymore (PATH
    # may be stale).
    if [[ ! -d "$plugin_dir" ]]; then
      echo "registry: warning — PATH entry ${entry} does not exist on disk; skipping" >&2
      continue
    fi

    discovered+=("${plugin_name}=${plugin_dir}")
  done

  # Collapse to first-wins JSON map.
  if (( ${#discovered[@]} == 0 )); then
    printf '%s\n' '{}'
    return 0
  fi

  local map='{}'
  local kv key value
  for kv in "${discovered[@]}"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    # Skip if key already present (PATH-order: first occurrence wins).
    if printf '%s\n' "$map" | jq -e --arg k "$key" 'has($k)' >/dev/null; then
      continue
    fi
    map=$(printf '%s\n' "$map" | jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}')
  done

  printf '%s\n' "$map"
}

# _internal_installed_plugins_fallback — Candidate B: read installed_plugins.json
# and cross-check against enabledPlugins in settings to filter to enabled-only.
# Output (stdout): JSON object {plugin_name: absolute_path, ...} (single line).
# Stderr: diagnostic on read failures.
# Exit: 0 on success (incl. empty), 1 if installed_plugins.json missing or unreadable.
#
# FR-F1-3: Disabled-but-installed plugins MUST NOT appear.
_internal_installed_plugins_fallback() {
  local installed_file="${HOME}/.claude/plugins/installed_plugins.json"
  if [[ ! -f "$installed_file" ]]; then
    echo "registry: ${installed_file} not found; cannot fall back" >&2
    return 1
  fi

  local installed_json
  if ! installed_json=$(jq -c '.' "$installed_file" 2>/dev/null); then
    echo "registry: failed to parse ${installed_file}" >&2
    return 1
  fi

  # Build the union enabled-plugins set from user settings + project local settings.
  # Keys are the "<plugin>@<source>" form.
  local user_settings="${HOME}/.claude/settings.json"
  local project_settings_local=".claude/settings.local.json"
  local project_settings=".claude/settings.json"

  local enabled_keys='[]'
  local f
  for f in "$user_settings" "$project_settings" "$project_settings_local"; do
    [[ ! -f "$f" ]] && continue
    local file_keys
    file_keys=$(jq -c '.enabledPlugins // {} | to_entries | map(select(.value == true) | .key)' "$f" 2>/dev/null) || continue
    enabled_keys=$(jq -c -n --argjson a "$enabled_keys" --argjson b "$file_keys" '$a + $b | unique')
  done

  # Walk installed_plugins.json, keep entries whose "<name>@<source>" key
  # appears in enabled_keys. Plugin-name = segment before "@" in the key.
  # Pick the latest version's installPath (highest version_dir basename).
  local result
  result=$(jq -c --argjson enabled "$enabled_keys" '
    .plugins // {}
    | to_entries
    | map(select(.key as $k | $enabled | index($k)))
    | map({
        name: (.key | split("@")[0]),
        path: (
          .value
          | sort_by(.installPath // "")
          | last
          | .installPath // ""
        )
      })
    | map(select(.path != ""))
    | from_entries
      | with_entries({key: .value.name, value: .value.path})
    ' <<<"$installed_json" 2>/dev/null)

  # The above pipeline has a subtle bug; rebuild more simply.
  result=$(printf '%s\n' "$installed_json" | jq -c --argjson enabled "$enabled_keys" '
    [(.plugins // {}) | to_entries[]
      | select(.key as $k | $enabled | index($k))
      | {name: (.key | split("@")[0]),
         path: ((.value | sort_by(.installPath // "") | last | .installPath) // "")}
      | select(.path != "")
    ] | map({(.name): .path}) | add // {}')

  if [[ -z "$result" || "$result" == "null" ]]; then
    result='{}'
  fi
  printf '%s\n' "$result"
  return 0
}

# build_session_registry — public entrypoint per contract §1.
# Args: NONE.
# Env (consumed): PATH, HOME, WHEEL_REGISTRY_FALLBACK
# Stdout: single-line JSON envelope:
#   {"schema_version":1,"built_at":"<iso>","source":"...","fallback_used":bool,"plugins":{...}}
# Stderr: diagnostics (warnings, fallback notices, errors).
# Exit: 0 on success (including empty plugins map), 1 if both A and B fail.
build_session_registry() {
  local built_at
  built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local plugins_a plugins_b plugins=''
  local source='candidate-a-path-parsing'
  local fallback_used=false

  if [[ "${WHEEL_REGISTRY_FALLBACK:-0}" == "1" ]]; then
    # Operator forced fallback — go straight to B.
    if ! plugins_b=$(_internal_installed_plugins_fallback); then
      echo "registry: candidate A skipped (forced) and candidate B (installed_plugins.json) failed; falling through with empty plugin map — self-bootstrap will inject wheel" >&2
      plugins='{}'
      source='self-bootstrap-only'
      fallback_used=true
    else
      plugins="$plugins_b"
      source='candidate-b-installed-plugins-json'
      fallback_used=true
      echo "registry: WHEEL_REGISTRY_FALLBACK=1 forced; using candidate B" >&2
    fi
  else
    # Try A first.
    plugins_a=$(_internal_path_parse) || plugins_a='{}'
    local count_a
    count_a=$(printf '%s\n' "$plugins_a" | jq 'length' 2>/dev/null || echo 0)
    if [[ "$count_a" -gt 0 ]]; then
      plugins="$plugins_a"
    else
      # A returned empty — auto-fall-back to B.
      echo "registry: candidate A returned empty, falling back to B" >&2
      if ! plugins_b=$(_internal_installed_plugins_fallback); then
        # Both candidates failed (e.g. fresh CI runner with no plugin
        # install). Fall through with empty plugins map — self-bootstrap
        # below injects wheel itself. Workflows that DO declare
        # requires_plugins fail loud at resolve_workflow_dependencies,
        # which is the correct gate for that error class.
        echo "registry: both candidate A (PATH parse) and candidate B (installed_plugins.json) failed; falling through with empty plugin map — self-bootstrap will inject wheel" >&2
        plugins='{}'
        source='self-bootstrap-only'
        fallback_used=true
      else
        plugins="$plugins_b"
        source='candidate-b-installed-plugins-json'
        fallback_used=true
      fi
    fi
  fi

  # Self-bootstrap (I-R-3): ensure wheel itself appears in the registry.
  # If PATH parsing missed wheel for any reason, derive its install dir
  # from BASH_SOURCE and add it. The registry entry for wheel from PATH
  # parsing wins if both are present.
  local self_lib_dir self_plugin_dir self_manifest self_name
  self_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  self_plugin_dir="$(dirname "$self_lib_dir")"
  self_manifest="${self_plugin_dir}/.claude-plugin/plugin.json"
  if [[ -f "$self_manifest" ]]; then
    self_name=$(jq -r '.name // empty' "$self_manifest" 2>/dev/null)
    if [[ -n "$self_name" && "$self_name" != "null" ]]; then
      # Only inject if not already present (PATH/installed_plugins win).
      if ! printf '%s\n' "$plugins" | jq -e --arg k "$self_name" 'has($k)' >/dev/null; then
        plugins=$(printf '%s\n' "$plugins" | jq -c --arg k "$self_name" --arg v "$self_plugin_dir" '. + {($k): $v}')
        echo "registry: self-bootstrap injected '${self_name}' from BASH_SOURCE (${self_plugin_dir})" >&2
      fi
    fi
  fi

  # Emit envelope.
  jq -c -n \
    --arg built_at "$built_at" \
    --arg source "$source" \
    --argjson fallback_used "$fallback_used" \
    --argjson plugins "$plugins" \
    '{schema_version:1, built_at:$built_at, source:$source, fallback_used:$fallback_used, plugins:$plugins}'
}
