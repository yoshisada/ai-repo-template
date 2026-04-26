#!/usr/bin/env bash
# classify-description.sh — cross-surface routing + kind auto-detection heuristic
#
# FR-014  / PRD FR-014:  cross-surface routing (roadmap | issue | feedback | ambiguous)
# FR-014a / PRD FR-014a: within-roadmap kind detection
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.9 + §4 + §5
#
# Usage:   classify-description.sh <description>
# Output:  stdout = JSON {"surface": "roadmap"|"issue"|"feedback"|"ambiguous",
#                         "kind": <string|null>, "confidence": "high"|"medium"|"low",
#                         "alternatives": [<string>...]}
# Exit:    0 on success

set -u

DESC="${1:-}"

if [ -z "$DESC" ]; then
  printf '{"surface":"ambiguous","kind":null,"confidence":"low","alternatives":["roadmap","issue","feedback"]}\n'
  exit 0
fi

# Lower-case + trim for matching
lc="$(printf '%s' "$DESC" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')"

# --- §5 cross-surface routing (runs first) ------------------------------------
# These patterns are evaluated as case-insensitive regex via shell =~.
# Order matters: specific wins over general.

surface=""
confidence=""

# Strong tactical cue: explicit failure words. "product-intent verb" must
# appear at the START of the description to count — otherwise "the build is broken"
# would incorrectly shadow the failure cue via the noun "build".
if [[ "$lc" =~ (broken|crashes|hangs|doesn\'t\ work|does\ not\ work|fails|errors\ out|wrong\ output|stuck) ]]; then
  if ! [[ "$lc" =~ ^(add|build|investigate|prove|disprove|we\ will\ not) ]]; then
    surface="issue"; confidence="high"
  fi
fi

# Weak tactical cue: "slow" alone → issue medium confidence if still unset
if [ -z "$surface" ] && [[ "$lc" =~ (^|\ )slow($|\ ) ]]; then
  if ! [[ "$lc" =~ ^(add|build|investigate|reduce|improve) ]]; then
    surface="issue"; confidence="medium"
  fi
fi

# Strategic cue: "should" / direction / mission
if [ -z "$surface" ] && [[ "$lc" =~ (should|direction|mission|architecture|scope|ergonomics) ]]; then
  if ! [[ "$lc" =~ ^(add|build|investigate) ]]; then
    surface="feedback"; confidence="medium"
  fi
fi

# Product-intent cue: explicit build/investigate/non-goal/critique framing
if [ -z "$surface" ] && [[ "$lc" =~ ^(add|build|investigate|prove|disprove|we\ will\ not|we\ won\'t|kiln\ (should|uses|produces|requires|forces)) ]]; then
  surface="roadmap"; confidence="high"
fi

# Weak roadmap cue: "add", "build", "investigate", "prove", "disprove" anywhere
if [ -z "$surface" ] && [[ "$lc" =~ (^|\ )(add|build|investigate|prove|disprove)(\ |$) ]]; then
  surface="roadmap"; confidence="medium"
fi

# Fallback
if [ -z "$surface" ]; then
  surface="ambiguous"; confidence="low"
fi

# --- §4 kind auto-detection (only runs when surface = roadmap or ambiguous) ---
kind="null"

if [ "$surface" = "roadmap" ] || [ "$surface" = "ambiguous" ]; then
  # Critique — strongest match
  if [[ "$lc" =~ (too\ many|too\ few|too\ slow|too\ expensive|broken\ compared|worse\ than|compared\ to|kiln\ (uses|produces|requires|forces)\ [a-z\ ]*(too|more|less)) ]]; then
    kind="critique"
  elif [[ "$lc" =~ ^(investigate|research|spike|explore|figure\ out) ]]; then
    kind="research"
  elif [[ "$lc" =~ ^(we\ will\ not|we\ won\'t|don\'t\ |never\ |no\ [a-z]+\ in\ v[0-9]) ]]; then
    kind="non-goal"
  elif [[ "$lc" =~ ^(constraint:|always\ [a-z]+|must\ always|always\ must) ]]; then
    kind="constraint"
  elif [[ "$lc" =~ ^(milestone:|reached|completed\ phase) ]]; then
    kind="milestone"
  elif [[ "$lc" =~ (achieve|reduce|increase|improve\ [a-z]+\ by) ]]; then
    kind="goal"
  else
    kind="feature"
  fi
fi

# Build alternatives list for ambiguous / low
if [ "$surface" = "ambiguous" ]; then
  alts='["roadmap","issue","feedback"]'
else
  alts='[]'
fi

# --- T008 / FR-013 / FR-014 / FR-016 / contracts §4 (research-first-completion):
# comparative-improvement signal-word detection with axis inference. Adds an
# OPTIONAL research_inference key to the output JSON when ANY signal matches.
# When NO signal matches, the key is OMITTED entirely (NOT null, NOT {}) —
# false-negative recovery is structural (NFR-006 sibling).

# Word match: case-insensitive whole-word. Use python3 for robust regex
# (POSIX awk's word boundaries differ across BSD vs GNU). The classifier is
# already a small bash script; one python3 invocation is acceptable overhead
# for the inference layer.
RESEARCH_INFERENCE=$(python3 - "$DESC" <<'PY'
import json
import re
import sys

desc = sys.argv[1]

# FR-013 + FR-014 signal-word table. Each tuple: (regex pattern as
# whole-word match, list of axes inferred). Order matters for first-match
# bookkeeping but final emission is set-union deduplicated by metric.
#
# Whole-word boundaries: literal pattern is wrapped with (?<!\w) ... (?!\w)
# to handle non-ASCII safely. Multi-word phrases are matched with literal
# spaces — boundaries on outermost tokens.
TABLE = [
    # latency / time
    (r"faster",            [{"metric": "time", "direction": "lower"}]),
    (r"slower",            [{"metric": "time", "direction": "lower"}]),
    (r"latency",           [{"metric": "time", "direction": "lower"}]),
    # cost + tokens
    (r"cheaper",           [{"metric": "cost", "direction": "lower"}, {"metric": "tokens", "direction": "lower"}]),
    (r"more expensive",    [{"metric": "cost", "direction": "lower"}, {"metric": "tokens", "direction": "lower"}]),
    (r"expensive",         [{"metric": "cost", "direction": "lower"}, {"metric": "tokens", "direction": "lower"}]),
    (r"cost",              [{"metric": "cost", "direction": "lower"}, {"metric": "tokens", "direction": "lower"}]),
    # tokens-only
    (r"tokens",            [{"metric": "tokens", "direction": "lower"}]),
    (r"smaller",           [{"metric": "tokens", "direction": "lower"}]),
    (r"concise",           [{"metric": "tokens", "direction": "lower"}]),
    (r"verbose",           [{"metric": "tokens", "direction": "lower"}]),
    # accuracy
    (r"accurate",          [{"metric": "accuracy", "direction": "equal_or_better"}]),
    (r"wrong",             [{"metric": "accuracy", "direction": "equal_or_better"}]),
    (r"regression",        [{"metric": "accuracy", "direction": "equal_or_better"}]),
    # output_quality (with FR-016 warning)
    (r"clearer",           [{"metric": "output_quality", "direction": "equal_or_better"}]),
    (r"better-structured", [{"metric": "output_quality", "direction": "equal_or_better"}]),
    (r"more actionable",   [{"metric": "output_quality", "direction": "equal_or_better"}]),
    # signal-only (no axis-inference; emit needs_research:true with rationale)
    (r"compare to",        []),
    (r"versus",            []),
    (r"vs ",               []),
    (r"better than",       []),
    (r"improve",           []),
    (r"optimize",          []),
    (r"efficient",         []),
    (r"degradation",       []),
    (r"reduce",            []),
    (r"increase",          []),
]

matched_signals = []
proposed_axes = []
seen_metrics = set()

for pat, axes in TABLE:
    # Whole-word, case-insensitive. We use a positive boundary regex.
    # For multi-word phrases, the trailing space in `vs ` is preserved
    # by the user's pattern.
    if re.search(r"(?<!\w)" + re.escape(pat) + r"(?!\w)", desc, re.IGNORECASE):
        matched_signals.append(pat.strip())
        for axis in axes:
            if axis["metric"] not in seen_metrics:
                seen_metrics.add(axis["metric"])
                proposed_axes.append({**axis, "priority": "primary"})

if not matched_signals:
    sys.stdout.write("")
    sys.exit(0)

# FR-016: when output_quality is in proposed axes, the rationale gains a
# verbatim warning on a separate line.
rationale = f"matched signal word: {matched_signals[0]}"
if any(a["metric"] == "output_quality" for a in proposed_axes):
    rationale += "\n(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)"

inference = {
    "needs_research": True,
    "matched_signals": matched_signals,
    "proposed_axes": proposed_axes,
    "rationale": rationale,
}
sys.stdout.write(json.dumps(inference, separators=(",", ":")))
PY
)

# Emit JSON. When research_inference is present, append it; otherwise emit
# the original three-key shape.
if [ -n "$RESEARCH_INFERENCE" ]; then
  if [ "$kind" = "null" ]; then
    printf '{"surface":"%s","kind":null,"confidence":"%s","alternatives":%s,"research_inference":%s}\n' "$surface" "$confidence" "$alts" "$RESEARCH_INFERENCE"
  else
    printf '{"surface":"%s","kind":"%s","confidence":"%s","alternatives":%s,"research_inference":%s}\n' "$surface" "$kind" "$confidence" "$alts" "$RESEARCH_INFERENCE"
  fi
else
  if [ "$kind" = "null" ]; then
    printf '{"surface":"%s","kind":null,"confidence":"%s","alternatives":%s}\n' "$surface" "$confidence" "$alts"
  else
    printf '{"surface":"%s","kind":"%s","confidence":"%s","alternatives":%s}\n' "$surface" "$kind" "$confidence" "$alts"
  fi
fi
