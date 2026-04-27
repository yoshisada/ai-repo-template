#!/usr/bin/env bash
# SC-001 / FR-001..FR-004 / FR-006 / NFR-001 — build-prd Step 4b.5 auto-flip fixture.
#
# Spec:    specs/escalation-audit/spec.md (US1 acceptance scenarios 1..4 + NFR-001)
# Contract: specs/escalation-audit/contracts/interfaces.md §A.2 + §D.1
#
# What this fixture asserts:
#   - PR_STATE=MERGED  → derived_from items end at state:shipped + status:shipped + pr:<N> + shipped_date:<today>
#                        + diagnostic line matches the anchored regex from §A.2.
#   - PR_STATE=OPEN    → no item is mutated; diagnostic emits pr-state=OPEN auto-flip=skipped reason=pr-not-merged.
#   - Idempotent re-run on already-flipped items → byte-identical files (FR-004) +
#                        diagnostic shows already_shipped == items.
#   - read_derived_from returning [] (no derived_from)  → reason=no-derived-from auto-flip=skipped.
#
# Substrate: tier-2 (run.sh-only) — extracts the inline Bash block from
# plugin-kiln/skills/kiln-build-prd/SKILL.md verbatim and invokes it inside a
# scaffolded $TMP fixture, so the test exercises the SHIPPED skill body (not a re-implementation).
#
# Invoke: bash plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugin-kiln/skills/kiln-build-prd/SKILL.md"

[[ -f "$SKILL_MD" ]] || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 2; }
command -v jq >/dev/null || { echo "FAIL: jq required"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
}

# --- Extract the Step 4b.5 bash block from SKILL.md verbatim ----------------
extract_step4b5_block() {
  awk '
    /^### Step 4b\.5: Auto-flip/  { in_section = 1; next }
    /^### Step 4b\.5 invariants/  { in_section = 0; next }
    in_section && /^```bash$/     { in_block = 1; next }
    in_section && in_block && /^```$/ { in_block = 0; next }
    in_section && in_block        { print }
  ' "$SKILL_MD"
}

BLOCK="$(extract_step4b5_block)"
[[ -n "$BLOCK" ]] || { echo "FAIL: could not extract Step 4b.5 bash block from SKILL.md"; exit 2; }

# --- Per-case scaffold + invoke helper --------------------------------------
# Scaffolds:
#   $TMP/case-<n>/.kiln/roadmap/items/{a,b,c}.md (state: distilled, status: in-progress)
#   $TMP/case-<n>/prd.md                          (derived_from listing the 3 items)
#   $TMP/case-<n>/plugin-kiln                     (symlink → $REPO_ROOT/plugin-kiln)
#   $TMP/case-<n>/stubs/gh                        (stub: prints whatever PR_STATE arg dictates)
#
# Invokes: cd into the case dir, define read_derived_from shim, run the extracted block.
scaffold_case() {
  local case_dir="$1" pr_state="$2"
  mkdir -p "$case_dir/.kiln/roadmap/items" "$case_dir/stubs"
  ln -sfn "$REPO_ROOT/plugin-kiln" "$case_dir/plugin-kiln"

  for slug in a b c; do
    cat > "$case_dir/.kiln/roadmap/items/2026-04-25-${slug}.md" <<EOF
---
id: 2026-04-25-${slug}
state: distilled
status: in-progress
kind: feature
prd: docs/features/2026-04-26-foo/PRD.md
---

# Item ${slug}

body
EOF
  done

  cat > "$case_dir/prd.md" <<EOF
---
derived_from:
  - .kiln/roadmap/items/2026-04-25-a.md
  - .kiln/roadmap/items/2026-04-25-b.md
  - .kiln/roadmap/items/2026-04-25-c.md
---

# PRD body
EOF

  # gh stub — emits the merge-state JSON the contract gates on.
  cat > "$case_dir/stubs/gh" <<EOF
#!/usr/bin/env bash
# Test stub: bypasses real gh CLI; never makes network calls (NFR-002).
case "\$*" in
  *pr*view*--json*state,mergedAt*)
    printf '{"state":"%s","mergedAt":"2026-04-26T00:00:00Z"}\n' "$pr_state"
    ;;
  *)
    echo '{}' ;;
esac
EOF
  chmod +x "$case_dir/stubs/gh"
}

# read_derived_from shim emits one entry per line (matches Step 4b helper contract — Module E).
READ_DERIVED_FROM_SHIM='
read_derived_from() {
  awk '"'"'
    /^---/ { fm++; next }
    fm == 1 && /^derived_from:[[:space:]]*$/ { in_df = 1; next }
    fm == 1 && in_df && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      print
      next
    }
    fm == 1 && in_df && /^[a-zA-Z]/ { in_df = 0 }
  '"'"' "$1"
}'

run_case() {
  local case_dir="$1" pr_number="$2"
  local runner="$case_dir/run-block.sh"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
set -uo pipefail
PATH="$case_dir/stubs:\$PATH"
PRD_PATH="$case_dir/prd.md"
PR_NUMBER="$pr_number"
$READ_DERIVED_FROM_SHIM
$BLOCK
EOF
  ( cd "$case_dir" && bash "$runner" )
}

