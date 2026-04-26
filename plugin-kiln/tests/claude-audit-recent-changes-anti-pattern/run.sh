#!/usr/bin/env bash
# Test: claude-audit-recent-changes-anti-pattern
#
# Anchor: FR-019 / SC-005 of claude-audit-quality
#
# Behavioral contract under test:
#   When `/kiln:kiln-claude-audit` runs against a CLAUDE.md containing
#   a literal `## Recent Changes` heading, the substance rule
#   `recent-changes-anti-pattern` MUST fire with `action:
#   removal-candidate` and propose a diff that REPLACES the entire
#   `## Recent Changes` section with the standardized
#   `## Looking up recent changes` pointer block (git log + roadmap
#   phases + ls docs/features/ + /kiln:kiln-next). The proposed-diff
#   body uses a generic `<active-phase>` placeholder per OQ-4 to
#   preserve byte-identity across re-runs (NFR-003).
#
#   Reconciliation (FR-017): when this rule fires, `recent-changes-overflow`
#   is demoted to `keep` in the same audit. When `## Recent Changes` is
#   absent, `recent-changes-overflow` emits no signal at all.
#
# Strategy — structural-invariant tripwire (per substrate gap B-1):
#   The kiln-test plugin-skill harness can't yet drive a deterministic
#   live audit invocation against a fixture mktemp dir. This fixture
#   asserts the structural invariants in
#   `plugin-kiln/rubrics/claude-md-usefulness.md` and
#   `plugin-kiln/skills/kiln-claude-audit/SKILL.md` that GUARANTEE the
#   anti-pattern firing behavior at audit time.
#
# Fixture data:
#   `fixtures/CLAUDE.md` — example input containing `## Recent Changes`.
#   Documentation for the future substrate upgrade; not consumed by
#   run.sh in v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-claude-audit/SKILL.md"
DOCTOR_SKILL="$SCRIPT_DIR/../../skills/kiln-doctor/SKILL.md"
RUBRIC="$SCRIPT_DIR/../../rubrics/claude-md-usefulness.md"

[[ -f "$SKILL"  ]]        || { echo "FAIL: SKILL.md missing at $SKILL" >&2; exit 1; }
[[ -f "$RUBRIC" ]]        || { echo "FAIL: rubric missing at $RUBRIC" >&2; exit 1; }
[[ -f "$DOCTOR_SKILL" ]]  || { echo "FAIL: kiln-doctor SKILL.md missing at $DOCTOR_SKILL" >&2; exit 1; }

# 1. Rubric MUST contain the `recent-changes-anti-pattern` rule entry.
rcap_block=$(awk '/^### recent-changes-anti-pattern/{flag=1; next} /^### /{flag=0} flag' "$RUBRIC")
if [[ -z "$rcap_block" ]]; then
  echo "FAIL: recent-changes-anti-pattern rule entry missing from rubric" >&2
  exit 1
fi

# 2. The rule's frontmatter MUST declare:
#    - signal_type: substance
#    - cost: cheap
#    - action: removal-candidate
#    - match_rule: presence of literal "## Recent Changes" heading
for required in \
    'rule_id: recent-changes-anti-pattern' \
    'signal_type: substance' \
    'cost: cheap' \
    'action: removal-candidate'; do
  if ! grep -qF "$required" <<<"$rcap_block"; then
    echo "FAIL: recent-changes-anti-pattern rule missing required field: $required" >&2
    exit 1
  fi
done
if ! grep -qE 'match_rule:.*Recent Changes' <<<"$rcap_block"; then
  echo "FAIL: recent-changes-anti-pattern match_rule does not reference '## Recent Changes' heading" >&2
  exit 1
fi

# 3. The rubric MUST contain the standardized "## Looking up recent
#    changes" pointer block as the proposed diff body (verbatim).
#    Accept either inside the rule prose (in the rubric) OR in SKILL.md.
pointer_block_anchors=(
  '## Looking up recent changes'
  '`git log --oneline -n 20`'
  '`.kiln/roadmap/phases/<active-phase>.md`'
  '`ls docs/features/`'
  '`/kiln:kiln-next`'
)
for anchor in "${pointer_block_anchors[@]}"; do
  if ! grep -qF "$anchor" "$RUBRIC"; then
    echo "FAIL: rubric does not contain standardized pointer block fragment: $anchor" >&2
    exit 1
  fi
done

# 4. The rubric MUST use the GENERIC `<active-phase>` placeholder
#    (not a literal phase name like `10-self-optimization`) inside
#    the proposed-diff body, per OQ-4 byte-identity reconciliation.
if ! grep -qF 'phases/<active-phase>.md' "$RUBRIC"; then
  echo "FAIL: rubric pointer block does not use generic <active-phase> placeholder (OQ-4 byte-identity guard)" >&2
  exit 1
fi

# 5. Reconciliation (FR-017) — both kiln-claude-audit/SKILL.md AND
#    kiln-doctor/SKILL.md MUST handle:
#    (a) `## Recent Changes` absent → recent-changes-overflow emits no signal
#    (b) `recent-changes-anti-pattern` fired in same audit → demote
#        recent-changes-overflow to `keep`
#
# Strategy: extract a 25-line window around every `recent-changes-overflow`
# mention in each file (avoid long-distance regex repetition counts that
# BSD grep rejects), then assert each window pair contains the absent /
# demote vocabulary at least once across the file.
for f in "$SKILL" "$DOCTOR_SKILL"; do
  basename_f=$(basename "$(dirname "$f")")
  reconciliation_window=$(awk '/recent-changes-overflow/{for (i=NR-12; i<=NR+12; i++) lines[i]=1} {linebuf[NR]=$0} END{for (i in lines) if (linebuf[i]) print linebuf[i]}' "$f")
  if [[ -z "$reconciliation_window" ]]; then
    echo "FAIL: $basename_f/SKILL.md contains zero mentions of recent-changes-overflow" >&2
    exit 1
  fi
  if ! grep -qiE 'absent|absence' <<<"$reconciliation_window"; then
    echo "FAIL: $basename_f/SKILL.md recent-changes-overflow context window does not mention absent-section handling (FR-017a)" >&2
    exit 1
  fi
  if ! grep -qiE 'demote|supersede|keep' <<<"$reconciliation_window"; then
    echo "FAIL: $basename_f/SKILL.md recent-changes-overflow context window does not mention demote/supersede/keep (FR-017b)" >&2
    exit 1
  fi
  if ! grep -qiE 'anti-pattern' <<<"$reconciliation_window"; then
    echo "FAIL: $basename_f/SKILL.md recent-changes-overflow context window does not reference recent-changes-anti-pattern (FR-017b)" >&2
    exit 1
  fi
done

echo "PASS: claude-audit-recent-changes-anti-pattern — rule registered with substance/cheap/removal-candidate/'## Recent Changes' match; standardized pointer block (git log + roadmap phases + ls docs/features + /kiln:kiln-next) present; generic <active-phase> placeholder preserves byte-identity (OQ-4); FR-017 reconciliation handlers in both kiln-claude-audit and kiln-doctor SKILL.md"
