---
type: mistake
date: 2026-04-24
status: fixed
made_by: claude-opus-4-7
assumption: "I assumed wheel workflow shapes needed a fallback rendering plan without checking the workflow JSON schema."
correction: "The wheel workflow JSON uses explicit `context_from: []` arrays to name parent edges, making the DAG literal data that any directed-graph library handles trivially."
severity: minor
tags:
  - mistake/assumption
  - topic/roadmap-interview
  - framework/wheel
---

# Hedged on graph-rendering risk without reading the workflow spec

## What happened

While walking the user through the `/kiln:kiln-roadmap` adversarial interview for a "wheel workflow visualizer (static HTML)" item, I composed Q8 ("what breaks if assumptions don't hold?") as an elaborate fallback plan — "if the graph lib can't render cycles or deeply nested teams, fallback is a collapsible JSON-tree view." I did this without first checking whether wheel's workflow JSON actually produced any shapes that would defeat a standard graph library. The user called it out directly: "start with the assumption we will be able to find a solution…if you are so hesitent check out the spec." One `cat` of `plugin-wheel/workflows/example.json` showed the shape was trivially renderable.

## The assumption

I treated "what if the graph lib can't handle edge cases" as a real risk worth planning around, with no evidence of any such edge cases in wheel. The signal I missed: the spec files (`plugin-wheel/workflows/*.json`, `specs/wheel-*/`) were right there, one grep away. Defensive hedging in an interview feels responsible but produces worse answers than grounded ones.

## The correction

The wheel workflow JSON has explicit structural edges — each step carries a `context_from: []` array naming its parents — so the DAG is literal data, not inference. Any directed-graph library (mermaid, cytoscape, d3-dag) renders it. The check cost one file read. When the user said "check out the spec," they were naming the actual fix: verify before hedging.

## Recovery

Read `plugin-wheel/workflows/example.json`, rewrote Q8 as a confident one-paragraph answer with no fallback plan, presented it to the user; they accepted and the roadmap item was written.

## Prevention for future agents

- When an interview question asks "what breaks if X" and you feel uncertain, read the spec BEFORE proposing a fallback. Hedging without evidence wastes the user's turn and trains weaker reasoning.
- For any wheel-related question, `plugin-wheel/workflows/*.json` and `specs/wheel-*/` are ground truth. Grep them first, answer second.
- In adversarial interviews, give confident suggestions or say "let me check" out loud. Don't paper over uncertainty with hedged fallbacks — it's a tell, and the user will catch it.
