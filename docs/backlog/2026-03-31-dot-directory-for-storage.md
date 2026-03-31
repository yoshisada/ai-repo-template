---
title: "Create .kiln/ directory for workflows, QA, and automation artifacts"
type: feature-request
severity: medium
category: scaffold
source: manual
github_issue: null
status: open
date: 2026-03-31
---

## Description

Create a `.kiln/` directory in consumer projects to store workflow definitions, QA tests (outside the testing framework), and other automation artifacts. This is **not** a replacement for `.specify/` — it exists alongside it.

The purpose of `.kiln/` is to give the app a place to define and store:
- **Workflows** — reusable automation sequences the app can pull from and execute as needed
- **Agent runs & outputs** — logs, results, and artifacts from every agent execution (QA engineer, debugger, auditor, smoke tester, etc.)
- **Issues** — backlog items, bug reports, and improvement ideas (replaces `docs/backlog/`)
- **QA artifacts** — tests and checks that live outside the project's normal test framework (e.g., Playwright scripts from `/qa-pass`, smoke test configs)
- **Progress tracking** — build logs, pipeline state, retrospective outputs
- **Automation definitions** — task templates and reusable patterns the app creates over time to automate recurring work

The key idea: the app itself can create workflows in `.kiln/` and pull from them later to automate tasks on demand.

## Impact

Adds a new directory to the scaffold. Skills that generate QA artifacts, workflows, or automation files would write to `.kiln/` instead of ad-hoc locations. Does not affect `.specify/`, `specs/`, or the existing speckit workflow paths.

## Suggested Fix

- Scaffold `.kiln/` with subdirectories (e.g., `workflows/`, `agents/`, `issues/`, `qa/`, `logs/`)
- Update `init.mjs` to create the directory structure
- Define a workflow format that skills and agents can produce and consume
- Route agent run outputs into `.kiln/agents/` (per-run directories with logs and artifacts)
- Move issue/backlog tracking from `docs/backlog/` into `.kiln/issues/`
- Route QA artifacts (from `/qa-pass`, `/qa-final`, etc.) into `.kiln/qa/`
- Route build/pipeline logs into `.kiln/logs/`
- Update `/report-issue` skill to write to `.kiln/issues/` instead of `docs/backlog/`
- `.gitignore` agent runs, QA test runs, and logs (transient outputs). Track workflow definitions and issues.
