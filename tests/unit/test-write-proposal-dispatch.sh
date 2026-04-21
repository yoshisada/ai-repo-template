#!/usr/bin/env bash
# tests/unit/test-write-proposal-dispatch.sh
# Unit tests for plugin-shelf/scripts/write-proposal-dispatch.sh
# Validates FR-007 (silent-on-skip), FR-008 (envelope shape), FR-010 (slug),
# FR-018 (malformed input -> skip), FR-019 (path includes date + slug),
# FR-020 (envelope is an internal artifact).

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/plugin-shelf/scripts/write-proposal-dispatch.sh"

pass=0
fail=0

# The script reads .wheel/outputs/propose-manifest-improvement.json in the
# current working directory, so each test gets an isolated temp CWD with its
# own seeded vault.
setup_sandbox() {
  local tmp
  tmp=$(mktemp -d -t dispatch.XXXXXX)
  mkdir -p "$tmp/.wheel/outputs" "$tmp/vault/manifest/types"
  cat > "$tmp/vault/manifest/types/mistake.md" <<'EOF'
---
type: mistake
---
# Mistake template
- severity — enum: minor | moderate | major
- tags — three-axis
EOF
  printf '%s' "$tmp"
}

cleanup_sandbox() {
  rm -rf "$1"
}

# Helper: run dispatch in a sandbox with a given reflect JSON and return the
# envelope (stdout).
run_dispatch() {
  local sandbox="$1" reflect_json="$2"
  printf '%s\n' "$reflect_json" > "$sandbox/.wheel/outputs/propose-manifest-improvement.json"
  (cd "$sandbox" && VAULT_ROOT="$sandbox/vault" bash "$SCRIPT" 2>/dev/null || true)
}

# FR-018: missing reflect output -> skip envelope
sb=$(setup_sandbox)
env_out=$(cd "$sb" && VAULT_ROOT="$sb/vault" bash "$SCRIPT" 2>/dev/null || true)
if printf '%s' "$env_out" | jq -e '.action=="skip"' >/dev/null 2>&1; then
  printf 'PASS missing-reflect-output\n'; pass=$((pass+1))
else
  printf 'FAIL missing-reflect-output — got=%s\n' "$env_out"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-003/FR-007: reflect output says skip:true -> skip envelope
sb=$(setup_sandbox)
out=$(run_dispatch "$sb" '{"skip": true}')
if printf '%s' "$out" | jq -e '.action=="skip"' >/dev/null 2>&1; then
  printf 'PASS explicit-skip\n'; pass=$((pass+1))
else
  printf 'FAIL explicit-skip — got=%s\n' "$out"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-018: malformed JSON -> skip envelope
sb=$(setup_sandbox)
printf 'not-json\n' > "$sb/.wheel/outputs/propose-manifest-improvement.json"
out=$(cd "$sb" && VAULT_ROOT="$sb/vault" bash "$SCRIPT" 2>/dev/null || true)
if printf '%s' "$out" | jq -e '.action=="skip"' >/dev/null 2>&1; then
  printf 'PASS malformed-json\n'; pass=$((pass+1))
else
  printf 'FAIL malformed-json — got=%s\n' "$out"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-005: `current` not in target -> skip envelope
sb=$(setup_sandbox)
out=$(run_dispatch "$sb" '{"skip": false, "target":"@manifest/types/mistake.md", "section":"s", "current":"definitely-not-in-the-file", "proposed":"replacement", "why":"see .wheel/outputs/evidence.json"}')
if printf '%s' "$out" | jq -e '.action=="skip"' >/dev/null 2>&1; then
  printf 'PASS hallucinated-current-forces-skip\n'; pass=$((pass+1))
else
  printf 'FAIL hallucinated-current-forces-skip — got=%s\n' "$out"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-004: target out-of-scope -> skip envelope
sb=$(setup_sandbox)
out=$(run_dispatch "$sb" '{"skip": false, "target":"plugin-shelf/skills/foo.md", "section":"s", "current":"x", "proposed":"y", "why":"see .wheel/outputs/evidence.json"}')
if printf '%s' "$out" | jq -e '.action=="skip"' >/dev/null 2>&1; then
  printf 'PASS out-of-scope\n'; pass=$((pass+1))
