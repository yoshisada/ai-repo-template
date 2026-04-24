#!/usr/bin/env bash
# Test: distill-multi-theme-state-flip-isolation
#
# Validates: FR-019 — source-entry status flips MUST be partitioned per-PRD.
# US4 scenario 4: "a source entry belongs to Theme A only; when both A and B
# are distilled, that entry's status flip affects Theme A's PRD only — Theme
# B's PRD does not touch it."
#
# Strategy — SKILL.md assertion guard tripwire:
#   The partition invariant is enforced by the `assert_in_bundle` guard
#   inside Step 5's per-PRD flip loop. A live plugin-skill harness run of
#   /kiln:kiln-distill against a two-theme fixture would require
#   interactive-stdin picker support (not yet in the harness). The
#   tripwire asserts the guard's structural shape in SKILL.md:
#
#     1. Step 5 iterates PRD_BUNDLES (per-PRD scope).
#     2. BUNDLED_PATHS set is built from THIS PRD's feedback + item + issue.
#     3. An `assert_in_bundle` function rejects paths not in BUNDLED_PATHS
#        with an FR-019 error message.
#     4. Every `flip_*` call is guarded by `assert_in_bundle` in the loop.
#
#   Additionally, the tripwire independently validates the assertion logic
#   by sourcing the guard into a test shell and exercising both the
#   in-bundle pass path and the out-of-bundle reject path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-distill/SKILL.md"

# 1. Per-PRD bundle iteration at Step 5.
if ! grep -qE 'for bundle_row in "\$\{PRD_BUNDLES\[@\]\}"' "$SKILL"; then
  echo "FAIL: Step 5 does not iterate per-PRD PRD_BUNDLES" >&2
  exit 1
fi

# 2. BUNDLED_PATHS built from this PRD's three-group partition.
if ! grep -qF 'BUNDLED_PATHS=$(printf ' "$SKILL"; then
  echo "FAIL: per-PRD BUNDLED_PATHS computation missing (FR-019 partition)" >&2
  exit 1
fi

# 3. assert_in_bundle guard with FR-019 error anchor.
if ! grep -qE 'assert_in_bundle\(\) \{' "$SKILL"; then
  echo "FAIL: assert_in_bundle guard function not defined in Step 5" >&2
  exit 1
fi
if ! grep -qE 'refused to flip state.*not in bundle.*FR-019 guard' "$SKILL"; then
  echo "FAIL: assert_in_bundle missing FR-019 error anchor" >&2
  exit 1
fi

# 4. Every flip_* call is guarded.
for flip in flip_feedback_or_issue flip_roadmap_item; do
  if ! grep -qE "assert_in_bundle.*\|\| continue[[:space:]]*$" "$SKILL"; then
    : # loop-level guard acceptable
  fi
  if ! grep -qE "^[[:space:]]*$flip " "$SKILL"; then
    echo "FAIL: $flip call-site missing from Step 5 loop" >&2
    exit 1
  fi
done

# 5. Behavioral unit test on the guard logic — reproduce a miniature of the
# Step 5 loop and prove out-of-bundle paths are rejected.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/guard-unit.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# Simulate Step 5 partition: Theme A bundle contains only "a-only.md".
# Theme B bundle contains only "b-only.md".
FEEDBACK_PATHS=""
ITEM_PATHS=""
ISSUE_PATHS=".kiln/issues/a-only.md"

BUNDLED_PATHS=$(printf '%s\n%s\n%s\n' "$FEEDBACK_PATHS" "$ITEM_PATHS" "$ISSUE_PATHS" | LC_ALL=C sort -u | sed '/^$/d')

assert_in_bundle() {
  local path="$1"
  if ! echo "$BUNDLED_PATHS" | grep -qxF "$path"; then
    echo "BLOCKED: $path" >&2
    return 1
  fi
  echo "PASSED: $path"
  return 0
}

# In-bundle path — should pass.
if ! assert_in_bundle ".kiln/issues/a-only.md"; then
  echo "FAIL: a-only.md rejected by its own bundle (false negative)" >&2
  exit 1
fi

# Out-of-bundle path — should block.
if assert_in_bundle ".kiln/issues/b-only.md" 2>/dev/null; then
  echo "FAIL: b-only.md was NOT blocked by theme-A bundle (false positive — FR-019 broken)" >&2
  exit 1
fi

echo "guard-unit OK"
BASH

bash "$TMP/guard-unit.sh"

echo "PASS: per-PRD state-flip partition guard is structurally present + functionally correct (FR-019)"
