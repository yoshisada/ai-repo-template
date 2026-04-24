---
id: 2026-04-23-cache-embeddings
title: "Cache embeddings between pipeline agents"
kind: feature
date: 2026-04-23
status: open
phase: current
state: in-phase
blast_radius: cross-cutting
review_cost: careful
context_cost: 2 sessions
implementation_hints: |
  Use a content-addressed cache keyed on the agent prompt hash. Store under
  `.wheel/cache/embeddings/<hash>.json`. Expire entries older than 24h.
  Invalidate on model-version change (include model id in hash inputs).
---

# Cache embeddings

Reduce repeated compute across agents in the same pipeline run.
