---
id: 2026-04-23-structured-capture
title: "Structured capture surface for planning"
kind: feature
date: 2026-04-23
status: open
phase: current
state: in-phase
blast_radius: cross-cutting
review_cost: careful
context_cost: 3 sessions
implementation_hints: |
  Root at .kiln/vision.md + .kiln/roadmap/{phases,items}/. Items carry a
  kind field (feature / goal / research / constraint / non-goal / milestone /
  critique) and a state field (planned / in-phase / distilled / specced /
  shipped). Phase lifecycle is single-in-progress.
---

# Structured capture surface for planning

Replace the one-liner `.kiln/roadmap.md` with a typed, phased planning layer.
