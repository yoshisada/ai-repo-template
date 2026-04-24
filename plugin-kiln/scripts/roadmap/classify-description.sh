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

# Emit JSON
if [ "$kind" = "null" ]; then
  printf '{"surface":"%s","kind":null,"confidence":"%s","alternatives":%s}\n' "$surface" "$confidence" "$alts"
else
  printf '{"surface":"%s","kind":"%s","confidence":"%s","alternatives":%s}\n' "$surface" "$kind" "$confidence" "$alts"
fi
