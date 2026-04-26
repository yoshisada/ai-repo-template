#!/usr/bin/env bash
# validate-research-block.sh — shared validation helper for the
# research-block frontmatter schema across four intake surfaces:
# items / issues / feedback / PRD.
#
# Spec:     specs/research-first-completion/spec.md (FR-001, FR-002, FR-003)
# Plan:     specs/research-first-completion/plan.md (Decision 3 — shared helper)
# Contract: specs/research-first-completion/contracts/interfaces.md §2
#
# CLI:
#   validate-research-block.sh <frontmatter-json>
#
# Input is a JSON STRING (NOT a file path) — the projected frontmatter object
# emitted by the appropriate parser (parse-item-frontmatter.sh for items,
# parse-prd-frontmatter.sh for PRDs, sibling parser for issues + feedback).
#
# Output (stdout):
#   {"ok": true|false, "errors": [...], "warnings": [...]}
#
# Exit code: 0 always (validation result is in JSON, not exit code) — matches
# the validate-item-frontmatter.sh precedent.

set -u

FM_JSON="${1:-}"

if [ -z "$FM_JSON" ]; then
  printf '{"ok":false,"errors":["missing frontmatter-json argument"],"warnings":[]}\n'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '{"ok":false,"errors":["jq not available — validator requires jq"],"warnings":[]}\n'
  exit 0
fi

# Validate JSON shape first.
if ! printf '%s' "$FM_JSON" | jq -e . >/dev/null 2>&1; then
  printf '{"ok":false,"errors":["frontmatter argument is not valid JSON"],"warnings":[]}\n'
  exit 0
fi

# Validation rules (contract §2):
#  1. needs_research present → must be true|false.
#  2. empirical_quality[]:
#     - metric ∈ ALLOWED_METRIC
#     - direction ∈ ALLOWED_DIR
#     - priority defaults secondary; if present must be ∈ ALLOWED_PRI
#     - metric:output_quality requires non-empty rubric
#     - duplicate metric in array → error
#  3. fixture_corpus present → must be ∈ ALLOWED_FIXTURE_CORPUS
#  4. fixture_corpus ∈ {declared, promoted} → fixture_corpus_path REQUIRED
#  5. fixture_corpus_path present → must be repo-relative (no leading /)
#  6. fixture_corpus: synthesized AND fixture_corpus_path present → warn
#  7. excluded_fixtures[]: each entry has non-empty path AND non-empty reason
#  8. Unknown research-block-shaped keys → warn-but-pass (warning only)
#  9. needs_research:false → warn (default — omit the key)
# 10. needs_research:true AND fixture_corpus absent → warn (variant pipeline
#     will bail at corpus-load)
#
# Emit JSON via jq for byte-stable, sorted-keys output (jq -c -S precedent).

