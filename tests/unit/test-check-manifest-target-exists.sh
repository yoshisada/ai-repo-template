#!/usr/bin/env bash
# tests/unit/test-check-manifest-target-exists.sh
# Unit tests for plugin-shelf/scripts/check-manifest-target-exists.sh (FR-005).
# Validates verbatim-match gate per Acceptance Scenario US2#4.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/plugin-shelf/scripts/check-manifest-target-exists.sh"
TMP=$(mktemp -d -t check-target.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/vault/manifest/types"
TARGET_FILE="$TMP/vault/manifest/types/mistake.md"
cat > "$TARGET_FILE" <<'EOF'
---
type: mistake
---
# Mistake template
- severity — enum: minor | moderate | major
- tags — three-axis
EOF

pass=0
fail=0

assert_exit() {
  local name="$1" expected="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$expected" ]; then
    printf 'PASS %s (exit=%s)\n' "$name" "$got"
    pass=$((pass+1))
  else
    printf 'FAIL %s — expected=%s got=%s\n' "$name" "$expected" "$got"
    fail=$((fail+1))
  fi
}

# Acceptance Scenario US2#4 — `current` appears verbatim in the target.
current_file="$TMP/c1.txt"
printf '%s' "- severity — enum: minor | moderate | major" > "$current_file"
assert_exit "verbatim-match-single-line" "0" env VAULT_ROOT="$TMP/vault" bash "$SCRIPT" "@manifest/types/mistake.md" "$current_file"

# US2#4 negative — `current` differs by a single byte -> non-match -> exit 1
mismatched="$TMP/c2.txt"
printf '%s' "- severity — enum: minor | moderate | CRITICAL" > "$mismatched"
assert_exit "single-byte-mismatch" "1" env VAULT_ROOT="$TMP/vault" bash "$SCRIPT" "@manifest/types/mistake.md" "$mismatched"

# FR-005: target does not exist -> exit 1
ghost="$TMP/c3.txt"
printf '%s' "anything" > "$ghost"
assert_exit "target-missing" "1" env VAULT_ROOT="$TMP/vault" bash "$SCRIPT" "@manifest/types/ghost.md" "$ghost"

# FR-005: unresolved vault_root -> exit 1. We unset both VAULT_ROOT and ensure
# no .shelf-config in the CWD (use a temp subdir as CWD).
unset_dir="$TMP/nowhere"
mkdir -p "$unset_dir"
(cd "$unset_dir" && env -u VAULT_ROOT bash "$SCRIPT" "@manifest/types/mistake.md" "$current_file") >/dev/null 2>&1
rc=$?
if [ "$rc" = "1" ]; then
  printf 'PASS unresolved-vault-root\n'; pass=$((pass+1))
else
  printf 'FAIL unresolved-vault-root — got exit=%s\n' "$rc"; fail=$((fail+1))
fi

# FR-005: .shelf-config fallback when VAULT_ROOT unset. Use a CWD that has
# .shelf-config pointing at the vault.
cfg_dir="$TMP/with-config"
mkdir -p "$cfg_dir"
cat > "$cfg_dir/.shelf-config" <<EOF
vault_root = $TMP/vault
EOF
current_cfg="$TMP/c-cfg.txt"
printf '%s' "- severity — enum: minor | moderate | major" > "$current_cfg"
(cd "$cfg_dir" && env -u VAULT_ROOT bash "$SCRIPT" "@manifest/types/mistake.md" "$current_cfg") >/dev/null 2>&1
rc=$?
if [ "$rc" = "0" ]; then
  printf 'PASS shelf-config-fallback\n'; pass=$((pass+1))
else
  printf 'FAIL shelf-config-fallback — got exit=%s\n' "$rc"; fail=$((fail+1))
fi

# FR-005: multi-line `current` — each line must appear in the target file
multi="$TMP/multi.txt"
cat > "$multi" <<'EOF'
- severity — enum: minor | moderate | major
- tags — three-axis
EOF
assert_exit "multi-line-verbatim" "0" env VAULT_ROOT="$TMP/vault" bash "$SCRIPT" "@manifest/types/mistake.md" "$multi"

# Non-@ target path -> exit 1 (only @-prefixed vault paths are resolvable).
assert_exit "non-at-prefix" "1" env VAULT_ROOT="$TMP/vault" bash "$SCRIPT" "manifest/types/mistake.md" "$current_file"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
