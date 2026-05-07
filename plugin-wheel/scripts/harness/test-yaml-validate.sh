#!/usr/bin/env bash
# test-yaml-validate.sh — Validate a test.yaml against the harness schema.
#
# Satisfies: FR-002 (test.yaml contract)
# Contract:  contracts/interfaces.md §7.6 + §1 (test.yaml schema)
#
# Usage:
#   test-yaml-validate.sh <test-yaml-path>
#
# Args:
#   <test-yaml-path>   absolute path to the test.yaml file
#
# Stdout: nothing (on success, silent)
# Stderr: diagnostics (on failure, one line per violation; warnings on unknown keys)
# Exit:   0 on pass, 2 on schema violation (inconclusive — contracts §1)
#
# Implementation note: we use a tiny pure-grep/sed parser because we can't
# guarantee `yq` is on PATH in consumer repos. The schema is small and
# line-oriented, so grep is sufficient. Accepted forms per line:
#   key: value
#   key: "quoted value"
# Anything else is either an unknown key (warning) or a parse error (2).
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "test-yaml-validate.sh: expected 1 arg (test-yaml-path), got $#" >&2
  exit 2
fi

yaml_path=$1

if [[ ! -f $yaml_path ]]; then
  echo "test-yaml-validate.sh: file does not exist: $yaml_path" >&2
  exit 2
fi

# Accepted keys (contracts §1). `env` and `require-env` are extension
# fields for 3rd-party-model fixtures — see parse-test-yaml-env.mjs.
known_keys=(harness-type skill-under-test expected-exit description timeout-override env require-env)

# Required keys (contracts §1).
required_keys=(harness-type skill-under-test description)

# Accepted harness-type values (v1: plugin-skill only).
accepted_substrates=(plugin-skill)

# Extract a scalar string value for `key:`. Returns empty if not present.
# Handles both `key: value` and `key: "value"`.
extract_scalar() {
  local key=$1 file=$2
  # Match start-of-line key, capture value after colon+space, strip surrounding quotes.
  awk -v k="^${key}:[[:space:]]*" '
    $0 ~ k {
      sub(k, "");
      # strip surrounding double quotes if both ends have them
      if (substr($0,1,1) == "\"" && substr($0,length($0),1) == "\"") {
        print substr($0, 2, length($0)-2)
      } else {
        # also strip single quotes
        if (substr($0,1,1) == "\x27" && substr($0,length($0),1) == "\x27") {
          print substr($0, 2, length($0)-2)
        } else {
          print $0
        }
      }
      exit
    }
  ' "$file"
}

# Enumerate all top-level keys in the file (lines matching `^<word>:`).
all_top_keys() {
  awk '/^[A-Za-z][A-Za-z0-9_-]*:/ { sub(/:.*/, ""); print }' "$1"
}

# --- Check required keys present and non-empty -------------------------------
violations=0
for k in "${required_keys[@]}"; do
  v=$(extract_scalar "$k" "$yaml_path")
  if [[ -z $v ]]; then
    echo "test-yaml-validate.sh: missing or empty required key '$k'" >&2
    violations=$((violations + 1))
  fi
done

# --- harness-type must be in accepted set ------------------------------------
htype=$(extract_scalar "harness-type" "$yaml_path")
if [[ -n $htype ]]; then
  ok=0
  for s in "${accepted_substrates[@]}"; do
    if [[ $htype == "$s" ]]; then ok=1; break; fi
  done
  if [[ $ok -eq 0 ]]; then
    echo "test-yaml-validate.sh: harness-type '$htype' not in v1 accepted set: ${accepted_substrates[*]}" >&2
    violations=$((violations + 1))
  fi
fi

# --- expected-exit optional; default 0; must be non-negative int -------------
exp=$(extract_scalar "expected-exit" "$yaml_path")
if [[ -n $exp ]]; then
  if ! [[ $exp =~ ^(0|[1-9][0-9]*)$ ]]; then
    echo "test-yaml-validate.sh: expected-exit must be a non-negative integer, got '$exp'" >&2
    violations=$((violations + 1))
  fi
fi

# --- timeout-override optional; must be int in [60, 3600] --------------------
tov=$(extract_scalar "timeout-override" "$yaml_path")
if [[ -n $tov ]]; then
  if ! [[ $tov =~ ^[1-9][0-9]*$ ]] || (( tov < 60 )) || (( tov > 3600 )); then
    echo "test-yaml-validate.sh: timeout-override must be an integer in [60, 3600], got '$tov'" >&2
    violations=$((violations + 1))
  fi
fi

# --- Unknown top-level keys: warning-only (contracts §1) ---------------------
while read -r key; do
  [[ -z $key ]] && continue
  known=0
  for k in "${known_keys[@]}"; do
    if [[ $key == "$k" ]]; then known=1; break; fi
  done
  if [[ $known -eq 0 ]]; then
    echo "test-yaml-validate.sh: warning — unknown top-level key '$key' (forward-compat, not an error)" >&2
  fi
done < <(all_top_keys "$yaml_path")

if (( violations > 0 )); then
  echo "test-yaml-validate.sh: $violations schema violation(s) — exit 2 (inconclusive)" >&2
  exit 2
fi

exit 0