VALIDATION_JSON=$(printf '%s' "$FM_JSON" | jq -c -S '
  def allowed_metric: ["accuracy","tokens","time","cost","output_quality"];
  def allowed_dir: ["lower","higher","equal_or_better"];
  def allowed_pri: ["primary","secondary"];
  def allowed_fixture_corpus: ["synthesized","declared","promoted"];
  # Known research-block keys (used to flag truly-foreign keys vs known schema).
  def known_research_keys: [
    "needs_research","empirical_quality","fixture_corpus",
    "fixture_corpus_path","promote_synthesized","excluded_fixtures","rubric"
  ];
  # Keys outside the research block (host frontmatter — items / issues /
  # feedback / PRD already-validated keys). Anything not in either set AND
  # whose name suggests research-block intent (substring match, case-insensitive)
  # gets a warning. This is a heuristic — we never error on unknown keys.
  def host_known_keys: [
    "id","title","kind","date","status","phase","state","blast_radius",
    "review_cost","context_cost","derived_from","distilled_date","theme",
    "category","area","severity","prd","promoted_from","roadmap_item",
    "addresses","proof_path","priority","tags","summary","author",
    "implementation_hints","mode","escalation","decision_log","scope",
    "rationale"
  ];

  . as $fm
  | (
      # Errors collection.
      [
        # Rule 1: needs_research bool-shape (only when present).
        ( if ($fm | has("needs_research"))
            and ($fm.needs_research != null)
            and (($fm.needs_research | type) != "boolean")
          then "needs_research must be true|false (got: \($fm.needs_research | tostring))"
          else empty end
        ),

        # Rule 2: empirical_quality[] structure.
        ( if ($fm | has("empirical_quality")) and ($fm.empirical_quality != null)
          then
            ( if ($fm.empirical_quality | type) != "array"
              then "empirical_quality must be a list"
              else empty end
            )
          else empty end
        ),

        # Rule 2a: per-entry metric validation.
        ( ($fm.empirical_quality // []) | to_entries[]
          | .key as $i | .value as $entry
          | if ($entry | type) != "object"
            then "empirical_quality[\($i)] must be a mapping"
            else empty end
        ),

        ( ($fm.empirical_quality // []) | to_entries[]
          | .key as $i | .value as $entry
          | if ($entry | type) == "object"
            then
              ( if (allowed_metric | index($entry.metric // "")) == null
                then "unknown metric: \($entry.metric // "<missing>") (allowed: \(allowed_metric | join("|")))"
                else empty end
              )
            else empty end
        ),

        ( ($fm.empirical_quality // []) | to_entries[]
          | .key as $i | .value as $entry
          | if ($entry | type) == "object"
            then
              ( if (allowed_dir | index($entry.direction // "")) == null
                then "unknown direction: \($entry.direction // "<missing>") (allowed: \(allowed_dir | join("|")))"
                else empty end
              )
            else empty end
        ),

        ( ($fm.empirical_quality // []) | to_entries[]
          | .key as $i | .value as $entry
          | if ($entry | type) == "object" and ($entry | has("priority")) and ($entry.priority != null)
            then
              ( if (allowed_pri | index($entry.priority)) == null
                then "unknown priority: \($entry.priority) (allowed: primary|secondary)"
                else empty end
              )
            else empty end
        ),

        # Rule 2b: output_quality requires rubric.
        ( ($fm.empirical_quality // []) | to_entries[]
          | .value as $entry
          | if ($entry | type) == "object" and ($entry.metric // "") == "output_quality"
            then
              ( if (($entry.rubric // "") | tostring | length) == 0
                then "output_quality-axis-missing-rubric"
                else empty end
              )
            else empty end
        ),

        # Rule 2c: duplicate metric in array.
        ( ($fm.empirical_quality // [])
          | map(select(type == "object") | .metric)
          | (group_by(.) | map(select(length > 1) | .[0]))[]
          | "duplicate metric: \(.)"
        ),

        # Rule 3: fixture_corpus enum.
        ( if ($fm | has("fixture_corpus")) and ($fm.fixture_corpus != null)
            and ((allowed_fixture_corpus | index($fm.fixture_corpus)) == null)
          then "unknown fixture_corpus: \($fm.fixture_corpus) (allowed: synthesized|declared|promoted)"
          else empty end
        ),

        # Rule 4: declared|promoted requires fixture_corpus_path.
        ( if ($fm.fixture_corpus // null) as $fc
            | ($fc == "declared" or $fc == "promoted")
              and (($fm.fixture_corpus_path // "") | tostring | length) == 0
          then "fixture-corpus-path-required-when-declared-or-promoted"
          else empty end
        ),

        # Rule 5: fixture_corpus_path repo-relative.
        ( if ($fm.fixture_corpus_path // null) != null
            and (($fm.fixture_corpus_path | tostring) | startswith("/"))
          then "fixture-corpus-path-must-be-relative: \($fm.fixture_corpus_path)"
          else empty end
        ),

        # Rule 7: excluded_fixtures structure.
        ( if ($fm | has("excluded_fixtures")) and ($fm.excluded_fixtures != null)
            and (($fm.excluded_fixtures | type) != "array")
          then "excluded_fixtures must be a list"
          else empty end
        ),

        ( ($fm.excluded_fixtures // []) | to_entries[]
          | .key as $i | .value as $entry
          | if ($entry | type) != "object"
            then "excluded_fixtures[\($i)] must be a mapping"
            else
              (
                if (($entry.path // "") | tostring | length) == 0
                then "excluded_fixtures[\($i)].path must be non-empty"
                else empty end
              ),
              (
                if (($entry.reason // "") | tostring | length) == 0
                then "excluded_fixtures[\($i)].reason must be non-empty"
                else empty end
              )
            end
        ),

        # promote_synthesized must be bool when present.
        ( if ($fm | has("promote_synthesized"))
            and ($fm.promote_synthesized != null)
            and (($fm.promote_synthesized | type) != "boolean")
          then "promote_synthesized must be true|false (got: \($fm.promote_synthesized | tostring))"
          else empty end
        )
      ]
    ) as $errors
  | (
      # Warnings collection.
      [
        # Rule 6: synthesized + path → warn.
        ( if ($fm.fixture_corpus // null) == "synthesized"
            and (($fm.fixture_corpus_path // "") | tostring | length) > 0
          then "fixture-corpus-path-ignored-with-synthesized: \($fm.fixture_corpus_path)"
          else empty end
        ),

        # Rule 8: unknown research-block-shaped keys.
        # A "research-block-shaped" key is heuristically detected as:
        #   - not in known_research_keys
        #   - not in host_known_keys
        #   - matches a substring suggesting research intent
        ( ($fm | keys_unsorted[]) as $k
          | $k
          | select(
              (known_research_keys | index($k)) == null
              and (host_known_keys | index($k)) == null
              and ($k | test("(?i)research|empirical|axis|axes|fixture|corpus|metric|direction|rubric|measure|baseline|candidate|gate|regress"))
            )
          | "unknown research-block field: \(.)"
        ),

        # Rule 9: needs_research:false discouraged.
        # NOTE: cannot use // operator because (false // null) evaluates to
        # null in jq — false is "falsy". Use has() + value comparison.
        ( if ($fm | has("needs_research")) and ($fm.needs_research == false)
          then "needs_research:false is the default — omit the key"
          else empty end
        ),

        # Rule 10: needs_research:true without fixture_corpus.
        ( if ($fm | has("needs_research")) and ($fm.needs_research == true)
            and (($fm.fixture_corpus // "") | tostring | length) == 0
          then "needs_research:true without fixture_corpus — variant pipeline will bail at corpus-load"
          else empty end
        )
      ]
    ) as $warnings
  | { ok: ($errors | length == 0), errors: $errors, warnings: $warnings }
' 2>/dev/null)

if [ -z "$VALIDATION_JSON" ]; then
  printf '{"ok":false,"errors":["jq validation failed unexpectedly"],"warnings":[]}\n'
  exit 0
fi

printf '%s\n' "$VALIDATION_JSON"
