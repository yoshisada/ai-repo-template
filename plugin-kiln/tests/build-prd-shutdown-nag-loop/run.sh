#!/usr/bin/env bash
# SC-003 / FR-010 — build-prd Step 6 shutdown-nag loop fixture.
#
# Spec:    specs/escalation-audit/spec.md (US3 acceptance scenarios 1..5)
# Contract: specs/escalation-audit/contracts/interfaces.md §B.1 + §D.3
#
# Substrate carve-out (B-1, documented in specs/escalation-audit/blockers.md):
#   Full /loop integration test is deferred — wheel-hook-bound substrate not
#   yet shipped. FR-010 verifies the contract via direct text/grep assertions
#   on plugin-kiln/skills/kiln-build-prd/SKILL.md Step 6 body. When the live
#   substrate lands, a follow-on plugin-kiln/tests/build-prd-shutdown-nag-loop-live/
#   fixture will exercise the live ScheduleWakeup chain.
#
# What this fixture asserts (the four §B.1 verification regex patterns + the
# tick-body contract elements + the sub-section anchor):
#   - "### 3a. Shutdown-nag loop (FR-007..FR-009, NFR-005)" anchor present
#   - ScheduleWakeup invocation with delaySeconds: 60
#   - KILN_SHUTDOWN_NAG_MAX_TICKS env-var override mentioned
#   - TaskStop force-shutdown call documented
#   - "team-empty" self-termination action documented
#   - re-poke + force-shutdown + already-terminated diagnostic actions present
#   - autonomous-loop-dynamic prompt sentinel referenced (matches /loop dynamic-mode contract)
#   - B-1 substrate gap documented inline
#
# Invoke: bash plugin-kiln/tests/build-prd-shutdown-nag-loop/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugin-kiln/skills/kiln-build-prd/SKILL.md"

[[ -f "$SKILL_MD" ]] || { echo "FAIL: SKILL.md missing at $SKILL_MD"; exit 2; }

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

# --- Extract Step 6 body up through the next H2 ----------------------------
awk '
  /^## Step 6:/ { in_section = 1 }
  in_section && /^## [^S]/ && !/^## Step 6:/ { in_section = 0 }
  in_section
' "$SKILL_MD" > "$TMP/step6.md"

[[ -s "$TMP/step6.md" ]] || { echo "FAIL: could not extract Step 6 body from SKILL.md"; exit 2; }

# Extract just the 3a sub-section for tighter scoping (sub-section ends at
# the next "### " heading OR the next "## " heading).
awk '
  /^### 3a\. Shutdown-nag loop/ { in_block = 1; print; next }
  in_block && /^### / { in_block = 0 }
  in_block && /^## / { in_block = 0 }
  in_block { print }
' "$SKILL_MD" > "$TMP/3a.md"

[[ -s "$TMP/3a.md" ]] || { echo "FAIL: could not extract 3a sub-section from SKILL.md"; exit 2; }

# === Anchor: sub-section header ============================================
assert 'sub-section "### 3a. Shutdown-nag loop (FR-007..FR-009, NFR-005)" present in Step 6' \
  grep -qE '^### 3a\. Shutdown-nag loop \(FR-007\.\.FR-009, NFR-005\)$' "$TMP/step6.md"

# === The four §B.1 verification regex patterns =============================
# Pattern 1: ScheduleWakeup with delaySeconds: 60
assert 'ScheduleWakeup invocation with delaySeconds: 60 (§B.1 pattern 1)' \
  grep -qE 'ScheduleWakeup\(\{[^}]*delaySeconds:[[:space:]]*60' "$TMP/3a.md"

# Pattern 2: KILN_SHUTDOWN_NAG_MAX_TICKS env-var override
assert 'KILN_SHUTDOWN_NAG_MAX_TICKS env-var override documented (§B.1 pattern 2)' \
  grep -qE 'KILN_SHUTDOWN_NAG_MAX_TICKS' "$TMP/3a.md"

# Pattern 3: TaskStop force-shutdown
assert 'TaskStop force-shutdown call documented (§B.1 pattern 3)' \
  grep -qE 'TaskStop' "$TMP/3a.md"

# Pattern 4: team-empty self-termination
assert 'team-empty self-termination action documented (§B.1 pattern 4)' \
  grep -qE 'team-empty' "$TMP/3a.md"

# === Tick-body / diagnostic action vocabulary ==============================
assert 're-poke action emitted in diagnostic vocabulary' \
  grep -qE 'action=re-poke' "$TMP/3a.md"

assert 'force-shutdown action emitted in diagnostic vocabulary' \
  grep -qE 'action=force-shutdown' "$TMP/3a.md"

assert 'already-terminated action documented (NFR-005 idempotency)' \
  grep -qE 'action=already-terminated' "$TMP/3a.md"

assert '10-tick-timeout reason emitted on force-shutdown (FR-009)' \
  grep -qE '10-tick-timeout' "$TMP/3a.md"

# === /loop dynamic-mode prompt sentinel =====================================
assert 'autonomous-loop-dynamic prompt sentinel referenced (§B.1)' \
  grep -qE 'autonomous-loop-dynamic' "$TMP/3a.md"

# === Substrate gap (B-1) documented inline =================================
assert 'B-1 substrate gap documented inline' \
  grep -qE 'B-1' "$TMP/3a.md"

assert 'substrate-gap section references deferred /loop integration test' \
  grep -qE 'integration test.*deferred|deferred.*integration test' "$TMP/3a.md"

# === Tally =================================================================
echo
echo "PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  echo "FAIL: $FAIL assertion(s) failed"
  exit 1
fi
echo "PASS"
