#!/usr/bin/env bash
# parse-prd-frontmatter.sh — Read empirical_quality / blast_radius /
# excluded_fixtures from a PRD's YAML frontmatter and emit a deterministic
# JSON projection on stdout.
#
# Satisfies: FR-AE-001 (empirical_quality declaration parsing),
#            FR-AE-004 (blast_radius read for rigor lookup),
#            FR-AE-006 (excluded_fixtures read).
# Contract:  specs/research-first-axis-enrichment/contracts/interfaces.md §3.
#
# Usage:
#   parse-prd-frontmatter.sh <prd-path>
#
# Stdout (on success): one JSON object on a single line, jq -c -S byte-stable:
#   {
#     "blast_radius": "isolated",
#     "empirical_quality": [
#       {"metric": "tokens", "direction": "equal_or_better", "priority": "primary"},
#       {"metric": "time", "direction": "lower", "priority": "secondary"}
#     ],
#     "excluded_fixtures": [
#       {"path": "002-flaky", "reason": "..."}
#     ]
#   }
# Absent fields project as JSON null (NOT [] / "") — caller distinguishes
# absent vs empty list via JSON null vs [].
#
# Exit: 0 success (even when fields are absent — null projection is success);
#       2 PRD path missing OR YAML frontmatter malformed OR an enum value is
#         outside its closed vocabulary. Stderr emits `Bail out! parse error: <reason>`.
#
# Reentrant: same input → byte-identical output (NFR-AE-002 sibling).
set -euo pipefail
LC_ALL=C
export LC_ALL

bail() {
  printf 'Bail out! parse error: %s\n' "$1" >&2
  exit 2
}

