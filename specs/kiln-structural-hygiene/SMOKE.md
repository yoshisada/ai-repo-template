# SMOKE: Kiln Structural Hygiene

Codifies the manually-verifiable success criteria for the
`/kiln:kiln-hygiene` skill and the `/kiln:kiln-doctor` 3h subcheck.
Run these against a real repo before merging the feature PR.

## SC-002 — merged-PRD archival catches a real instance (fixture)

**Fixture**: `plugin-kiln/skills/kiln-hygiene/tests/fixtures/fixture-all-rules-fire/`.

Bootstrap:

```bash
# From a scratch worktree:
SCRATCH=$(mktemp -d)
cp -r plugin-kiln/skills/kiln-hygiene/tests/fixtures/fixture-all-rules-fire/* "$SCRATCH/.kiln/issues/"
mkdir -p "$SCRATCH/docs/features/2026-04-01-merged-one" \
         "$SCRATCH/docs/features/2026-04-02-merged-two" \
         "$SCRATCH/docs/features/2026-04-10-unmerged" \
         "$SCRATCH/products/merged-three"
# Create empty PRD stubs so the prd: paths resolve
for p in "$SCRATCH/docs/features/2026-04-01-merged-one/PRD.md" \
         "$SCRATCH/docs/features/2026-04-02-merged-two/PRD.md" \
         "$SCRATCH/docs/features/2026-04-10-unmerged/PRD.md" \
         "$SCRATCH/products/merged-three/PRD.md"; do
  printf '# stub\n' > "$p"
done
cd "$SCRATCH" && /kiln:kiln-hygiene
```

Assertions on the preview:

```bash
PREV=$(ls -1t .kiln/logs/structural-hygiene-*.md | head -1)

# Bundled block with exactly 3 items
grep -Fc '## Bundled: merged-prd-not-archived (3 items)' "$PREV"        # → 1

# Strict-bundle prose verbatim
grep -Fc 'Accept or reject as a unit.' "$PREV"                           # → 1

# Exactly 3 archive-candidate rows for this rule
grep -cE '^\| merged-prd-not-archived \|.+\| archive-candidate \|' "$PREV"  # → 3

# Control is NOT in the bundled diff body
! awk '/^## Bundled: merged-prd-not-archived/,/^## [^B]/' "$PREV" | grep -q 'unmerged-control.md'

# Malformed item is needs-review in the Signal Summary
grep -cE '^\| merged-prd-not-archived \|.+\| needs-review \|.*malformed\.md' "$PREV"   # → 1
```

## SC-003 — gh-unavailable graceful degradation

```bash
# Approach A: strip gh from PATH
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$(dirname $(command -v gh))" | paste -sd: -) \
  /kiln:kiln-hygiene

# Approach B: deauth (dangerous if you'll need gh elsewhere — use Approach A)
GH_TOKEN= /kiln:kiln-hygiene
```

Assertions:

```bash
PREV=$(ls -1t .kiln/logs/structural-hygiene-*.md | head -1)

# Header reports gh unavailable
grep -Fc '**gh availability**: unavailable' "$PREV"                      # → 1

# Notes section contains the exact FR-006 string from contract §9
grep -Fc 'merged-prd-not-archived: gh unavailable — marked inconclusive' "$PREV"  # → 1

# No archive-candidate rows for merged-prd-not-archived
! grep -qE '^\| merged-prd-not-archived \|.+\| archive-candidate \|' "$PREV"

# No bundled block rendered
! grep -q '^## Bundled: merged-prd-not-archived' "$PREV"

# Exit code was 0
echo "exit=$?"                                                            # → exit=0
```

## SC-004 — doctor subcheck under 2s budget

```bash
# Isolate 3h by wrapping a targeted harness that extracts the 3h block only.
# The /usr/bin/time -p shape is required — avoid bash builtin `time` so the
# numeric output is stable across shells.
/usr/bin/time -p bash -c '
  # Inline Step 3h logic (copy from doctor SKILL.md section 3h).
  HYGIENE_DRIFT_COUNT=0
  MANIFEST_PATH=$(find . -path "*/kiln/templates/kiln-manifest.json" 2>/dev/null | head -1)
  [ -z "$MANIFEST_PATH" ] && MANIFEST_PATH=plugin-kiln/templates/kiln-manifest.json
  MANIFEST_DIRS=$(jq -r ".directories | keys[]" "$MANIFEST_PATH" | sed "s:^\./::; s:/*$::")
  TOP_LEVEL_MANIFEST=$(echo "$MANIFEST_DIRS" | awk -F/ "{print \$1}" | sort -u)
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    echo "$TOP_LEVEL_MANIFEST" | grep -Fxq "$dir" && continue
    if grep -RlF "${dir}/" plugin-*/ templates/ 2>/dev/null | head -1 | grep -q . ; then continue; fi
    find "$dir" -maxdepth 0 -type d -mtime +30 | grep -q . || continue
    HYGIENE_DRIFT_COUNT=$((HYGIENE_DRIFT_COUNT + 1))
  done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name .git ! -name node_modules | sed "s:^\./::")
  for art_dir in .kiln/logs .kiln/qa/test-results .kiln/qa/playwright-report .kiln/qa/videos .kiln/qa/traces .kiln/qa/screenshots .kiln/qa/results .kiln/state; do
    [ -d "$art_dir" ] || continue
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      base=$(basename "$file")
      case "$base" in .gitkeep|README.md) continue ;; esac
      if compgen -G ".wheel/state_*.json" >/dev/null 2>&1; then
        if grep -lF "$base" .wheel/state_*.json 2>/dev/null | head -1 | grep -q . ; then continue; fi
      fi
      HYGIENE_DRIFT_COUNT=$((HYGIENE_DRIFT_COUNT + 1))
    done < <(find "$art_dir" -type f -mtime +60 2>/dev/null)
  done
  echo "drift=$HYGIENE_DRIFT_COUNT"
' 2>&1
```

