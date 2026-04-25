---
id: 2026-04-25-agent-prompt-includes
title: "Agent prompt-include preprocessor — shared trailing modules across kiln agents"
kind: feature
date: 2026-04-25
status: open
phase: 08-in-flight
state: distilled
blast_radius: feature
review_cost: moderate
context_cost: 1 session
depends_on: []
prd: docs/features/2026-04-25-agent-prompt-composition/PRD.md
implementation_hints: |
  ## Shape

  A small preprocessor that resolves `{insert_<path>.md}` (or equivalent)
  directives in agent `.md` files, expanding them in-place against shared
  modules. User's stated form:

      xxxxxxxxxx {insert_.md}

  Treat the directive as a literal verbatim include — no templating
  variables, no conditionals, no recursion in v1. Shared module content
  is concatenated at the directive's location. KISS — this is `cat`
  with discipline, not Jinja.

  ## Where shared modules live

  Recommend `plugin-kiln/agents/_shared/<name>.md`. Underscore prefix
  so it sorts to the top and is visually distinct from agent files.
  Alternative: `plugin-kiln/templates/agent-modules/<name>.md` if we
  want to keep `agents/` strictly for spawnable agents — defer to
  taste in plan.

  ## Syntax candidates (decide in plan)

    1. `{insert_<path>.md}`           — user's stated form. Compact.
                                        Risk: collides with bash brace
                                        expansion if anyone ever pipes
                                        the file through a shell.
    2. `<!-- @include path.md -->`     — HTML-comment-safe, won't break
                                        markdown rendering. Slightly
                                        verbose. Mirrors mdx-prompt /
                                        POML conventions.
    3. `{{> include path.md }}`        — handlebars-partials shape.
                                        Familiar to web devs.

  Recommend #2 for safety + tooling-friendliness; user's form (#1) is
  fine if we lock down the resolution context. Decide in plan.

  ## Resolution timing

  Two viable points:

    A. **Scaffold-time** in `plugin-kiln/bin/init.mjs` — when consumers
       run `npx @yoshisada/kiln init/update`, init.mjs walks
       `agents/*.md`, resolves directives, writes resolved files to
       the consumer's `.claude/agents/` (or wherever installed agents
       live). Pros: zero runtime cost; resolved file is what Claude
       Code reads. Cons: source-file diff drift if consumers edit
       resolved output.

    B. **Pre-commit / build-time** — a script run from `plugin-kiln/`
       that compiles sources → committed compiled outputs. Same
       discipline as `package-lock.json`. Pros: easy to diff; CI
       can verify `compiled == build(sources)`. Cons: extra commit
       step.

  Recommend hybrid — author sources in `agents/_src/`, compile to
  `agents/<role>.md` via a small build script, commit both, CI
  verifies they match. init.mjs ships the compiled output.

  ## Caching implications (load-bearing)

  Trailing-include shape means: stable agent-identity prefix + stable
  shared trailer = full agent.md is one cacheable unit. The shared
  module is included ONCE per agent at compile time, so each agent's
  system prompt is still a stable string at runtime (no per-spawn
  variability). Anthropic prompt cache treats it as a single ephemeral-
  cache prefix — ideal cache layout. Don't break this by adding
  per-spawn variables to the include path; that's the spawn-time
  injection layer's job (see related item
  2026-04-24-agent-spawn-context-injection-layer).

  ## Distinction from sibling: 2026-04-24-agent-spawn-context-injection-layer

  That item: runtime injection at spawn time, into the Agent tool's
  `prompt` parameter (NOT the system prompt). Per-spawn variable
  bindings, Runtime Environment block.

  This item: build-time include directive into the agent's persistent
  system prompt (`agents/<role>.md` body). Static, no variables.

  These compose: an agent's .md file = (role identity) + {insert
  shared trailer at compile time} → static system prompt; then at
  spawn time, the orchestrator prepends a Runtime Environment block
  to the prompt parameter for per-call context. Two different
  layers, both useful.

  ## Initial scope (v1)

    1. Pick syntax (recommend `<!-- @include path.md -->`).
    2. Write resolver: `plugin-kiln/scripts/agent-includes/resolve.sh`
       (Bash + sed + cat — ~50 lines). Resolves all directives in a
       single pass. NO recursion in v1 (a shared module that itself
       includes another is an error).
    3. Author one shared trailer module:
       `plugin-kiln/agents/_shared/coordination-protocol.md` — the
       SendMessage-relay-results boilerplate that's currently
       duplicated across team-mode agents.
    4. Refactor 2-3 existing kiln agents to use the include directive
       (e.g., qa-engineer.md, prd-auditor.md, debugger.md).
    5. CI check: compiled output matches build(sources).
    6. Document in CLAUDE.md "Active Technologies" + plan.md.

  ## Generalization to other plugins (defer to v2)

  Same preprocessor could resolve directives in `plugin-wheel/agents/`,
  `plugin-shelf/agents/`, etc. v1 is kiln-scoped to bound risk. Path
  semantics ("relative to agent file" vs "relative to plugin root")
  decided in v2 if the value of generalization holds up.

  ## Out of scope for v1

  - Variable substitution in includes (`{insert path.md var=foo}`)
  - Conditional includes (`{if SHELL=bash insert ...}`)
  - Cross-plugin includes (`{insert plugin:wheel/_shared/x.md}`)
  - Recursive includes
  - Live-reload / runtime resolution

  All of the above are tractable v2 features once the v1 directive +
  resolver shape is locked.
