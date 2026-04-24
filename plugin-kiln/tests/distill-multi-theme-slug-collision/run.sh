#!/usr/bin/env bash
# Test: distill-multi-theme-slug-collision
#
# Validates: FR-017 (multi-theme slug disambiguation + pre-existing committed
# dir skip) — research.md §4 algorithm. Acceptance scenario: US4 scenario 2
# "two themes share date + slug → second directory is suffixed -2 (numeric)
# and the first stays un-suffixed."
#
# Approach: drive `disambiguate-slug.sh` directly with a fixture FEATURES_DIR
# that starts empty, then pre-populate with a committed PRD directory and
# re-run to validate the "skip over committed PRDs" branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISAMBIG="$SCRIPT_DIR/../../scripts/distill/disambiguate-slug.sh"

if [[ ! -x "$DISAMBIG" ]]; then
  echo "FAIL: disambiguate-slug.sh missing or not executable at $DISAMBIG" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Case 1 — fresh fixture: duplicate slug in same run.
# Expected: first stays un-suffixed, second gets -2.
OUT="$(DISTILL_FEATURES_DIR="$TMPDIR" bash "$DISAMBIG" 2026-04-24 coaching coaching lint-fix)"
EXPECTED="2026-04-24-coaching
2026-04-24-coaching-2
2026-04-24-lint-fix"

if [[ "$OUT" != "$EXPECTED" ]]; then
  echo "FAIL case 1: duplicate slug in same run did not produce expected output." >&2
  echo "Expected:" >&2; printf '%s\n' "$EXPECTED" >&2
  echo "Got:"      >&2; printf '%s\n' "$OUT"      >&2
  exit 1
fi

# Case 2 — pre-existing committed PRD directory forces first occurrence to -2.
mkdir -p "$TMPDIR/2026-04-24-coaching"
OUT2="$(DISTILL_FEATURES_DIR="$TMPDIR" bash "$DISAMBIG" 2026-04-24 coaching coaching)"
EXPECTED2="2026-04-24-coaching-2
2026-04-24-coaching-3"

if [[ "$OUT2" != "$EXPECTED2" ]]; then
  echo "FAIL case 2: pre-existing committed dir did not force -2 + -3." >&2
  echo "Expected:" >&2; printf '%s\n' "$EXPECTED2" >&2
  echo "Got:"      >&2; printf '%s\n' "$OUT2"     >&2
  exit 1
fi

# Case 3 — multiple pre-existing committed suffixes: -1 + -2 both exist on
# disk, algorithm must skip past to -3 and -4.
mkdir -p "$TMPDIR/2026-04-24-coaching-2"
OUT3="$(DISTILL_FEATURES_DIR="$TMPDIR" bash "$DISAMBIG" 2026-04-24 coaching coaching)"
EXPECTED3="2026-04-24-coaching-3
2026-04-24-coaching-4"

if [[ "$OUT3" != "$EXPECTED3" ]]; then
  echo "FAIL case 3: multiple pre-existing suffixes did not skip correctly." >&2
  echo "Expected:" >&2; printf '%s\n' "$EXPECTED3" >&2
  echo "Got:"      >&2; printf '%s\n' "$OUT3"     >&2
  exit 1
fi

# Case 4 — input order preserved even when disambiguation rewrites some
# entries. Slugs alpha, alpha, beta, beta, alpha → output must stay in the
# same positional order.
DISTILL_FEATURES_DIR="$(mktemp -d)" OUT4="$(DISTILL_FEATURES_DIR="$(mktemp -d)" bash "$DISAMBIG" 2026-04-24 alpha alpha beta beta alpha)"
EXPECTED4="2026-04-24-alpha
2026-04-24-alpha-2
2026-04-24-beta
2026-04-24-beta-2
2026-04-24-alpha-3"

if [[ "$OUT4" != "$EXPECTED4" ]]; then
  echo "FAIL case 4: interleaved duplicate slugs did not keep input order / correct suffixes." >&2
  echo "Expected:" >&2; printf '%s\n' "$EXPECTED4" >&2
  echo "Got:"      >&2; printf '%s\n' "$OUT4"     >&2
  exit 1
fi

# Case 5 — usage error on bad date.
set +e
BAD_OUT="$(DISTILL_FEATURES_DIR="$TMPDIR" bash "$DISAMBIG" not-a-date coaching 2>/dev/null)"
EC=$?
set -e
if [[ "$EC" -ne 2 ]]; then
  echo "FAIL case 5: bad date should exit 2, got exit=$EC" >&2
  exit 1
fi

echo "PASS: slug disambiguation handles in-run collisions AND pre-existing committed dirs"
