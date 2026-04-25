---
id: 2026-04-24-code-review-team-with-static-analysis
title: "Code-review agent team — senior-merge-bar enforcement with SonarQube and pluggable static analysis integration"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: ~3-4 sessions
---

# Code-review agent team — senior-merge-bar enforcement with SonarQube and pluggable static analysis integration

## Intent

Add the missing "craft review" step to the kiln pipeline. Today the pipeline has `prd-auditor` (compliance: every FR has an impl) and `qa-engineer` (functional: does it work). Neither checks whether the code a human would actually merge without requesting changes — naming, over-engineering, premature abstractions, speculative helpers, test meaningfulness, comment quality, PR-description usefulness.

The vision (`.kiln/vision.md`) commits to autonomous PRs passing a "senior-engineer-would-merge" bar, not just the audit floor. This item adds the pipeline step that enforces that bar.

## Why a team, not a single agent

A single review agent has too much work to do well. The review surface naturally decomposes into specialist concerns:

- **Structure reviewer** — naming, premature abstractions, dead code, removed-but-not-really code (`// deleted` breadcrumbs), helpers that have one caller.
- **Test reviewer** — tests that assert real acceptance vs coverage-chasing, FR-traceability, test-to-impl ratio sanity, test-naming quality.
- **Comment/narrative reviewer** — comments that are load-bearing vs narration, PR description usefulness, commit-message quality.
- **Static-analysis integrator** — runs SonarQube, eslint, semgrep, or any configured analyzer; normalizes findings into the shared review format.
- **Precedent checker** — consumes the precedent-reader helper (see item `2026-04-24-precedent-reader-helper`) to suppress false-positive pushback when the human has previously accepted an idiom the other reviewers flag.

A coordinator (wheel workflow or review-team agent) aggregates findings, deduplicates, and returns a single structured review.

## Pluggable review sources

The team should be **open-ended** — new review sources (other linters, custom checkers, other plugin-provided reviewers) plug in without restructuring the team:

- A shared "review-finding" schema (severity, file, line, message, rule-id, auto-fixable?).
- A manifest (`.kiln/review-sources.json` or similar) listing configured sources.
- Each source is either a shell command that emits the shared schema, an MCP tool, or an agent.
- Static analyzers (SonarQube, eslint, semgrep, pylint, clippy, govet) wire in as "shell command" sources.
- Custom Claude Code plugins that ship their own review logic wire in as "agent" sources.

## External tool integration

- **SonarQube** — explicitly named priority. Consumer sets `SONAR_TOKEN` + `SONAR_HOST`; integrator agent queries the project, normalizes issues to the shared schema, and returns them alongside the in-process reviewers' findings.
- **Other static analysis** — eslint/semgrep/pylint wire in as pluggable sources (see above). The review team doesn't pick favorites; it aggregates whatever is configured.
- **GitHub review UI** — auto-fixable findings become draft suggestions on the PR; substantive findings block and get routed back to the implementer agent (same `qa-engineer` feedback pattern already shipped).

## Interaction with existing pipeline

- Runs **after** `prd-auditor` (compliance baseline) and **before** PR finalization.
- Auto-fixable findings (typos, obvious style issues, dead imports) get applied without human involvement. Substantive findings (premature abstraction, weak test, missing FR reference in a new function) either block for human review or feed back to the implementer agent for another round.
- Outputs a single structured review document (`.kiln/review/<feature>-review.md`) that the PR description links to — so the human reader can see both what the team flagged and what was auto-fixed.

## Dependencies

- **precedent-reader helper** (`2026-04-24-precedent-reader-helper`) — without this, the review team will generate false-positive pushback on idioms the human has previously accepted, producing review fatigue.
- **wheel workflow engine** — the team coordinator naturally fits the existing team-primitives infrastructure (`specs/wheel-team-primitives/`).
- **qa-engineer feedback loop pattern** — reuse the same "route findings back to implementers, wait for fixes, re-check" pattern already shipped; don't invent a new coordination primitive.

## Failure modes to avoid

- **Review-fatigue from false positives.** If the team flags things the human has said are fine, the human starts ignoring reviews. Precedent integration is load-bearing.
- **Coverage-chasing team growth.** Resist adding reviewers who check things that aren't actually in the senior-merge-bar. Every specialist needs a load-bearing reason tied to the vision's quality claim.
- **Static analyzer noise.** SonarQube and friends can produce hundreds of findings on a first run. Integrator must filter to *new* findings on the diff, not the whole codebase, and must respect existing suppression files / baselines.
- **Auto-fix silent drift.** Auto-fixes that touch semantic code (not just formatting) are a trust risk. Start conservative — only apply auto-fixes for reversible, diff-visible changes.

## Success signal

- A pipeline run that previously shipped a PR a human would have requested changes on now ships a PR the human approves as-is — measurable via "human-requested-changes rate on pipeline PRs" trending down.
- SonarQube project score on pipeline-produced code stays within the consumer's configured threshold.
- Review noise rate (human-flagged "this feedback was wrong") stays low — indicating precedent integration is working.