---

# Agent prompt-include preprocessor — shared trailing modules across kiln agents

## What

Build a small preprocessor that resolves `{insert_<path>.md}` (or
equivalent) directives in `plugin-kiln/agents/*.md` files. Authors
write `xxxxxxxxxx {insert_path.md}` and the resolver expands the
directive against a shared module at compile time. Result: one
canonical source for trailing prompt content (e.g., the SendMessage
coordination-protocol boilerplate), included into every kiln agent
without copy-paste drift.

## Why now

Several kiln agents already duplicate boilerplate at the bottom of
their .md files (coordination-protocol guidance, citation discipline,
scope-of-action rules). Every time we update one, we either fix all
of them or accept drift. A shared trailing module + an include
directive is the compile-time fix. The 2026-04-25 web research found
no Claude Code-specific tool for this — POML / Priompt / mdx-prompt
exist for the broader ecosystem but none target agent .md files. A
~50-line bash resolver gives kiln this primitive without taking on
a heavyweight DSL dependency.

## Why this shape (vs. the spawn-time injection layer)

The sibling item `2026-04-24-agent-spawn-context-injection-layer`
solves a different problem: per-spawn variable bindings injected
into the `prompt` parameter at runtime. This item solves
"deduplicate static content across agent .md files" at compile time.
The two layers compose cleanly:

    agent.md body = (role identity) + {include shared trailer}     ← THIS ITEM (compile-time)
    spawn prompt  = (Runtime Env block) + (task)                   ← sibling item (runtime)

Both layers are stable strings to the cache; neither breaks the
other's prompt-cache layout.

## Hardest part

Picking the syntax + resolution timing in a way that doesn't paint
us into a corner when v2 adds variables / cross-plugin includes /
conditionals. Recommend HTML-comment-safe `<!-- @include path.md -->`
syntax + scaffold-time resolution via init.mjs, with the option to
move to a hybrid build-time + commit-compiled-output model later.

## Cheaper version

Skip the build/commit dance — resolve directives at scaffold time
only (init.mjs), don't commit compiled outputs. Means consumers
who clone the kiln repo and inspect agent .md sources see the raw
directives, not the resolved content. Trade-off: less diff-friendly
in PRs, but ships in half the lines of code. Recommended v1 if
scope pressure hits.

## Acceptance signal

A kiln agent .md file with `<!-- @include _shared/coordination-
protocol.md -->` at the bottom resolves to a complete agent.md
during scaffold, and 2-3 existing kiln agents are refactored to
use the directive without behavioral regression. CI fails if
sources and compiled outputs drift.
