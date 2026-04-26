#!/usr/bin/env bash
# SC-002 / FR-005 / NFR-004 — kiln-roadmap --check Check 5 merged-PR drift fixture.
#
# Spec:    specs/escalation-audit/spec.md (US2 acceptance scenarios 1..4)
# Contract: specs/escalation-audit/contracts/interfaces.md §A.3 + §D.2
#
# Cases asserted:
#   (a) ref-walk-resolved drift  → drift row with pr=#246 + resolution=ref-walk + fix line.
#   (b) heuristic-fallback drift → drift row with resolution=heuristic + Notes addendum.
#   (c) item with empty `prd:`    → NO drift row (NFR-004 backward-compat).
#   (d) `gh pr list` returns []   → NO drift row (US2 scenario 4: already-shipped pattern).
#   (e) item state=shipped        → NO drift row (Check 5 entry condition).
#
# Substrate: tier-2 (run.sh-only) — extracts the Check 5 inline block from
# plugin-kiln/skills/kiln-roadmap/SKILL.md and runs it against scaffolded items
# with PATH-prefix `gh` + `git` stubs.
#
# Invoke: bash plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugin-kiln/skills/kiln-roadmap/SKILL.md"

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

# --- Extract the §C walk loop body (Check 5 lives inside it) ---------------
# We extract the bash code-fence under "## §C: Consistency check" up through
# the first standalone closing fence after the per-item walk loop.
extract_check_block() {
  awk '
    /^## §C: Consistency check/  { in_section = 1; next }
    in_section && /^## §[A-Z]:/   { in_section = 0; next }
    in_section && /^```bash$/     { in_block = 1; next }
    in_section && in_block && /^```$/ { in_block = 0; next }
    in_section && in_block        { print }
  ' "$SKILL_MD"
}

BLOCK="$(extract_check_block)"
[[ -n "$BLOCK" ]] || { echo "FAIL: could not extract §C check block from SKILL.md"; exit 2; }

# Sanity: Check 5's drift-row literal is present in the extracted block.
echo "$BLOCK" | grep -q '\[drift\]' \
  || { echo "FAIL: extracted block does not contain Check 5 drift row"; exit 2; }

# --- Per-case scaffold ------------------------------------------------------
scaffold_case() {
  local case_dir="$1"
  mkdir -p "$case_dir/.kiln/roadmap/items" "$case_dir/stubs" \
           "$case_dir/docs/features/2026-04-20-foo" \
           "$case_dir/docs/features/2026-04-21-bar" \
           "$case_dir/docs/features/2026-04-22-baz"
  ln -sfn "$REPO_ROOT/plugin-kiln" "$case_dir/plugin-kiln"

  # Item (a): drifted via ref-walk — state=distilled, populated prd, prd file exists.
  cat > "$case_dir/.kiln/roadmap/items/2026-04-20-refwalk.md" <<'EOF'
---
id: 2026-04-20-refwalk
state: distilled
status: in-progress
kind: feature
phase: phase-10
prd: docs/features/2026-04-20-foo/PRD.md
---
body
EOF
  echo "# foo PRD" > "$case_dir/docs/features/2026-04-20-foo/PRD.md"

  # Item (b): drifted via heuristic — state=specced, populated prd, but git for-each-ref returns nothing.
  cat > "$case_dir/.kiln/roadmap/items/2026-04-21-heuristic.md" <<'EOF'
---
id: 2026-04-21-heuristic
state: specced
status: in-progress
kind: feature
phase: phase-10
prd: docs/features/2026-04-21-bar/PRD.md
---
body
EOF
  echo "# bar PRD" > "$case_dir/docs/features/2026-04-21-bar/PRD.md"

  # Item (c): NFR-004 backward-compat — state=distilled but EMPTY prd field.
  cat > "$case_dir/.kiln/roadmap/items/2026-04-22-noprd.md" <<'EOF'
---
id: 2026-04-22-noprd
state: distilled
status: in-progress
kind: feature
phase: phase-10
prd: ""
---
body
EOF

  # Item (d): NFR-004 backward-compat — state=distilled, populated prd, but gh returns []
  # (already-shipped pattern). Drift NOT flagged.
  cat > "$case_dir/.kiln/roadmap/items/2026-04-23-nopr.md" <<'EOF'
---
id: 2026-04-23-nopr
state: distilled
status: in-progress
kind: feature
phase: phase-10
prd: docs/features/2026-04-23-qux/PRD.md
---
body
EOF
  mkdir -p "$case_dir/docs/features/2026-04-23-qux"
  echo "# qux PRD" > "$case_dir/docs/features/2026-04-23-qux/PRD.md"

  # Item (e): state=shipped — Check 5 entry condition skips this entirely (US2 scenario 4).
  cat > "$case_dir/.kiln/roadmap/items/2026-04-19-shipped.md" <<'EOF'
---
id: 2026-04-19-shipped
state: shipped
status: shipped
kind: feature
phase: phase-10
prd: docs/features/2026-04-22-baz/PRD.md
pr: 186
shipped_date: 2026-04-22
---
body
EOF
  echo "# baz PRD" > "$case_dir/docs/features/2026-04-22-baz/PRD.md"

  # gh stub — returns 246 for the `foo` and `bar` branches; [] (empty) for `qux`.
  cat > "$case_dir/stubs/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *pr*list*--state*merged*--head*foo*)
    echo "246"
    ;;
  *pr*list*--state*merged*--head*bar*)
    echo "247"
    ;;
  *pr*list*--state*merged*--head*qux*)
    echo ""
    ;;
  *pr*list*--state*merged*--head*baz*)
    # Not reached — item is state=shipped so Check 5 doesn't query.
    echo "186"
    ;;
  *)
    echo ""
    ;;