# --- Verification regex from §A.2 (anchored) --------------------------------
DIAG_RE='^step4b-auto-flip: pr-state=(MERGED|OPEN|CLOSED|unknown) auto-flip=(success|skipped) items=[0-9]+ patched=[0-9]+ already_shipped=[0-9]+ reason=[a-z-]*$'

TODAY="$(date -u +%Y-%m-%d)"

# === Case 1: PR_STATE=MERGED — happy path (US1 acceptance scenarios 1, 4, 5) ===
echo "--- Case 1: PR_STATE=MERGED ---"
CASE1="$TMP/case-merged"
scaffold_case "$CASE1" "MERGED"
OUT1="$(run_case "$CASE1" 999)"
echo "$OUT1"

assert "diagnostic line matches anchored regex from §A.2" \
  bash -c "echo '$OUT1' | grep -qE '$DIAG_RE'"

assert "diagnostic shows pr-state=MERGED auto-flip=success" \
  bash -c "echo '$OUT1' | grep -qE 'pr-state=MERGED auto-flip=success items=3 patched=3 already_shipped=0 reason=$'"

for slug in a b c; do
  item="$CASE1/.kiln/roadmap/items/2026-04-25-${slug}.md"
  assert "item $slug has state: shipped" grep -q '^state: shipped$' "$item"
  assert "item $slug has status: shipped" grep -q '^status: shipped$' "$item"
  assert "item $slug has pr: 999" grep -q '^pr: 999$' "$item"
  assert "item $slug has shipped_date: $TODAY" grep -q "^shipped_date: ${TODAY}$" "$item"
done

# === Case 2: idempotency re-run (US1 scenario 3 + FR-004) ===
echo "--- Case 2: idempotency (re-run on already-shipped items) ---"
SNAPSHOT_BEFORE="$TMP/snapshot-before"
SNAPSHOT_AFTER="$TMP/snapshot-after"
mkdir -p "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"
for slug in a b c; do
  cp "$CASE1/.kiln/roadmap/items/2026-04-25-${slug}.md" "$SNAPSHOT_BEFORE/${slug}.md"
done

OUT2="$(run_case "$CASE1" 999)"
echo "$OUT2"

assert "re-run diagnostic shows already_shipped=3 patched=0" \
  bash -c "echo '$OUT2' | grep -qE 'pr-state=MERGED auto-flip=success items=3 patched=0 already_shipped=3 reason=$'"

for slug in a b c; do
  cp "$CASE1/.kiln/roadmap/items/2026-04-25-${slug}.md" "$SNAPSHOT_AFTER/${slug}.md"
  assert "item $slug byte-identical across re-run (FR-004)" \
    diff -q "$SNAPSHOT_BEFORE/${slug}.md" "$SNAPSHOT_AFTER/${slug}.md"
done

# === Case 3: PR_STATE=OPEN — no mutation (US1 scenario 2) ===
echo "--- Case 3: PR_STATE=OPEN ---"
CASE3="$TMP/case-open"
scaffold_case "$CASE3" "OPEN"
SNAPSHOT_OPEN_BEFORE="$TMP/snapshot-open-before"
mkdir -p "$SNAPSHOT_OPEN_BEFORE"
for slug in a b c; do
  cp "$CASE3/.kiln/roadmap/items/2026-04-25-${slug}.md" "$SNAPSHOT_OPEN_BEFORE/${slug}.md"
done

OUT3="$(run_case "$CASE3" 1234)"
echo "$OUT3"

assert "OPEN-state diagnostic emits skipped + reason=pr-not-merged" \
  bash -c "echo '$OUT3' | grep -qE 'pr-state=OPEN auto-flip=skipped items=0 patched=0 already_shipped=0 reason=pr-not-merged'"

assert "OPEN-state diagnostic matches anchored regex" \
  bash -c "echo '$OUT3' | grep -qE '$DIAG_RE'"

for slug in a b c; do
  item="$CASE3/.kiln/roadmap/items/2026-04-25-${slug}.md"
  assert "OPEN: item $slug NOT mutated (state still distilled)" grep -q '^state: distilled$' "$item"
  assert "OPEN: item $slug byte-identical to pre-run snapshot" \
    diff -q "$SNAPSHOT_OPEN_BEFORE/${slug}.md" "$item"
done

# === Case 4: empty derived_from — reason=no-derived-from (edge case) ===
echo "--- Case 4: empty derived_from ---"
CASE4="$TMP/case-empty-df"
scaffold_case "$CASE4" "MERGED"
# Overwrite the PRD with no derived_from list
cat > "$CASE4/prd.md" <<'EOF'
---
title: empty
---

body only
EOF
OUT4="$(run_case "$CASE4" 999)"
echo "$OUT4"

assert "empty derived_from emits reason=no-derived-from" \
  bash -c "echo '$OUT4' | grep -qE 'pr-state=MERGED auto-flip=skipped items=0 patched=0 already_shipped=0 reason=no-derived-from'"

# --- Tally ------------------------------------------------------------------
echo
echo "PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  echo "FAIL: $FAIL assertion(s) failed"
  exit 1
fi
echo "PASS"
