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
python3 - "$prd" <<'PY'
import json
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
empirical_quality = None
me = re.search(r"^empirical_quality:\s*(.*)$", fm, re.MULTILINE)
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
        lines = fm.splitlines()
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
            out.append({"metric": metric, "direction": direction, "priority": priority})
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

projection = {
    "blast_radius": blast_radius,
    "empirical_quality": empirical_quality,
    "excluded_fixtures": excluded_fixtures,
}

# Sorted-keys JSON, single line — matches `jq -c -S` byte-stability.
sys.stdout.write(json.dumps(projection, sort_keys=True, separators=(",", ":")) + "\n")
PY
