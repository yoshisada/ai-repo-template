#!/usr/bin/env bash
# SC-6 fixture — verifies research-runner.md, fixture-synthesizer.md, output-quality-judge.md
# meet FR-A-10 + FR-A-11:
#   * `tools:` present in frontmatter, with the expected allowlist
#   * NO `model:` frontmatter (research-first agents — workflow step decides)
#   * Body has NO verb tables (no `| Verb |`)
#   * Body has NO enumerated tool references (e.g. `Bash(`, `Read(`)
#   * Body has NO step-by-step task prose (no `## Steps`, no leading `1. `)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
AGENTS_DIR="${REPO_ROOT}/plugin-kiln/agents"

declare -A EXPECTED_TOOLS
EXPECTED_TOOLS[research-runner]="Read, Bash, SendMessage, TaskUpdate, TaskList"
EXPECTED_TOOLS[fixture-synthesizer]="Read, Write, SendMessage, TaskUpdate"
EXPECTED_TOOLS[output-quality-judge]="Read, SendMessage, TaskUpdate"

# Helper: extract frontmatter (between first two `---` lines).
get_frontmatter() {
  awk '
    BEGIN { fm_seen=0; in_fm=0 }
    /^---[[:space:]]*$/ {
      if (!fm_seen) { fm_seen=1; in_fm=1; next }
      else if (in_fm) { exit }
    }
    in_fm { print }
  ' "$1"
}

# Helper: extract body (everything after second `---`).
get_body() {
  awk '
    BEGIN { fm_seen=0; closed=0 }
    /^---[[:space:]]*$/ {
      if (!fm_seen) { fm_seen=1; next }
      else if (!closed) { closed=1; next }
    }
    closed { print }
  ' "$1"
}

fail=0
declare -i pass=0

for agent in research-runner fixture-synthesizer output-quality-judge; do
  file="${AGENTS_DIR}/${agent}.md"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: ${agent}.md missing at $file" >&2
    fail=1; continue
  fi

  fm="$(get_frontmatter "$file")"
  body="$(get_body "$file")"

  # Frontmatter checks.
  if ! grep -qE '^tools:[[:space:]]+' <<<"$fm"; then
    echo "FAIL: ${agent}.md frontmatter missing 'tools:'" >&2; fail=1
  else
    actual_tools="$(grep -E '^tools:[[:space:]]+' <<<"$fm" | sed -E 's/^tools:[[:space:]]+//' | sed -E 's/[[:space:]]+$//')"
    expected="${EXPECTED_TOOLS[$agent]}"
    if [[ "$actual_tools" != "$expected" ]]; then
      echo "FAIL: ${agent}.md tools mismatch — got '$actual_tools', want '$expected'" >&2; fail=1
    fi
  fi

  if grep -qE '^model:' <<<"$fm"; then
    echo "FAIL: ${agent}.md MUST NOT have 'model:' frontmatter (FR-A-10)" >&2; fail=1
  fi

  # Required name + description.
  grep -qE '^name:[[:space:]]+' <<<"$fm" || { echo "FAIL: ${agent}.md missing name" >&2; fail=1; }
  grep -qE '^description:[[:space:]]+' <<<"$fm" || { echo "FAIL: ${agent}.md missing description" >&2; fail=1; }

  # Body checks.
  if grep -qF '| Verb |' <<<"$body"; then
    echo "FAIL: ${agent}.md body contains a verb table (FR-A-11)" >&2; fail=1
  fi

  # Enumerated tool references — patterns like `Bash(`, `Read(`, `Write(`, `Edit(`, `Agent(`.
  if grep -qE '\b(Bash|Read|Write|Edit|Agent|Grep|Glob|TaskCreate|WebFetch)\(' <<<"$body"; then
    offending="$(grep -E '\b(Bash|Read|Write|Edit|Agent|Grep|Glob|TaskCreate|WebFetch)\(' <<<"$body" | head -1)"
    echo "FAIL: ${agent}.md body contains enumerated tool reference: $offending (FR-A-11)" >&2; fail=1
  fi

  # Step-by-step prose: `## Steps` heading, or numbered task lists at body root.
  if grep -qE '^##[[:space:]]+Steps?[[:space:]]*$' <<<"$body"; then
    echo "FAIL: ${agent}.md body contains '## Steps' heading (FR-A-11)" >&2; fail=1
  fi
  # Numbered task list at column 0 (must be 1., 2., 3., 4., not e.g. content like `4.6`).
  if grep -qE '^[0-9]+\.[[:space:]]+\*\*' <<<"$body"; then
    echo "FAIL: ${agent}.md body contains numbered step list (FR-A-11)" >&2; fail=1
  fi

  pass+=1
done

if [[ $fail -ne 0 ]]; then
  echo "FAIL: structural-validity gates failed" >&2
  exit 1
fi

echo "PASS: research-first-agents-structural — all 3 agents conform to FR-A-10/FR-A-11"
