---
derived_from:
  - .kiln/roadmap/items/2026-04-23-cache-embeddings.md
distilled_date: 2026-04-24
theme: caching
---
# Feature PRD: Caching

**Date**: 2026-04-24
**Status**: Draft

## Background

Recently the roadmap surfaced these items in the **current** phase:
2026-04-23-cache-embeddings (feature).

## Problem Statement

Pipeline agents repeatedly compute embeddings for overlapping prompts, wasting tokens and time.

## Goals

- Cache embeddings keyed on prompt hash + model id.
- Invalidate on model version change.

## Requirements

### Functional Requirements

- **FR-001** (from: .kiln/roadmap/items/2026-04-23-cache-embeddings.md): Content-addressed cache at `.wheel/cache/embeddings/<hash>.json`.
- **FR-002** (from: .kiln/roadmap/items/2026-04-23-cache-embeddings.md): Expire entries older than 24h.

## User Stories

As a pipeline operator, I want agents to reuse embedding work so tokens drop.

## Success Criteria

- Embedding-call count drops by 40% on repeat pipeline runs.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Cache embeddings between pipeline agents](.kiln/roadmap/items/2026-04-23-cache-embeddings.md) | .kiln/roadmap/ | item | — | feature / phase:current |
