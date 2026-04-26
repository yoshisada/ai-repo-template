#!/usr/bin/env bash
# Test: claude-audit-substance
#
# Anchor: FR-011 / SC-003 of claude-audit-quality
#
# Behavioral contract under test:
#   When `/kiln:kiln-claude-audit` runs against a CLAUDE.md that passes
#   all mechanical rules (right length, recent freshness, no enumeration
#   bloat, no migration notice) but contains no vision-pillar reference,
#   the `missing-thesis` substance rule MUST fire (action:
#   `expand-candidate`). The rule reads `CTX_JSON.vision.body`, extracts
#   pillar phrases, pre-filters via grep, and only invokes the editorial
#   pass when the pre-filter returns zero hits (R-1 mitigation).
#
# Strategy — structural-invariant tripwire (per substrate gap B-1):
#   The kiln-test plugin-skill harness can't yet drive a deterministic
#   live audit invocation against a fixture mktemp dir. This fixture
#   asserts the structural invariants in
#   `plugin-kiln/rubrics/claude-md-usefulness.md` and
#   `plugin-kiln/skills/kiln-claude-audit/SKILL.md` that GUARANTEE the
#   `missing-thesis` rule will fire under the documented conditions.
#
# Fixture data:
#   `fixtures/CLAUDE.md` — example structurally-clean CLAUDE.md (passes
#   mechanical rules) with no vision-pillar reference.
#   `fixtures/.kiln/vision.md` — example vision file whose pillar
#   phrases the audited CLAUDE.md fails to mention. Documentation for
#   the future substrate upgrade; not consumed by run.sh in v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-claude-audit/SKILL.md"
RUBRIC="$SCRIPT_DIR/../../rubrics/claude-md-usefulness.md"

[[ -f "$SKILL"  ]] || { echo "FAIL: SKILL.md missing at $SKILL" >&2; exit 1; }
[[ -f "$RUBRIC" ]] || { echo "FAIL: rubric missing at $RUBRIC" >&2; exit 1; }

# 1. Rubric MUST contain the `missing-thesis` rule under a substance
#    rules section.
mt_block=$(awk '/^### missing-thesis/{flag=1; next} /^### |^---/{flag=0} flag' "$RUBRIC")
if [[ -z "$mt_block" ]]; then
  echo "FAIL: missing-thesis rule entry missing from rubric" >&2
  exit 1
fi

# 2. The rule's frontmatter MUST declare:
#    - signal_type: substance
#    - cost: editorial
#    - action: expand-candidate
#    - ctx_json_paths: [vision.body]
for required in \
    'signal_type: substance' \
    'cost: editorial' \
    'action: expand-candidate' \
    'ctx_json_paths: \[vision\.body\]'; do
  if ! grep -qE "$required" <<<"$mt_block"; then
    echo "FAIL: missing-thesis rule missing required field: $required" >&2
    exit 1
  fi
done

# 3. The match_rule MUST mention reading vision.body, extracting pillar
#    phrases, and pre-filtering before invoking the editorial pass
#    (R-1 mitigation).
for fragment in \
    'CTX_JSON.vision.body' \
    'pillar' \
    'pre-filter'; do
  if ! grep -qiF "$fragment" <<<"$mt_block"; then
    echo "FAIL: missing-thesis match_rule does not reference: $fragment" >&2
    exit 1
  fi
done

# 4. SKILL.md MUST execute substance rules at Step 2 (before cheap
#    rubric pass at Step 3) — the FR-015 reorder anchor that ensures
#    substance findings lead the output.
if ! grep -qE '^## Step 2 — Substance pass' "$SKILL"; then
  echo "FAIL: SKILL.md missing Step 2 substance pass section (FR-015)" >&2
  exit 1
fi

# 5. SKILL.md substance pass MUST reference the missing-thesis rule by ID.
step2_block=$(awk '/^## Step 2 — Substance pass/{flag=1; next} /^## /{flag=0} flag' "$SKILL")
if ! grep -qF 'missing-thesis' <<<"$step2_block"; then
  echo "FAIL: SKILL.md Step 2 substance pass does not reference missing-thesis rule" >&2
  exit 1
fi

# 6. The Signal Summary sort MUST rank `signal_type: substance` at 0
#    (top of table) per FR-010 / interfaces §4. Accept any phrasing
#    pairing "substance" with rank 0 / "first" / "leads" / "top".
if ! grep -qE 'substance.{0,40}(rank|first|top|leads|0)' "$SKILL" \
   && ! grep -qE 'signal_type_rank.{0,80}substance.{0,10}0' "$SKILL"; then
  echo "FAIL: SKILL.md does not declare signal_type=substance leads Signal Summary sort (FR-010)" >&2
  exit 1
fi

echo "PASS: claude-audit-substance — missing-thesis rule registered with substance/editorial/expand-candidate/[vision.body]; pre-filter (R-1) documented; Step 2 substance pass executes before cheap rubric pass; substance rank=0 sort key present"