Expected output: `real <= 2.00`. Record the real-time on a fresh
checkout of this repo; check in the measurement with the implementer
notes.

**Implementer measurement (2026-04-23, ai-repo-template at this
branch HEAD)**: recorded in `agent-notes/implementer.md` along with
the raw `time -p` output.

## SC-005 — propose-don't-apply grep

```bash
grep -nE 'sed -i|mv \.kiln/(issues|feedback)/|git mv \.kiln/(issues|feedback)/' \
     plugin-kiln/skills/kiln-hygiene/SKILL.md
# → zero matches
```

## SC-006 — idempotence

```bash
/kiln:kiln-hygiene
sleep 1
/kiln:kiln-hygiene
cd .kiln/logs
PREV2=$(ls -1t structural-hygiene-*.md | sed -n '1p')
PREV1=$(ls -1t structural-hygiene-*.md | sed -n '2p')
diff <(tail -n +2 "$PREV1") <(tail -n +2 "$PREV2")
# → empty diff
```

The single `# Structural Hygiene Audit — <ts>` header line is the
only permitted diff (NFR-002).

## SC-007 — backwards compat

Mask the 3h row (permitted new row) and diff every existing
cleanup/doctor mode against a captured baseline taken on `main`
immediately before merge. See
`plugin-kiln/skills/kiln-hygiene/tests/fixtures/fixture-no-drift/README.md`
for the full bash recipe.

Expected result: every diff empty after excluding the `Structural
hygiene drift` row.

## SC-008 — "This month's leak would have been caught"

**Reproduces the Part B PRD claim** — flagging all 18 stale items
that were manually archived in commit `574f220` (housekeeping sweep).

```bash
SCRATCH=$(mktemp -d)
git worktree add "$SCRATCH" 574f220^
cd "$SCRATCH"
/kiln:kiln-hygiene
PREV=$(ls -1t .kiln/logs/structural-hygiene-*.md | head -1)

# Extract the 18 filenames from the commit-before-sweep state
EXPECTED_FILES=(
  2026-04-02-lobster-workflow-engine-plugin.md
  2026-04-02-ux-evaluator-nested-screenshot-dir.md
  2026-04-03-shelf-note-templates.md
  2026-04-03-shelf-notes-backlinks-tags.md
  2026-04-03-shelf-sync-close-archived-issues.md
  2026-04-03-shelf-sync-docs.md
  2026-04-03-shelf-sync-update-tech-tags.md
  2026-04-04-add-todo-skill.md
  2026-04-04-wheel-branch-subroutine-support.md
  2026-04-04-wheel-cleanup-in-hook.md
  2026-04-04-wheel-list-skill.md
  2026-04-04-wheel-skill-activation.md
  2026-04-07-qa-engineer-test-dedup-efficiency.md
  2026-04-21-add-feedback-tool-and-rename-issue-to-prd.md
  2026-04-21-fix-skill-should-prompt-next-step.md
  2026-04-21-kiln-fix-drop-wheel-plugin-from-recording.md
  2026-04-21-kiln-fix-step7-recorder-stall-teams.md
  2026-04-23-claude-md-audit-and-prune.md
)

MISSING=0
for f in "${EXPECTED_FILES[@]}"; do
  if ! grep -q "$f" "$PREV"; then
    echo "MISSING: $f"
    MISSING=$((MISSING+1))
  fi
done
[ "$MISSING" -eq 0 ] || { echo "SC-008 FAIL: $MISSING/18 items not flagged"; exit 1; }

# Must all be in the bundled archive block (not needs-review)
BUNDLED=$(awk '/^## Bundled: merged-prd-not-archived/,/^## [^B]/' "$PREV")
for f in "${EXPECTED_FILES[@]}"; do
  echo "$BUNDLED" | grep -q "$f" || { echo "SC-008 FAIL: $f not in bundled block"; exit 1; }
done
echo "SC-008 PASS: all 18 items flagged for archive"

git worktree remove "$SCRATCH"
```

**Deferred to auditor**: the live `git worktree` + `/kiln:kiln-hygiene`
invocation is out-of-band for the implementer (requires a clean
worktree + live gh auth). The auditor agent runs this as part of
Task #3 and records the result in the PR description.

## Notes

- Every assertion here is shell-runnable. No LLM-as-judge.
- SC-002, SC-003, SC-006, and SC-007 can run locally against scratch
  fixtures; SC-004 requires a real `time -p` measurement; SC-008
  requires a historical git-checkout dance and is auditor-owned.
- Strings in Notes-section warnings are grep-anchored; contract §9 is
  the single source of truth for their wording.
