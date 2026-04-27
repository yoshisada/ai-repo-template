#!/usr/bin/env bash
# plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh
#
# Regression fixture for `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`.
# Citing: SC-002 (specs/merge-pr-and-sc-grep-guidance/spec.md), NFR-002 (zero-behavior-change).
#
# What this proves: running the extracted helper against a snapshot of the
# pre-merge state of PR #189's three derived_from items produces frontmatter
# byte-identical to the post-merge state observed in commit 22a91b10. A
# second invocation against the post-merge state mutates nothing (FR-008
# idempotency).
#
# Pre-snapshot source: 1c55419d^ (the commit BEFORE the manual flip in
# 1c55419d). This is the TRUE pre-merge state — `state: distilled`, no
# `pr:`, no `shipped_date:`. The contract specified `22a91b10^` but that is
# the manually-flipped intermediate state (already `pr: #189`), which would
# short-circuit the helper's idempotency guard and produce no mutation.
# Documented in agent-notes/impl-roadmap-and-merge.md.
#
# Post-snapshot source: 22a91b10 (the canonical auto-flip output —
# `state: shipped`, `pr: 189` at end of frontmatter, `shipped_date: 2026-04-27`
# at end of frontmatter). This is the byte-identity target.
#
# Date stability: the helper uses `date -u +%Y-%m-%d` to stamp `shipped_date:`.
# The fixture stubs `date` via PATH to return 2026-04-27 so the test passes on
# any day, not just today.
set -euo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"

# 1. Scaffold a fake repo root in $TMP with the three pre-merge snapshots and the PRD.
mkdir -p "$TMP/.kiln/roadmap/items"
cp "$HERE/golden/pre/"*.md "$TMP/.kiln/roadmap/items/"
mkdir -p "$TMP/docs/features/2026-04-26-escalation-audit"
cp "$HERE/golden/prd.md" "$TMP/docs/features/2026-04-26-escalation-audit/PRD.md"

# 2. Stub `gh` to return MERGED for the pinned PR number (189). The helper's
#    PR_STATE_JSON probe matches against `--json state,mergedAt`.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Fixture stub: always reports MERGED for any `pr view --json state,*` query.
case "$*" in
  *"--json state"*) echo '{"state":"MERGED","mergedAt":"2026-04-27T06:16:53Z"}'; exit 0 ;;
  *) echo '{}'; exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/gh"

# 3. Stub `date` to pin TODAY=2026-04-27 (the canonical post-merge shipped_date
#    in commit 22a91b10). Falls through to system /bin/date for any other
#    invocation. Required because the helper uses
#    `TODAY="$(date -u +%Y-%m-%d)"` verbatim from Step 4b.5.
cat > "$TMP/bin/date" <<'STUB'
#!/usr/bin/env bash
# Fixture stub: pin TODAY for byte-identity vs commit 22a91b10.
if [ "$*" = "-u +%Y-%m-%d" ]; then
  echo "2026-04-27"
else
  exec /bin/date "$@"
fi
STUB
chmod +x "$TMP/bin/date"

# 4. Run the helper from $TMP, with stubbed gh + date on PATH.
echo "--- First run (expect: items=3 patched=3 already_shipped=0) ---"
( cd "$TMP" && PATH="$TMP/bin:$PATH" \
  bash "$REPO_ROOT/plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh" 189 \
       "docs/features/2026-04-26-escalation-audit/PRD.md" )

# 5. Diff each item against golden post snapshot — MUST be byte-identical.
for item in "$HERE/golden/post/"*.md; do
  base="$(basename "$item")"
  if ! diff -u "$TMP/.kiln/roadmap/items/$base" "$item"; then
    echo "FAIL: $base byte-diff vs golden/post (first run)"
    exit 1
  fi
done

# 6. Re-run the helper; assert idempotency (FR-008 — no further mutation).
echo "--- Second run (expect: items=3 patched=0 already_shipped=3) ---"
( cd "$TMP" && PATH="$TMP/bin:$PATH" \
  bash "$REPO_ROOT/plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh" 189 \
       "docs/features/2026-04-26-escalation-audit/PRD.md" )

for item in "$HERE/golden/post/"*.md; do
  base="$(basename "$item")"
  if ! diff -u "$TMP/.kiln/roadmap/items/$base" "$item"; then
    echo "FAIL: $base byte-diff after idempotent re-run"
    exit 1
  fi
done

echo "PASS"
