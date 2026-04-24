---
last_updated: 2026-04-24
---

# Product Vision

<!--
FR-001 / PRD FR-001: created on first run from template.
Mirrored to Obsidian at <base_path>/<slug>/vision.md via shelf-write-roadmap-note.
Update with `/kiln:kiln-roadmap --vision` (FR-019 / PRD FR-019).
-->

## What we are building

A mostly-autonomous build system for a solo builder (team-ready later) who already uses Claude Code and Obsidian as native infrastructure. You feed it ideas, feedback, issues, and roadmap features; it turns them into working software — researching, specifying, planning, implementing, QA-ing, auditing, and shipping — with minimal human intervention. The unfair shortcut: the system deliberates over accumulated precedent (prior feedback, approved manifest proposals, past decisions, captured mistakes) to decide when to act vs when to escalate — it proceeds when you've already answered the question, and asks only when it doesn't have enough signal. Shipped builds meet a "senior-engineer-would-merge" bar — simple code, meaningful FR-traced tests, sparse load-bearing comments, useful PR descriptions, retros with actual insight — not just the audit floor. A first-class capability is that thinking about the project (ideas, feedback, mistakes, product direction) is captured as structured artifacts that feed the next PRD via `/kiln:kiln-distill`: the loop is the product. The system also captures its own operational failures — AI mistakes become manifest-improvement proposals on the next sync, so templates and skills evolve from evidence, not separate redesign cycles. Current implementation is a suite of five Claude Code plugins — `kiln` (spec-first pipeline), `clay` (idea → repo), `shelf` (Obsidian mirror), `trim` (design↔code sync), `wheel` (workflow engine). Primarily a personal tool, but engineered with enough distribution discipline (portable plugin format, versioned releases, consumer scaffolding, clean install UX) that it installs cleanly for others who find it — because clunky onboarding is a bug.

## What it is not

Not a fully autonomous system that acts without precedent — when it can't infer what you'd want from captured context, it escalates. Not a replacement for human strategic thinking (vision, phase transitions, manifest-proposal approvals, accepting proposed roadmap items — all require explicit "yes"). Not a hosted service — state lives in the repo and a local Obsidian vault; no dashboards-as-service, no cloud-side orchestration. Not a Claude-Code-agnostic agent framework — the thesis depends on Claude Code's hook, Agent, and Skill primitives; other substrates would require abandoning the gates that make the system trustable. Not a spec-less code generator — the 4-gate hook enforcement *is* the product. Not a community-driven roadmap — external feedback is valued but filtered through "does this match real use?"; useless features don't ship just because someone asked. Not a multi-user coordination platform yet — solo-first design, with a deliberate commitment not to paint ourselves into a corner against future team support. Not language-opinionated by principle — today's implementation skews JS/TS/Markdown/Bash out of incremental delivery, but language-agnostic feature design is the target direction.

## How we'll know we're winning

Six-month signals:

- **(a)** An idea captured via `/clay:clay-idea` reaches a reviewed PR via `/kiln:kiln-build-prd` with zero-to-few human interventions along the way, and the PR passes the senior-engineer-merge test — simple code, FR-traced tests, load-bearing comments only, useful description, retro with a real insight.
- **(b)** When the system does interrupt, it's because precedent is genuinely absent — not because a gate was wired to always ask. High-signal escalations, not friction.
- **(c)** The capture surfaces close their loops — items captured in one session become PRDs via `/kiln:kiln-distill` and shipped features in a later session, without hand-coordination.
- **(d)** The self-improvement loop closes — AI mistakes captured in one session become proposed manifest/template edits in a later session, and those edits land.
- **(e)** Hooks reliably gate untraced `src/` edits and `.env` commits in consumer projects — autonomous agents cannot silently drift.
- **(f)** Obsidian (`shelf`) and design (`trim`) mirrors stay in sync without hand-reconciliation.
- **(g)** Install works cleanly — a fresh consumer runs the scaffold and is productive without fighting setup.
- **(h)** External feedback gets filtered — signals that match real use land on the roadmap; hypothetical "wouldn't it be cool" asks don't.

## Guiding constraints

- **Context-informed autonomy** — the system deliberates over precedent (captured feedback, approved proposals, declined non-goals, mistake corrections) before acting. Precedent present → it acts; precedent absent/ambiguous → it escalates.
- **Propose constantly, apply never unilaterally** — self-improvement proposals always route through a human apply step.
- **File-based state** — no services; everything persists in the repo or a configured Obsidian vault so the audit trail is portable and forkable.
- **Spec-first, non-negotiable** — 4-gate hooks enforce spec + plan + tasks + `[X]` before `src/` edits; `/kiln:kiln-fix` is the only spec-less escape hatch and still requires an existing spec.
- **Plugin-workflow portability** — scripts invoked from wheel workflows resolve via `${WORKFLOW_PLUGIN_DIR}`, never repo-relative paths.
- **Quality gates ship with the build** — lint, static analysis, coverage thresholds, full-codebase audit tooling pre-wired; the senior-engineer-merge bar is the target, not the audit floor.
- **Idempotent writes** — generators produce byte-identical output on unchanged inputs so drift is visible in git.
- **Install must not be clunky** — consumer onboarding is a vision-level commitment, not a nice-to-have; breaking changes in the scaffold surface warrant visible version-bumps and migration notes.
