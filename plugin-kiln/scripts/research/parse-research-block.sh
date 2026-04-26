#!/usr/bin/env bash
# parse-research-block.sh — read research-block fields from any YAML
# frontmatter file (item / issue / feedback / PRD) and emit a deterministic
# JSON projection on stdout.
#
# Spec:     specs/research-first-completion/spec.md (FR-001, FR-002, FR-004)
# Plan:     specs/research-first-completion/plan.md (Decision 3)
# Contract: specs/research-first-completion/contracts/interfaces.md §3 (sibling
#           parser shape for non-PRD surfaces — emits the same canonical
#           projection as parse-prd-frontmatter.sh's research-block subset).
#
# Usage:
#   parse-research-block.sh <file-path>
#
# Stdout: one JSON object on a single line (jq -c -S byte-stable):
#   {
#     "needs_research": true|false|null,
#     "empirical_quality": [...]|null,
#     "fixture_corpus": "..."|null,
#     "fixture_corpus_path": "..."|null,
#     "promote_synthesized": true|false|null,
#     "excluded_fixtures": [...]|null
#   }
#
# Absent fields project as JSON null. Unknown research-block-shaped keys are
# preserved verbatim in the output so the validator can warn on them.
#
# Exit:  0 success (even when no research-block fields present);
#        2 on parse error or unknown enum value (loud-fail per NFR-007).
#
# Reentrant: same input → byte-identical output (NFR-003 sibling).

set -euo pipefail
LC_ALL=C
export LC_ALL

bail() {
  printf 'Bail out! parse error: %s\n' "$1" >&2
  exit 2
}

(( $# == 1 )) || bail "expected 1 arg (file path), got $#"
FILE="$1"
[[ -f "$FILE" ]] || bail "file not found: $FILE"

python3 - "$FILE" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

# Frontmatter: lines between leading "---" and trailing "---".
m = re.match(r"^﻿?---\r?\n(.*?)\r?\n---\r?\n", text, re.DOTALL)
fm = m.group(1) if m else ""

ALLOWED_METRIC = {"accuracy", "tokens", "time", "cost", "output_quality"}
ALLOWED_DIR = {"lower", "higher", "equal_or_better"}
ALLOWED_PRI = {"primary", "secondary"}
ALLOWED_FIXTURE_CORPUS = {"synthesized", "declared", "promoted"}

def bail(msg):
    sys.stderr.write(f"Bail out! parse error: {msg}\n")
    sys.exit(2)

def strip_quotes(s):
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    return s

def parse_bool(s):
    s = strip_quotes(s).lower()
    if s == "true":
        return True
    if s == "false":
        return False
    return None

# ---- needs_research ----
needs_research = None
mn = re.search(r"^needs_research:\s*(.+?)\s*$", fm, re.MULTILINE)
if mn:
    val = strip_quotes(mn.group(1).strip())
    if val == "":
        needs_research = None
    else:
        b = parse_bool(val)
        if b is None:
            bail(f"needs_research must be true|false (got: {val})")
        needs_research = b

# ---- promote_synthesized ----
promote_synthesized = None
mp = re.search(r"^promote_synthesized:\s*(.+?)\s*$", fm, re.MULTILINE)
if mp:
    val = strip_quotes(mp.group(1).strip())
    if val == "":
        promote_synthesized = None
    else:
        b = parse_bool(val)
        if b is None:
            bail(f"promote_synthesized must be true|false (got: {val})")
        promote_synthesized = b

# ---- fixture_corpus ----
fixture_corpus = None
mfc = re.search(r"^fixture_corpus:\s*(.+?)\s*$", fm, re.MULTILINE)
if mfc:
    val = strip_quotes(mfc.group(1).strip())
    if val != "":
        if val not in ALLOWED_FIXTURE_CORPUS:
            bail(f"unknown fixture_corpus: {val} (allowed: synthesized|declared|promoted)")
        fixture_corpus = val

# ---- fixture_corpus_path ----
fixture_corpus_path = None
mfp = re.search(r"^fixture_corpus_path:\s*(.+?)\s*$", fm, re.MULTILINE)
if mfp:
    val = strip_quotes(mfp.group(1).strip())
    if val != "":
        if val.startswith("/"):
            bail(f"fixture-corpus-path-must-be-relative: {val}")
        fixture_corpus_path = val

# ---- empirical_quality ----
empirical_quality = None

# Pre-extract rubric values (FR-010 of plan-time-agents — preserve verbatim).
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
    if rest == "":
        empirical_quality = None
    elif rest == "[]":
        empirical_quality = []
    elif rest.startswith("["):
        # Inline-flow. Accumulate following lines if needed for balanced brackets.
        lines = fm_for_parse.splitlines()
        flow = rest
        for i, ln in enumerate(lines):
            if re.match(r"^empirical_quality:\s*\[", ln):
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

        def quote_values(s):
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

            rubric_raw = item.get("rubric")
            rubric_value = None
            if isinstance(rubric_raw, str):
                ph = re.match(r"^__KILN_RUBRIC_PH_(\d+)__$", rubric_raw)
                if ph:
                    idx = int(ph.group(1))
                    if 0 <= idx < len(_rubric_placeholders):
                        rubric_value = _rubric_placeholders[idx]
                else:
                    rubric_value = rubric_raw

            if rubric_value is not None:
                projected["rubric"] = rubric_value

            out.append(projected)
        empirical_quality = out
    else:
        bail("empirical_quality: only inline-flow shape `[...]` supported in v1")

# ---- excluded_fixtures ----
excluded_fixtures = None
mx = re.search(r"^excluded_fixtures:\s*(.*)$", fm, re.MULTILINE)
if mx:
    rest = mx.group(1).rstrip()
    if rest == "":
        excluded_fixtures = None
    elif rest == "[]":
        excluded_fixtures = []
    elif rest.startswith("["):
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

# ---- detect unknown research-block-shaped keys (forward to validator's
# heuristic). We pass through any top-level frontmatter key whose name
# contains research-related substrings AND is not a known schema key. This
# lets the validator warn-but-pass on typos like `needs_reearch:`.
known_keys = {
    "needs_research", "empirical_quality", "fixture_corpus",
    "fixture_corpus_path", "promote_synthesized", "excluded_fixtures",
}
research_re = re.compile(r"(?i)research|empirical|axis|axes|fixture|corpus|metric|direction|rubric|measure|baseline|candidate|gate|regress")

extra = {}
for line in fm.splitlines():
    mk = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):", line)
    if mk:
        k = mk.group(1)
        if k not in known_keys and research_re.search(k):
            extra[k] = True

projection = {
    "needs_research": needs_research,
    "empirical_quality": empirical_quality,
    "fixture_corpus": fixture_corpus,
    "fixture_corpus_path": fixture_corpus_path,
    "promote_synthesized": promote_synthesized,
    "excluded_fixtures": excluded_fixtures,
}
# Surface unknown research-block-shaped keys so the validator can emit warnings.
for k in extra:
    projection[k] = True

sys.stdout.write(json.dumps(projection, sort_keys=True, separators=(",", ":")) + "\n")
PY
