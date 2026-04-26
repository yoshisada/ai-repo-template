#!/usr/bin/env bash
# Test: claude-audit-grounded-finding-required
#
# Anchor: FR-014 / SC-004 of claude-audit-quality
#
# Behavioral contract under test:
#   When `/kiln:kiln-claude-audit` runs against a CLAUDE.md that is
#   structurally clean (passes all rubric mechanical rules) but
#   diverges from `.kiln/vision.md` content, the audit MUST emit at
#   least one substance finding whose `match_rule:` reads from
#   `CTX_JSON` (vision.body, roadmap.phases, plugins.list, claude_md.body)
#   AS THE PRIMARY JUSTIFICATION. The finding's Notes bullet MUST
#   contain a one-line `remove-this-citation-and-verdict-changes-because:
#   <reason>` rationale that is non-empty (FR-012). If zero
#   project-context-driven rules fire, a `(no project-context signals
#   fired)` placeholder row MUST appear in the Signal Summary (FR-013).
#
# Strategy — structural-invariant tripwire (per substrate gap B-1):
#   The kiln-test plugin-skill harness can't yet drive a deterministic
#   live audit invocation against a fixture mktemp dir. This fixture
#   asserts the structural invariants in
#   `plugin-kiln/skills/kiln-claude-audit/SKILL.md` and
#   `plugin-kiln/rubrics/claude-md-usefulness.md` that GUARANTEE the
#   grounded-finding behavior at audit time.
#
# Fixture data:
#   `fixtures/CLAUDE.md` — structurally-clean CLAUDE.md.
#   `fixtures/.kiln/vision.md` — vision file whose content the audited
#   CLAUDE.md diverges from. Documentation for the future substrate
#   upgrade; not consumed by run.sh in v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../skills/kiln-claude-audit/SKILL.md"
RUBRIC="$SCRIPT_DIR/../../rubrics/claude-md-usefulness.md"

[[ -f "$SKILL"  ]] || { echo "FAIL: SKILL.md missing at $SKILL" >&2; exit 1; }
[[ -f "$RUBRIC" ]] || { echo "FAIL: rubric missing at $RUBRIC" >&2; exit 1; }

# 1. SKILL.md MUST require a `remove-this-citation-and-verdict-changes-because:`
#    rationale line per CTX_JSON-citing finding (FR-012). The literal
#    rationale-line key MUST appear in SKILL.md as a contract requirement.
if ! grep -qF 'remove-this-citation-and-verdict-changes-because:' "$SKILL"; then
  echo "FAIL: SKILL.md missing literal rationale-line key 'remove-this-citation-and-verdict-changes-because:' (FR-012)" >&2
  exit 1
fi

# 2. SKILL.md MUST forbid decorative correlations as primary
#    justifications (FR-012). Accept "decorative" or "correlation"
#    paired with "forbidden" / "MUST NOT" / "not load-bearing".
if ! grep -qiE 'decorative|correlation' "$SKILL"; then
  echo "FAIL: SKILL.md does not address decorative-correlation prohibition (FR-012)" >&2
  exit 1
fi

# 3. SKILL.md MUST contain the project-context-driven row guarantee
#    (FR-013). Accept any phrasing for the placeholder row.
if ! grep -qF '(no project-context signals fired)' "$SKILL"; then
  echo "FAIL: SKILL.md missing project-context-driven row guarantee placeholder '(no project-context signals fired)' (FR-013)" >&2
  exit 1
fi

# 4. SKILL.md MUST tie the placeholder to "zero rules with non-empty
#    ctx_json_paths fired". Accept paraphrases that pair `ctx_json_paths`
#    with "zero" / "no rules" / "none fired".
if ! grep -qE 'ctx_json_paths.{0,200}(zero|no rules|none fired|empty)' "$SKILL" \
   && ! grep -qE '(zero|no rules|none fired).{0,200}ctx_json_paths' "$SKILL"; then
  echo "FAIL: SKILL.md does not tie '(no project-context signals fired)' placeholder to zero-fired-ctx_json_paths-rules condition (FR-013)" >&2
  exit 1
fi

# 5. Rubric MUST have at least 4 substance rules with non-empty
#    ctx_json_paths (the four substance rules from FR-006..FR-009).
#    The minimum is 4; the grep counts non-empty ctx_json_paths
#    declarations in the substance rules block.
substance_block=$(awk '/^## Substance rules/{flag=1; next} /^## [A-Z]/{if (flag) flag=0} flag' "$RUBRIC")
non_empty_ctx_count=$(grep -cE 'ctx_json_paths: \[[^]]+\]' <<<"$substance_block" || true)
if [[ "$non_empty_ctx_count" -lt 4 ]]; then
  echo "FAIL: rubric has only $non_empty_ctx_count substance rules with non-empty ctx_json_paths (need ≥4 — missing-thesis, missing-loop, missing-architectural-context, scaffold-undertaught)" >&2
  exit 1
fi

# 6. SKILL.md MUST require the Notes section to render substance findings
#    before mechanical findings (FR-010). Accept "substance" near "before"
#    / "first" / "ahead of" / "lead" / "top".
if ! grep -qiE 'substance.{0,80}(before|first|ahead|lead|top|prior)' "$SKILL"; then
  echo "FAIL: SKILL.md does not declare Notes ordering 'substance before mechanical' (FR-010)" >&2
  exit 1
fi

echo "PASS: claude-audit-grounded-finding-required — FR-012 rationale-line key 'remove-this-citation-and-verdict-changes-because:' is contracted; decorative-correlation prohibition present; FR-013 project-context-driven row guarantee placeholder + zero-fired condition wired; ≥4 substance rules with non-empty ctx_json_paths registered; Notes substance-first ordering declared"
