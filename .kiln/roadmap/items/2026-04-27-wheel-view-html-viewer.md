---
id: 2026-04-27-wheel-view-html-viewer
title: "/wheel:wheel-view — HTML viewer for available wheel workflows + kiln feedback-loop docs"
kind: feature
date: 2026-04-27
status: open
phase: 12-loop-and-workflow-design
state: planned
blast_radius: feature
review_cost: moderate
context_cost: 2-3 sessions
depends_on:
  - 2026-04-25-feedback-loop-doc-format
implementation_hints: |
  Skill name: /wheel:wheel-view. Ships with the wheel plugin.

  Three sections in the rendered HTML:
    1. Local workflows  — workflows/*.json in the consumer repo
    2. Plugin workflows — every installed plugin's workflows/ dir
       (e.g., kiln:kiln-report-issue, kiln:kiln-build-prd)
    3. (when kiln present) Feedback loops — docs/feedback-loop/*.json
       documented per 2026-04-25-feedback-loop-doc-format. Render the
       Mermaid diagrams from each loop's steps[] + context_from:
       inline. Detection: presence of docs/feedback-loop/ directory.

  Layout priorities (load-bearing — user requested):
    - Readability first; collapsible workflow sections.
    - Each step is an expandable row revealing its full body —
      command scripts, agent prompts, inputs/outputs, model
      selection, plugin deps.
    - Inline CSS, minimal vanilla JS for expand/collapse. No
      webserver, no build step, no external assets.

  Discovery reuses wheel:wheel-list's scanner — do NOT duplicate.
  Local-overrides-plugin precedence applies; surface the resolved
  source path next to each workflow name.

  Output: single self-contained HTML file at
  /tmp/wheel-view-<timestamp>.html, opened via `open` (macOS) /
  `xdg-open` (Linux). Cleanup is the user's responsibility.

  v1 scope (cheaper 80%):
    - Two-pane layout: workflow list left, detail pane right.
    - Expandable steps with full text bodies + syntax-highlighted
      JSON for raw step payloads.
    - Mermaid rendering for feedback-loop section (via Mermaid
      CDN inline; or pre-render to SVG at scan time if offline-
      friendliness matters).

  v2 candidates (out of scope for v1):
    - Search / filter across workflows + steps
    - "What command triggers this workflow" — cross-reference from
      skills that invoke /wheel:wheel-run <name>
    - Cross-workflow navigation (click a feedback-loop step that
      references another loop, jump there)
    - Per-step model / token budget aggregation
    - Drift check vs. plugin-shipped baselines (local override
      diffs)

  Hard part: unifying local + plugin workflow paths in one view.
  Plugin workflows live under marketplace cache paths
  (~/.claude/plugins/cache/<org>/<plugin>/<version>/workflows/);
  local workflows live in workflows/. Each entry must surface its
  resolved source so the user can distinguish "this is the local
  override" from "this is the plugin baseline."

  Soft assumptions (call out if any prove false):
    - Wheel JSON schema is stable enough that a static HTML render
      stays useful across releases.
    - GitHub-style Mermaid rendering via CDN is acceptable; offline
      use cases get a v2 fallback.
    - User has `open`/`xdg-open` available.

  Depends-on rationale:
    - 2026-04-25-feedback-loop-doc-format — SOFT: only the third
      section (feedback loops) needs the doc format + the renderer
      at plugin-wheel/scripts/render/render-workflow.sh. The local
      + plugin workflow sections render without it. Workaround:
      ship v1 with sections 1 + 2 only; layer feedback-loop section
      in once the doc format is populated.
---

# /wheel:wheel-view — HTML viewer for available wheel workflows + kiln feedback-loop docs

## What

A skill that ships with the wheel plugin. Invoked as `/wheel-view`, it generates a self-contained HTML page and opens it in the browser. The page shows every workflow available in this repo — both local (`workflows/*.json`) and plugin-shipped — plus, when kiln is present, the feedback-loop documentation under `docs/feedback-loop/*.json` with Mermaid diagrams rendered inline.

Layout prioritizes readability over density: workflows are collapsible sections, steps are expandable rows that open to reveal full content (command scripts, agent prompts, inputs, outputs, model selection, plugin deps). Purpose: when a user hits a command and wants to understand "what's actually about to run," they can drill into individual steps and see the real prompts/scripts without grepping JSON.

## Hardest part

Unifying local + plugin workflow discovery into one browseable view. Plugin workflows resolve from marketplace cache paths; local workflows from `workflows/`. Local-overrides-plugin precedence applies. Each rendered entry must surface where it came from so the user can distinguish a local override from the plugin baseline.

## Key assumptions

- `wheel:wheel-list`'s scanner is the single source of truth for discovery — reuse, don't rewrite.
- Workflow JSON schema is stable enough that a static HTML render stays useful across releases.
- Single-file HTML (inline CSS + minimal vanilla JS) is acceptable; no webserver needed.
- `open`/`xdg-open` is available for launching the browser.
- Mermaid via CDN is acceptable for v1; offline-only use cases are a v2 concern.

## Depends on

- `2026-04-25-feedback-loop-doc-format` — **SOFT**: needed only for the third section (kiln feedback loops + their Mermaid diagrams). Sections 1 + 2 (local + plugin workflows) render without it. Workaround: ship v1 with the first two sections, layer the feedback-loop section in when the doc format has populated `docs/feedback-loop/`.

## Cheaper 80% version

Skill calls wheel-list's scanner, emits one HTML file (inline CSS + minimal JS for expand/collapse) to `/tmp/wheel-view-<timestamp>.html`, opens it via `open`. v1 includes the readability priorities — two-pane layout, expandable step rows revealing full prompt/script/input/output text, syntax-highlighted JSON, Mermaid diagrams for the feedback-loop section. v2 adds search, filter, "what command triggers this," and cross-workflow navigation.

## Breaks if deps slip

- **`feedback-loop-doc-format` not populated** → ship without section 3. Functional v1 still delivers value via local + plugin workflow rendering.
- **Mermaid CDN unavailable / offline** → fall back to pre-rendered SVG at scan time, or text-only step list for the feedback-loop section.

## Why now

The wheel/kiln stack has accumulated enough workflows and feedback loops that "what's actually running when I invoke this command?" has become a real onboarding question. `wheel:wheel-list` answers it as text; that's not enough when steps carry multi-paragraph agent prompts and embedded scripts. A browseable HTML surface — with expansion, syntax highlighting, and the feedback-loop diagrams alongside — closes the observability gap without committing to a webserver or external docs site.

## Acceptance signal

A new contributor asks "what does `/kiln:kiln-build-prd` actually run?" — the answer is "run `/wheel:wheel-view`, expand the build-prd workflow, click any step." The HTML answers it visually, with the kiln feedback loops on the same page for context.
