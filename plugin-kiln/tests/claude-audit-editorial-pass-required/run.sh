#!/usr/bin/env bash
# Test: claude-audit-editorial-pass-required
#
# Anchor: FR-005 / SC-002 of claude-audit-quality
#
# Behavioral contract under test:
#   When `/kiln:kiln-claude-audit` runs against a CLAUDE.md known to
#   contain a paraphrase of an article in `.specify/memory/constitution.md`,
#   the audit MUST emit a `duplicated-in-constitution` finding with
#   `action: duplication-flag` (NOT `inconclusive`). The audit performs
#   the editorial pass in the model's own context — no sub-LLM call,
#   no "expensive editorial work" punt. `inconclusive` is reserved for
#   the three legitimate triggers in the rubric preamble (FR-004).
#
# Strategy — structural-invariant tripwire (per substrate gap B-1):
#   The kiln-test plugin-skill harness can't yet drive a deterministic
#   live audit invocation against a fixture mktemp dir. This fixture
#   asserts the structural invariants in
#   `plugin-kiln/skills/kiln-claude-audit/SKILL.md` and
#   `plugin-kiln/rubrics/claude-md-usefulness.md` that GUARANTEE the
#   editorial-pass-required behavior at audit time.
#
# Fixture data:
#   `fixtures/CLAUDE.md` — example input that paraphrases a constitution
#   article. `fixtures/.specify/memory/constitution.md` — the reference
#   document the paraphrase is drawn from. Documentation for the future
#   substrate upgrade; not consumed by run.sh in v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-claude-audit/SKILL.md"
RUBRIC="$SCRIPT_DIR/../../rubrics/claude-md-usefulness.md"

[[ -f "$SKILL"  ]] || { echo "FAIL: SKILL.md missing at $SKILL" >&2; exit 1; }
[[ -f "$RUBRIC" ]] || { echo "FAIL: rubric missing at $RUBRIC" >&2; exit 1; }

# 1. Rubric MUST contain the `duplicated-in-constitution` rule with
#    `action: duplication-flag`. The rule's existence is the contract
#    that any constitution-paraphrase fires duplication-flag, not inconclusive.
duplicated_block=$(awk '/^### duplicated-in-constitution/{flag=1} flag; /^### [^d]|^---/{if (flag) {flag=0}}' "$RUBRIC")
if ! grep -qF 'rule_id: duplicated-in-constitution' <<<"$duplicated_block"; then
  echo "FAIL: rule duplicated-in-constitution missing from rubric" >&2
  exit 1
fi
if ! grep -qF 'action: duplication-flag' <<<"$duplicated_block"; then
  echo "FAIL: duplicated-in-constitution rule does not declare action: duplication-flag" >&2
  exit 1
fi
if ! grep -qF '.specify/memory/constitution.md' <<<"$duplicated_block"; then
  echo "FAIL: duplicated-in-constitution rule does not reference .specify/memory/constitution.md" >&2
  exit 1
fi

# 2. Rubric preamble MUST contain the 3-trigger taxonomy that limits
#    `inconclusive` (FR-004). This is the wall against the "expensive
#    editorial" punt path.
preamble_block=$(awk '/^##+ When `inconclusive` is legitimate/{flag=1; next} /^## /{flag=0} flag' "$RUBRIC")
if [[ -z "$preamble_block" ]]; then
  echo "FAIL: rubric preamble missing 'When inconclusive is legitimate' section" >&2
  exit 1
fi
for trigger in "Missing reference document" "Unparseable reference" "External dependency unavailable"; do
  if ! grep -qF "$trigger" <<<"$preamble_block"; then
    echo "FAIL: rubric preamble missing legitimate-inconclusive trigger: $trigger" >&2
    exit 1
  fi
done

# 3. Rubric preamble MUST explicitly call out that "Editorial work feels
#    expensive" is NOT a legitimate trigger. This is the literal anti-punt
#    clause from FR-004 / interfaces §3.
if ! grep -qF '"Editorial work feels expensive" is explicitly NOT a legitimate trigger' "$RUBRIC"; then
  echo "FAIL: rubric preamble missing explicit prohibition of 'editorial work feels expensive' as inconclusive trigger" >&2
  exit 1
fi

# 4. SKILL.md MUST declare that editorial rules execute in the model's
#    own context — no sub-LLM call. This is the FR-003 contract.
if ! grep -qE 'Editorial rules.*executed in the model.s own context.*FR-003' "$SKILL"; then
  echo "FAIL: SKILL.md missing FR-003 anchor 'Editorial rules (executed in the model's own context)'" >&2
  exit 1
fi
if ! grep -qiF 'no sub-LLM call' "$SKILL"; then
  echo "FAIL: SKILL.md does not state 'no sub-LLM call' for editorial rules (FR-003)" >&2
  exit 1
fi

# 5. SKILL.md Step 3.5 invariant section MUST forbid cost / capacity
#    language ("expensive", "deferred", "skipped", "manual review") as
#    inconclusive reasons. This is the FR-001 + FR-005 enforcement —
#    rules can't punt on editorial work via cost language.
step35_block=$(awk '/^## Step 3\.5/{flag=1; next} /^## (Step [^3]|[A-Z])/{flag=0} flag' "$SKILL")
if ! grep -qiE 'expensive|deferred|cost|capacity' <<<"$step35_block"; then
  echo "FAIL: Step 3.5 invariant does not address cost/capacity language as forbidden inconclusive trigger" >&2
  exit 1
fi
if ! grep -qiE 'forbidden|prohibited|MUST NOT|must not' <<<"$step35_block"; then
  echo "FAIL: Step 3.5 invariant does not forbid cost/capacity inconclusive triggers" >&2
  exit 1
fi

echo "PASS: claude-audit-editorial-pass-required — duplicated-in-constitution rule wired with action: duplication-flag; FR-003 'no sub-LLM call' contract present; FR-004 3-trigger taxonomy plus 'editorial work feels expensive' prohibition present; Step 3.5 forbids cost-language inconclusive punts"
