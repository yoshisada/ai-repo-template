---
derived_from:
  - .kiln/issues/2026-04-10-1000-already-migrated.md
distilled_date: 2026-04-10
theme: already-migrated
---

# PRD: Already-Migrated Feature

**Date**: 2026-04-10

This PRD is the MIGRATED fixture — it already carries `derived_from:` frontmatter. The backfill subcommand MUST skip it on every invocation (idempotence predicate FR-010 in spec `prd-derived-from-frontmatter`). The harness seed test asserts that running backfill twice produces zero hunks against this file.

## Background

Fixture content. Not consumed by the backfill subcommand; the subcommand only reads the top-20 lines of frontmatter + the `### Source Issues` table.

## Goals

N/A — fixture.

### Source Issues

| # | Issue | Status |
|---|-------|--------|
| 1 | [.kiln/issues/2026-04-10-1000-already-migrated.md](.kiln/issues/2026-04-10-1000-already-migrated.md) | open |