(( $# == 1 )) || bail "expected 1 arg (prd path), got $#"
prd=$1
[[ -f $prd ]] || bail "prd path not found: $prd"

# Hand-rolled YAML frontmatter parsing via python3 stdlib (re + json). Mirrors
# plugin-wheel/scripts/agents/compose-context.sh precedent — PyYAML is NOT a
# kiln dependency.
#
# Additive validator stanza for FR-010 (research-first-plan-time-agents):
# when an empirical_quality[] entry has metric:output_quality, it MUST also
# carry a non-empty rubric: <string>. The rubric value is preserved
# character-for-character (no normalization, no whitespace trimming). On
# missing/empty rubric this script exits 2 with
# `Bail out! output_quality-axis-missing-rubric: <abs-prd-path>`.
python3 - "$prd" <<'PY'
import json
import os
import re
import sys

prd_path = sys.argv[1]
with open(prd_path, "r", encoding="utf-8") as f:
    text = f.read()

# Frontmatter: lines between leading "---" and trailing "---" at file top.
# Tolerate windows line endings + leading BOM. Empty/missing frontmatter →
# all fields project as null.
m = re.match(r"^﻿?---\r?\n(.*?)\r?\n---\r?\n", text, re.DOTALL)
fm = m.group(1) if m else ""

ALLOWED_BLAST = {"isolated", "feature", "cross-cutting", "infra"}
ALLOWED_METRIC = {"accuracy", "tokens", "time", "cost", "output_quality"}
ALLOWED_DIR = {"lower", "higher", "equal_or_better"}
ALLOWED_PRI = {"primary", "secondary"}
# T004 / FR-004 / NFR-009 / contracts §3 (research-first-completion):
# additive enums for the three new field projections. Existing projections
# (blast_radius / empirical_quality / excluded_fixtures) UNCHANGED in shape
# and exit codes.
ALLOWED_FIXTURE_CORPUS = {"synthesized", "declared", "promoted"}

def bail(msg):
    sys.stderr.write(f"Bail out! parse error: {msg}\n")
    sys.exit(2)

def strip_quotes(s):
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    return s

# --- blast_radius ---
blast_radius = None
mb = re.search(r"^blast_radius:\s*(.+?)\s*$", fm, re.MULTILINE)
if mb:
    val = strip_quotes(mb.group(1))
    if val == "":
        blast_radius = None
    else:
        if val not in ALLOWED_BLAST:
            bail(f"unknown blast_radius: {val} (allowed: isolated|feature|cross-cutting|infra)")
        blast_radius = val

# --- empirical_quality ---
# Two flow-style shapes accepted:
#   1) Inline JSON-ish flow on one line:
#      empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}]
#   2) Block style with `- metric: tokens` etc. — also support nested via single-line dicts.
#
# FR-010 (research-first-plan-time-agents): when an item declares
# `metric: output_quality`, it MUST also carry a non-empty `rubric:` string.
# The rubric value is preserved character-for-character (no normalization).
# To avoid the existing quote_keys/quote_values regexes mangling free-text
# rubric content (which may contain `:`, `,`, etc.), we PRE-EXTRACT each
# rubric value via a placeholder swap, parse the rest of the flow as before,
# and re-substitute verbatim values post-parse.
empirical_quality = None

# Pre-extract rubric values (FR-010): replace `rubric: "..."` and `rubric: '...'`
# with `rubric: __KILN_RUBRIC_PH_<N>__` placeholders that survive flow→JSON
# conversion as ordinary bare tokens. Captured originals are restored verbatim
# after json.loads. This guarantees byte-for-byte rubric preservation per
# contracts/interfaces.md §3.
_rubric_placeholders = []
def _pre_extract_rubric(match):
    val = match.group(1) if match.group(1) is not None else match.group(2)
    _rubric_placeholders.append(val)
    return f'rubric: __KILN_RUBRIC_PH_{len(_rubric_placeholders)-1}__'

fm_for_parse = re.sub(
    r"rubric:\s*(?:\"([^\"]*)\"|'([^']*)')",
    _pre_extract_rubric,
    fm,
)

me = re.search(r"^empirical_quality:\s*(.*)$", fm_for_parse, re.MULTILINE)
if me:
    rest = me.group(1).rstrip()
    if rest == "" or rest == "[]":
        empirical_quality = [] if rest == "[]" else None
    elif rest.startswith("["):
        # Inline-flow. Collect lines until a line that ends with `]` (greedy).
        # For v1 we accept everything on a single line; multi-line flow not required by spec.
        # Convert YAML flow → JSON: keys/values bare strings → quote them.
        flow = rest
        # Append following lines until balanced brackets, just in case author wraps.
        lines = fm_for_parse.splitlines()
        for i, ln in enumerate(lines):
            if re.match(r"^empirical_quality:\s*\[", ln):
                # accumulate until balanced
                buf = ln.split(":", 1)[1].strip()
                depth = buf.count("[") - buf.count("]")
                j = i + 1
                while depth > 0 and j < len(lines):
                    buf += " " + lines[j].strip()
                    depth += lines[j].count("[") - lines[j].count("]")
                    j += 1
                flow = buf
                break

        # Quote bare YAML keys/values to make valid JSON. Match `word:` and
        # `: word` (boundaries on `,` `{` `}` `[` `]`).
        def quote_keys(s):
            return re.sub(r"([{,\s])([A-Za-z_][A-Za-z0-9_]*)\s*:", r'\1"\2":', s)

        def quote_values(s):
            # Replace `: <bare-token>` with `: "<bare-token>"` when the token
            # is not already quoted, not a number, not a structural char.
            return re.sub(r':\s*([A-Za-z_][A-Za-z0-9_-]*)', r': "\1"', s)

        j = quote_keys(flow)
        j = quote_values(j)
        try:
            arr = json.loads(j)
        except Exception as ex:
            bail(f"empirical_quality flow parse: {ex}")
        if not isinstance(arr, list):
            bail("empirical_quality must be a list")
        out = []
        for item in arr:
            if not isinstance(item, dict):
                bail("empirical_quality item must be a mapping")
            metric = item.get("metric")
            direction = item.get("direction")
            priority = item.get("priority", "primary")
            if metric not in ALLOWED_METRIC:
                bail(f"unknown metric: {metric} (allowed: accuracy|tokens|time|cost|output_quality)")
            if direction not in ALLOWED_DIR:
                bail(f"unknown direction: {direction} (allowed: lower|higher|equal_or_better)")
            if priority not in ALLOWED_PRI:
                bail(f"unknown priority: {priority} (allowed: primary|secondary)")

            projected = {"metric": metric, "direction": direction, "priority": priority}

            # FR-010: rubric handling for output_quality axis.
            rubric_raw = item.get("rubric")
            rubric_value = None
            if isinstance(rubric_raw, str):
                ph_match = re.match(r"^__KILN_RUBRIC_PH_(\d+)__$", rubric_raw)
                if ph_match:
                    idx = int(ph_match.group(1))
                    if 0 <= idx < len(_rubric_placeholders):
                        rubric_value = _rubric_placeholders[idx]
                else:
                    # Bare-token rubric (single word, no spaces) — preserved as-is
                    # by quote_values. Acceptable but discouraged; first-real-use
                    # rubrics will be quoted strings.
                    rubric_value = rubric_raw

            if metric == "output_quality":
                # FR-010 loud-failure: rubric required + non-empty.
                if rubric_value is None or rubric_value == "":
                    sys.stderr.write(
                        f"Bail out! output_quality-axis-missing-rubric: {os.path.abspath(prd_path)}\n"
                    )
                    sys.exit(2)
                projected["rubric"] = rubric_value
            elif rubric_value is not None:
                # Non-output_quality axis with rubric — pass through (forward-compat).
                projected["rubric"] = rubric_value

            out.append(projected)
        # Detect duplicate metric.
        seen = set()
        for it in out:
            if it["metric"] in seen:
                bail(f"duplicate metric in empirical_quality: {it['metric']}")
            seen.add(it["metric"])
        empirical_quality = out
    else:
        bail("empirical_quality: only inline-flow shape `[...]` supported in v1")

# --- excluded_fixtures ---
excluded_fixtures = None
mx = re.search(r"^excluded_fixtures:\s*(.*)$", fm, re.MULTILINE)
if mx:
    rest = mx.group(1).rstrip()
    if rest == "" or rest == "[]":
        excluded_fixtures = [] if rest == "[]" else None
    elif rest.startswith("["):
        # Same flow logic as empirical_quality. The reason: field may contain
        # spaces/punctuation — require it to be quoted in source.
        lines = fm.splitlines()
        flow = rest
        for i, ln in enumerate(lines):
            if re.match(r"^excluded_fixtures:\s*\[", ln):
                buf = ln.split(":", 1)[1].strip()
                depth = buf.count("[") - buf.count("]")
                j = i + 1
                while depth > 0 and j < len(lines):
                    buf += " " + lines[j].strip()
                    depth += lines[j].count("[") - lines[j].count("]")
                    j += 1
                flow = buf
                break

        def quote_keys(s):
            return re.sub(r"([{,\s])([A-Za-z_][A-Za-z0-9_]*)\s*:", r'\1"\2":', s)

        # Values: 'path' is bare token; 'reason' MUST be quoted in source.
        def quote_path_value(s):
            return re.sub(r'"path"\s*:\s*([A-Za-z0-9_/\.-]+)', r'"path": "\1"', s)

        j = quote_keys(flow)
        j = quote_path_value(j)
        try:
            arr = json.loads(j)
        except Exception as ex:
            bail(f"excluded_fixtures flow parse: {ex}")
        if not isinstance(arr, list):
            bail("excluded_fixtures must be a list")
        out = []
        for item in arr:
            if not isinstance(item, dict):
                bail("excluded_fixtures item must be a mapping")
            pth = item.get("path")
            reason = item.get("reason", "")
            if not isinstance(pth, str) or pth == "":
                bail("excluded_fixtures.path must be a non-empty string")
            out.append({"path": pth, "reason": str(reason)})
        excluded_fixtures = out
    else:
        bail("excluded_fixtures: only inline-flow shape `[...]` supported in v1")

# T004 / FR-004 / NFR-009 / contracts §3 — three more additive field
# projections: needs_research, fixture_corpus, fixture_corpus_path,
# promote_synthesized. Loud-fail on malformed values (NFR-007). Absent →
# JSON null (matches existing pattern). Backward compat: PRDs without these
# keys produce the existing three-key projection plus four nulls — callers
# that read only the existing keys are unaffected (NFR-001).

def parse_bool(s):
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        s = s[1:-1]
    s = s.lower()
    if s == "true":
        return True
    if s == "false":
        return False
    return None

needs_research = None
mn = re.search(r"^needs_research:\s*(.+?)\s*$", fm, re.MULTILINE)
if mn:
    val = mn.group(1).strip()
    if val != "":
        b = parse_bool(val)
        if b is None:
            bail(f"needs_research must be true|false (got: {val})")
        needs_research = b

fixture_corpus = None
mfc = re.search(r"^fixture_corpus:\s*(.+?)\s*$", fm, re.MULTILINE)
if mfc:
    val = strip_quotes(mfc.group(1))
    if val != "":
        if val not in ALLOWED_FIXTURE_CORPUS:
            bail(f"unknown fixture_corpus: {val} (allowed: synthesized|declared|promoted)")
        fixture_corpus = val

fixture_corpus_path = None
mfp = re.search(r"^fixture_corpus_path:\s*(.+?)\s*$", fm, re.MULTILINE)
if mfp:
    val = strip_quotes(mfp.group(1))
    if val != "":
        if val.startswith("/"):
            bail(f"fixture-corpus-path-must-be-relative: {val}")
        fixture_corpus_path = val

promote_synthesized = None
mps = re.search(r"^promote_synthesized:\s*(.+?)\s*$", fm, re.MULTILINE)
if mps:
    val = mps.group(1).strip()
    if val != "":
        b = parse_bool(val)
        if b is None:
            bail(f"promote_synthesized must be true|false (got: {val})")
        promote_synthesized = b

projection = {
    "blast_radius": blast_radius,
    "empirical_quality": empirical_quality,
    "excluded_fixtures": excluded_fixtures,
    "fixture_corpus": fixture_corpus,
    "fixture_corpus_path": fixture_corpus_path,
    "needs_research": needs_research,
    "promote_synthesized": promote_synthesized,
}

# Sorted-keys JSON, single line — matches `jq -c -S` byte-stability.
sys.stdout.write(json.dumps(projection, sort_keys=True, separators=(",", ":")) + "\n")
PY