else
  printf 'FAIL out-of-scope — got=%s\n' "$out"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# Happy path — all gates pass -> write envelope with correct shape
sb=$(setup_sandbox)
VALID_CURRENT="- severity — enum: minor | moderate | major"
# Escape `current` for JSON (handles the em-dash etc.).
reflect_json=$(jq -cn \
  --arg target "@manifest/types/mistake.md" \
  --arg section "## Required frontmatter" \
  --arg current "$VALID_CURRENT" \
  --arg proposed "- severity — enum: minor | moderate | major | critical" \
  --arg why "see .wheel/outputs/evidence.json for the production outage severity case" \
  '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
out=$(run_dispatch "$sb" "$reflect_json")
if printf '%s' "$out" | jq -e '
    .action=="write"
    and .target=="@manifest/types/mistake.md"
    and (.proposal_path | test("^@inbox/open/[0-9]{4}-[0-9]{2}-[0-9]{2}-manifest-improvement-[a-z0-9-]+\\.md$"))
    and .frontmatter.type=="proposal"
    and .frontmatter.target=="@manifest/types/mistake.md"
    and (.frontmatter.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
    and .body_sections.target_line=="@manifest/types/mistake.md"
    and .body_sections.section=="## Required frontmatter"
    and (.body_sections.current | test("severity"))
    and (.body_sections.proposed | test("critical"))
    and (.body_sections.why | test("evidence.json"))
  ' >/dev/null 2>&1; then
  printf 'PASS happy-path-envelope-shape\n'; pass=$((pass+1))
else
  printf 'FAIL happy-path-envelope-shape — got=%s\n' "$out"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-007: the dispatch script must emit NOTHING to stderr on any path
sb=$(setup_sandbox)
printf '{"skip": true}\n' > "$sb/.wheel/outputs/propose-manifest-improvement.json"
stderr_capture=$( (cd "$sb" && VAULT_ROOT="$sb/vault" bash "$SCRIPT" 2>&1 >/dev/null) )
if [ -z "$stderr_capture" ]; then
  printf 'PASS silent-stderr-on-skip\n'; pass=$((pass+1))
else
  printf 'FAIL silent-stderr-on-skip — stderr=%s\n' "$stderr_capture"; fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-010: slug in proposal_path matches the deterministic derivation
sb=$(setup_sandbox)
why_text="Add status_label field because .wheel/outputs/sync-summary.md shows hard-coded labels"
expected_slug=$(printf '%s' "$why_text" | bash "$ROOT/plugin-shelf/scripts/derive-proposal-slug.sh")
reflect_json=$(jq -cn \
  --arg target "@manifest/types/mistake.md" \
  --arg section "s" \
  --arg current "$VALID_CURRENT" \
  --arg proposed "replacement" \
  --arg why "$why_text" \
  '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
out=$(run_dispatch "$sb" "$reflect_json")
path=$(printf '%s' "$out" | jq -r '.proposal_path // ""')
if printf '%s' "$path" | grep -qE "manifest-improvement-${expected_slug}\.md\$"; then
  printf 'PASS slug-matches-derivation\n'; pass=$((pass+1))
else
  printf 'FAIL slug-matches-derivation — path=%s expected_slug=%s\n' "$path" "$expected_slug"
  fail=$((fail+1))
fi
cleanup_sandbox "$sb"

# FR-019: proposal_path begins with @inbox/open/
sb=$(setup_sandbox)
reflect_json=$(jq -cn \
  --arg target "@manifest/types/mistake.md" \
  --arg section "s" \
  --arg current "$VALID_CURRENT" \
  --arg proposed "replacement" \
  --arg why "see .wheel/outputs/evidence.json" \
  '{skip:false, target:$target, section:$section, current:$current, proposed:$proposed, why:$why}')
out=$(run_dispatch "$sb" "$reflect_json")
path=$(printf '%s' "$out" | jq -r '.proposal_path // ""')
case "$path" in
  @inbox/open/*) printf 'PASS proposal-path-prefix\n'; pass=$((pass+1)) ;;
  *) printf 'FAIL proposal-path-prefix — path=%s\n' "$path"; fail=$((fail+1)) ;;
esac
cleanup_sandbox "$sb"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
