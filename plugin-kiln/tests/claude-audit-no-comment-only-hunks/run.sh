#!/usr/bin/env bash
# Test: claude-audit-no-comment-only-hunks
#
# Anchor: FR-002 / SC-001 of claude-audit-quality
#
# Behavioral contract under test:
#   When `/kiln:kiln-claude-audit` runs against a CLAUDE.md known to fire
#   the `external/length-density` rule, the audit output MUST contain
#   zero `# ... No diff proposed` lines. Every fired signal produces ONE
#   of: a concrete unified diff, an explicit `inconclusive` with a
#   reference-document reason from the rubric's 3-trigger taxonomy, or a
#   `keep` (load-bearing protection). Comment-only diff hunks are
#   forbidden (FR-001 + FR-002).
#
# Strategy — structural-invariant tripwire (per substrate gap B-1):
#   The kiln-test plugin-skill harness can't yet drive a deterministic
#   live audit invocation in pure shell (the audit is an LLM-powered
#   skill). Until the substrate is upgraded to spawn `claude --print
#   --plugin-dir <path>` against a fixture mktemp dir and parse the
#   output deterministically, this fixture instead asserts the structural
#   invariants in `plugin-kiln/skills/kiln-claude-audit/SKILL.md` and
#   `plugin-kiln/rubrics/claude-md-usefulness.md` that GUARANTEE the
#   no-comment-only-hunks behavior at audit time.
#
# Fixture data:
#   `fixtures/CLAUDE.md` — example input known to fire
#   `external/length-density`. Documentation for the future substrate
#   upgrade; not consumed by run.sh in v1.
#
# This fixture is the same tripwire pattern used by
# distill-multi-theme-basic/run.sh (committed by impl-context-roadmap).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-claude-audit/SKILL.md"
RUBRIC="$SCRIPT_DIR/../../rubrics/claude-md-usefulness.md"

if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: SKILL.md missing at $SKILL" >&2
  exit 1
fi
if [[ ! -f "$RUBRIC" ]]; then
  echo "FAIL: rubric missing at $RUBRIC" >&2
  exit 1
fi

# 1. SKILL.md MUST contain a Step 3.5 output discipline invariant section
#    (FR-001 anchor). The header MAY be renumbered in this PR — accept any
#    `## Step 3\.5` heading that mentions "Output discipline invariant".
if ! grep -qE '^## Step 3\.5.*Output discipline invariant' "$SKILL"; then
  echo "FAIL: Step 3.5 'Output discipline invariant' section missing in SKILL.md (FR-001 anchor)" >&2
  exit 1
fi

# 2. The Step 3.5 invariant MUST explicitly enumerate the three permitted
#    output shapes (diff / inconclusive / keep). Accept any phrasing that
#    names all three.
for shape in "concrete" "inconclusive" "keep"; do
  if ! awk '/^## Step 3\.5/{flag=1; next} /^## (Step [^3]|[A-Z])/{flag=0} flag' "$SKILL" | grep -qiF "$shape"; then
    echo "FAIL: Step 3.5 invariant section does not enumerate output shape: $shape" >&2
    exit 1
  fi
done

# 3. The Step 3.5 section MUST forbid comment-only diff hunks. Accept any
#    phrasing that pairs "comment-only" or "No diff proposed" with a
#    forbidden / not-permitted / MUST-NOT signal.
step35_block=$(awk '/^## Step 3\.5/{flag=1; next} /^## (Step [^3]|[A-Z])/{flag=0} flag' "$SKILL")
if ! grep -qiE 'comment-only|no diff proposed|placeholder' <<<"$step35_block"; then
  echo "FAIL: Step 3.5 invariant does not name the comment-only-hunks anti-pattern" >&2
  exit 1
fi
if ! grep -qiE 'forbid|not permitted|MUST NOT|must not|prohibited' <<<"$step35_block"; then
  echo "FAIL: Step 3.5 invariant does not forbid the anti-pattern" >&2
  exit 1
fi

# 4. The "No diff proposed pending maintainer call" placeholder string
#    MUST NOT appear as live audit output text in the SKILL.md
#    instructions (other than inside the forbidden-list / prohibition
#    prose). Strict rule: the literal phrase MAY appear ONLY adjacent to a
#    "forbidden" / "MUST NOT" / "anti-pattern" marker — count occurrences
#    NOT preceded by such a marker.
hits_total=$(grep -cE 'No diff proposed pending maintainer call|# No diff proposed' "$SKILL" || true)
hits_in_prohibition=$(awk '
  /forbid|MUST NOT|must not|anti-pattern|not permitted|prohibited|FR-001|FR-002|FORBIDDEN/ {window=8}
  window > 0 { print; window-- }
' "$SKILL" | grep -cE 'No diff proposed pending maintainer call|# No diff proposed' || true)
if [[ "$hits_total" -gt "$hits_in_prohibition" ]]; then
  echo "FAIL: 'No diff proposed' placeholder appears in SKILL.md outside a prohibition context ($hits_total total vs $hits_in_prohibition in prohibition windows)" >&2
  exit 1
fi

# 5. Rubric preamble MUST contain the 3-trigger taxonomy that limits
#    `inconclusive` to specific conditions (FR-004 — supports FR-002 by
#    eliminating "expensive editorial" as a punt path).
if ! grep -qE '^##+ When `inconclusive` is legitimate' "$RUBRIC"; then
  echo "FAIL: rubric preamble missing 'When inconclusive is legitimate' section (FR-004)" >&2
  exit 1
fi

echo "PASS: claude-audit-no-comment-only-hunks — Step 3.5 invariant present; comment-only hunks forbidden in skill body; rubric 3-trigger taxonomy in place"