esac
EOF
  chmod +x "$case_dir/stubs/gh"

  # git stub — overrides only `for-each-ref` and `log`. Other git invocations
  # would be unusual for Check 5 but pass through to system git for safety.
  REAL_GIT="$(command -v git)"
  cat > "$case_dir/stubs/git" <<EOF
#!/usr/bin/env bash
# Test stub for Check 5 — short-circuits 'git log' and 'git for-each-ref' so
# the resolution can be deterministically driven per fixture path.
case "\$1" in
  log)
    # Item (a) PRD path → return a fake merge SHA so for-each-ref runs.
    case "\$*" in
      *docs/features/2026-04-20-foo/PRD.md*) echo "deadbeefcafe1111" ;;
      # Item (b) PRD path → return SHA but for-each-ref returns nothing → heuristic fallback.
      *docs/features/2026-04-21-bar/PRD.md*) echo "deadbeefcafe2222" ;;
      *) echo "" ;;
    esac
    ;;
  for-each-ref)
    case "\$*" in
      *deadbeefcafe1111*) echo "build/foo-20260420" ;;
      *deadbeefcafe2222*) echo "" ;;  # heuristic path
      *) echo "" ;;
    esac
    ;;
  *)
    exec "$REAL_GIT" "\$@"
    ;;
esac
EOF
  chmod +x "$case_dir/stubs/git"
}

# --- Build a per-case runner script (extracted block + helper context) ------
run_case() {
  local case_dir="$1"
  local runner="$case_dir/run-block.sh"
  local notes_file="$case_dir/notes.txt"
  : > "$notes_file"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
set -uo pipefail
PATH="$case_dir/stubs:\$PATH"
H_LIST_ITEMS="plugin-kiln/scripts/roadmap/list-items.sh"
H_PARSE_ITEM="plugin-kiln/scripts/roadmap/parse-item-frontmatter.sh"
NOTES_FILE="$notes_file"
$BLOCK
EOF
  ( cd "$case_dir" && bash "$runner" )
}

# === Scenario: scaffold and run ============================================
echo "--- Scaffolding fixture and running Check 5 ---"
CASE="$TMP/case"
scaffold_case "$CASE"
OUT="$(run_case "$CASE")"
NOTES="$(cat "$CASE/notes.txt")"

echo "--- stdout ---"
echo "$OUT"
echo "--- notes ---"
echo "$NOTES"
echo "---"

# (a) ref-walk drift — pr=#246 + resolution=ref-walk + fix line.
assert "(a) ref-walk drift row contains pr=#246 + resolution=ref-walk" \
  bash -c "echo '$OUT' | grep -qE '^\[drift\] 2026-04-20-refwalk state=distilled .*pr=#246 resolution=ref-walk\$'"
assert "(a) ref-walk drift row followed by fix line" \
  bash -c "echo '$OUT' | grep -qE '^  fix: bash plugin-kiln/scripts/roadmap/update-item-state.sh .*2026-04-20-refwalk\\.md shipped --status shipped\$'"

# (b) heuristic-fallback drift — pr=#247 + resolution=heuristic.
assert "(b) heuristic-fallback drift row contains resolution=heuristic" \
  bash -c "echo '$OUT' | grep -qE '^\[drift\] 2026-04-21-heuristic state=specced .*pr=#247 resolution=heuristic\$'"
assert "(b) heuristic branch is build/bar-20260421 (derived from PRD path)" \
  bash -c "echo '$OUT' | grep -qE 'branch=build/bar-20260421'"
assert "(b) heuristic-fallback emits Notes addendum (R-2)" \
  bash -c "echo '$NOTES' | grep -qE '^note: 2026-04-21-heuristic resolved via heuristic build-branch fallback \\(R-2\\)\\.\$'"

# (c) NFR-004: empty prd → no drift row.
assert "(c) item with empty prd: → NO drift row (NFR-004)" \
  bash -c "! echo '$OUT' | grep -qE '\\[drift\\] 2026-04-22-noprd'"

# (d) gh returns [] → no drift row (already-shipped pattern).
assert "(d) gh pr list returning [] → NO drift row" \
  bash -c "! echo '$OUT' | grep -qE '\\[drift\\] 2026-04-23-nopr'"

# (e) state=shipped → no drift row (Check 5 entry condition).
assert "(e) state=shipped item → NO drift row (Check 5 entry condition)" \
  bash -c "! echo '$OUT' | grep -qE '\\[drift\\] 2026-04-19-shipped'"

# Notes addendum scoping — only the heuristic case emits a note.
NOTE_COUNT="$(printf '%s\n' "$NOTES" | grep -cE '^note: ' || true)"
assert "exactly 1 heuristic notes addendum emitted" \
  bash -c "[ '$NOTE_COUNT' = '1' ]"

# --- Tally ------------------------------------------------------------------
echo
echo "PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  echo "FAIL: $FAIL assertion(s) failed"
  exit 1
fi
echo "PASS"
