# Feature Specification: /wheel:wheel-view — HTML viewer for available wheel workflows

**Feature Branch**: `build/manifest-evolution-ledger-20260427` (working inline; branch shared with manifest-evolution-ledger work)
**Created**: 2026-04-27
**Status**: Draft
**Input**: Roadmap item — `.kiln/roadmap/items/2026-04-27-wheel-view-html-viewer.md` (phase: `12-loop-and-workflow-design`)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - "What's about to run when I invoke this command?" (Priority: P1)

A maintainer is about to invoke a kiln or wheel command (e.g., `/kiln:kiln-build-prd`, `/wheel:wheel-run my-workflow`) and wants to understand exactly what that command will execute — which steps fire, in what order, with which agent prompts and shell scripts. Today they grep `workflows/*.json` and the marketplace cache. The viewer answers it visually instead.

**Why this priority**: This is the load-bearing reason the viewer exists. Without P1 working, the whole feature fails its purpose — every other story is a refinement.

**Independent Test**: Run `/wheel:wheel-view`. Confirm an HTML page opens showing every available workflow (local + plugin). Pick any workflow's name; expand it; expand any step. The full step body (command script, agent prompt, inputs/outputs, model selection if any) is visible without leaving the page.

**Acceptance Scenarios**:

1. **Given** the consumer repo has at least one local workflow under `workflows/` AND at least one plugin workflow installed, **When** the user invokes `/wheel:wheel-view`, **Then** the browser opens an HTML page listing both workflows under clearly labeled "Local" and "Plugin: <name>" sections, with each workflow's name, step count, and resolved source path visible at a glance.

2. **Given** the viewer is open on a workflow, **When** the user clicks a step row to expand it, **Then** the step's full content renders — for `command` steps the literal shell script, for `agent` steps the full prompt text, for both the `requires_plugins` field, any `model:` selection, and the step's `id`/`type`/`output:` fields.

3. **Given** a local workflow exists with the same name as a plugin-shipped workflow (override case), **When** the user views both, **Then** the page surfaces which one is active in the consumer repo and labels the other as "shadowed by local override," including the resolved file path for both.

---

### User Story 2 - "What's the actual feedback loop here?" (Priority: P2)

A new contributor (or the maintainer revisiting old work) wants to understand a documented feedback loop — say, the retro-to-PI-apply loop or the capture-to-distill flow. The loop is documented under `docs/feedback-loop/*.json` per the format specified in `2026-04-25-feedback-loop-doc-format` and rendered to markdown with embedded Mermaid diagrams. They want to see the diagram + per-step prose without opening multiple files in different editors.

**Why this priority**: Loops are the second class of "what runs when" the user asks about. Bundling them into the same viewer gives a single place to land for both runnable and conceptual flows. P2 because the runnable workflows (P1) are the more common path; loops are a smaller second audience.

**Independent Test**: With kiln installed and `docs/feedback-loop/*.json` populated, run `/wheel:wheel-view`. Confirm a "Feedback loops" section appears alongside "Local workflows" and "Plugin workflows," with each loop's Mermaid diagram rendered inline and per-step `_meta.doc` prose visible on expansion.

**Acceptance Scenarios**:

1. **Given** kiln is installed AND `docs/feedback-loop/` contains at least one valid loop JSON file, **When** the user invokes `/wheel:wheel-view`, **Then** a "Feedback loops" section is present and each loop entry shows its Mermaid diagram inline, the loop's `_meta` metadata (kind, status, owner, triggers, metrics, anti_patterns, related_loops), and expandable steps with `_meta.doc` text.

2. **Given** kiln is NOT installed (or `docs/feedback-loop/` does not exist), **When** the user invokes `/wheel:wheel-view`, **Then** the viewer renders only the "Local workflows" and "Plugin workflows" sections without an empty / broken feedback-loops section.

---

### User Story 3 - "Can I share this artifact?" (Priority: P3)

A maintainer wants to share what their pipeline looks like with a collaborator who doesn't have the repo cloned — e.g., paste it in a Slack thread, attach it to a PR review, or save it as documentation. The viewer's output should be a single self-contained file they can hand off.

**Why this priority**: Useful but not load-bearing. Most users will run the viewer locally to inspect their own setup. Shareability is a nice-to-have that justifies the "single self-contained HTML file" implementation choice but doesn't drive any new functional requirements beyond what P1 already implies.

**Independent Test**: After running `/wheel:wheel-view`, locate the generated HTML file. Email or upload it to a fresh environment with no repo access. Open in a browser. Confirm the page renders with all expand/collapse interactivity intact and no broken external resources (other than the explicitly-permitted Mermaid CDN for diagram rendering).

**Acceptance Scenarios**:

1. **Given** the viewer was just generated, **When** the user copies the output HTML file to a different machine and opens it in a browser, **Then** all sections render, all steps expand/collapse correctly, and Mermaid diagrams render (assuming network access for the CDN, or pre-rendered SVG if implemented as the offline fallback).

---

### Edge Cases

- **Empty consumer repo (no local workflows)**: viewer still renders, with the "Local workflows" section showing a clear "no workflows under `workflows/`" empty state rather than disappearing or erroring.
- **No plugins installed (no plugin workflows discovered)**: viewer still renders with empty-state message under "Plugin workflows."
- **Malformed workflow JSON**: a workflow file that fails to parse should be listed with its filename + an explicit "could not parse" indicator and the parse error preview, not silently dropped.
- **Workflow with zero steps**: rendered as a workflow entry with "0 steps — workflow body is empty."
- **Workflow JSON over a size threshold (large step bodies)**: display behavior degrades gracefully — collapsed by default, expanded shows the full body without truncation, but an indicator marks it as "large."
- **Multiple plugins shipping a workflow with the same name**: each appears in its own plugin section; if a local workflow shadows them all, the local wins for invocation but all are listed.
- **Mermaid CDN unreachable / offline**: feedback-loops section renders the loop's metadata + step list, with a placeholder where the diagram would appear and a one-line note explaining how to regenerate the page with offline fallback.
- **`open` / `xdg-open` unavailable**: the skill prints the path to the generated HTML file and instructs the user to open it manually rather than failing.
- **Workflow file references a nonexistent script path** (e.g., a `command` step calling `${WHEEL_PLUGIN_<name>}/scripts/missing.sh`): rendered verbatim with no resolution attempt — the viewer shows the literal command, not the resolved script body.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The skill `/wheel:wheel-view` MUST be invocable from any consumer repo where wheel is installed. The skill MUST exit cleanly without error when no workflows are present (renders an empty-state HTML page).
- **FR-002**: Workflow discovery MUST cover both local workflows (`workflows/*.json` in the consumer repo) and every wheel-aware plugin's workflow directory (e.g., `<plugin-install-path>/workflows/*.json`). The discovery logic MUST reuse the existing `wheel:wheel-list` scanner — not reimplement it.
- **FR-003**: The output HTML page MUST be a single self-contained file. Inline CSS and inline (vanilla) JavaScript only; no external assets except the optional Mermaid CDN reference for the feedback-loops section (FR-014). No build step, no webserver.
- **FR-004**: For each discovered workflow, the page MUST surface: workflow name, total step count, resolved source file path (so the user can distinguish local from plugin and see which override is active), and the workflow's `description` field (when present).
- **FR-005**: Each workflow entry MUST be a collapsible section (collapsed by default for navigability; expanded shows the per-step list).
- **FR-006**: Each step within an expanded workflow MUST be presented as an expandable row. Collapsed shows: step `id`, `type`, and a one-line summary. Expanded shows: the full step body — for `command` steps the literal shell script; for `agent` steps the full prompt text; for any step type, the `requires_plugins` list, the `model:` selection if present, the `inputs:` and `output:` field values, and any other top-level step keys.
- **FR-007**: Step body content MUST be presented as preformatted text with monospace styling. JSON payloads embedded as values (e.g., `inputs:` blocks) MAY be rendered with basic syntax highlighting; multi-line shell scripts and prompts MUST preserve their original whitespace and line breaks.
- **FR-008**: When a local workflow overrides a plugin-shipped workflow with the same name, BOTH MUST be listed: the local under "Local workflows" and the plugin original under "Plugin: <plugin-name>" with a clearly visible "shadowed by local override" badge or label.
- **FR-009**: Layout MUST prioritize readability — generous whitespace, two-pane navigation (workflow list left, detail content right) on viewport widths ≥ 1024px; single-column flow on smaller viewports. The page MUST be readable at 100% browser zoom without requiring horizontal scrolling for the workflow list.
- **FR-010**: When kiln is detected as installed (presence of `docs/feedback-loop/` directory in the consumer repo), the viewer MUST add a third section "Feedback loops" alongside the local + plugin workflow sections. When kiln is not detected, the section MUST be entirely absent (not present-and-empty).
- **FR-011**: For each feedback loop discovered under `docs/feedback-loop/*.json`, the viewer MUST render: the loop's name, `_meta.kind`, `_meta.status`, `_meta.owner`, any `_meta.triggers` / `_meta.metrics` / `_meta.anti_patterns` / `_meta.related_loops` / `_meta.last_audited` values present, an inline Mermaid `flowchart TD` diagram derived from the loop's `steps[]` + `context_from:` edges (matching the rendering produced by `plugin-wheel/scripts/render/render-workflow.sh`), and per-step expandable rows showing each step's `_meta.doc` if present (falling back to the step's command/instruction body).
- **FR-012**: The viewer MUST NOT execute any workflow or feedback loop. Discovery and rendering are read-only operations against on-disk JSON.
- **FR-013**: The viewer MUST NOT make network requests EXCEPT for the optional Mermaid CDN load (FR-014). All other content MUST be inlined.
- **FR-014**: For Mermaid diagram rendering in the feedback-loops section, the viewer MAY load a single pinned-version Mermaid script from a public CDN. The CDN URL and version MUST be a constant in the skill (no dynamic fetching of the latest version). If the CDN is unreachable, the page MUST still render the loop's metadata + step list, with a placeholder where the diagram would appear and a note explaining the offline state.
- **FR-015**: After generating the HTML file, the viewer MUST attempt to open it in the user's default browser via `open` (macOS) / `xdg-open` (Linux) / `start` (Windows, future). If the open command is unavailable or fails, the skill MUST print the file path to stdout and exit cleanly.
- **FR-016**: The generated HTML file MUST be written to a temporary location (e.g., `/tmp/wheel-view-<timestamp>.html`) so multiple invocations don't overwrite each other and the consumer repo isn't polluted with generated artifacts. The file path MUST be printed to stdout regardless of whether the browser auto-launch succeeded.
- **FR-017**: A workflow file that fails JSON parsing MUST be surfaced as a "could-not-parse" entry with its filename and parse error preview, NOT silently dropped from the listing.
- **FR-018**: The viewer MUST surface, somewhere on the page (e.g., a small footer or header banner), the timestamp of generation, the count of workflows discovered per section, and the version of wheel that generated the page. This makes the artifact self-describing for shareability (US3).
- **FR-019**: The skill MUST be implemented under the wheel plugin (`plugin-wheel/skills/wheel-view/`), not kiln, because workflow discovery is wheel's domain. The kiln-specific feedback-loops section is a conditional render gated by `docs/feedback-loop/` presence — not a kiln dependency in the wheel plugin manifest.
- **FR-020**: The skill MUST NOT modify, write, or delete anything inside `workflows/`, plugin install directories, or `docs/feedback-loop/`. All inputs are read-only.

### Key Entities

- **Workflow Entry**: a discovered workflow JSON file with associated metadata (resolved source path, source kind: local | plugin-name, parse status, name, description, step count, steps[]).
- **Step Entry**: a single step within a workflow, carrying id, type, the step's full body (command script / agent prompt), inputs, output, requires_plugins, model selection (if any).
- **Plugin Source**: a discovered wheel-aware plugin (name, install path, list of workflow files contributed). Determined via reuse of `wheel:wheel-list`'s scanner.
- **Feedback Loop Entry** (kiln-conditional): a JSON file under `docs/feedback-loop/` matching the schema from `2026-04-25-feedback-loop-doc-format` — carrying `_meta` (kind, status, owner, triggers, metrics, anti_patterns, related_loops, last_audited), top-level steps[], and per-step `_meta.doc` annotations. Mermaid diagram source derives from steps[] + context_from: edges.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user invoking `/wheel:wheel-view` in a consumer repo with at least one local workflow and at least one installed plugin sees both, with full step content visible upon expansion, in under 5 seconds end-to-end (skill invocation → HTML rendered in browser).
- **SC-002**: A new contributor with no prior exposure to a workflow can answer the question "what does this command run?" in under 60 seconds using only the viewer — no source-grep, no editor open.
- **SC-003**: 100% of workflow files discovered by `wheel:wheel-list` are also discovered and rendered by `wheel-view` (the viewer never silently drops a workflow that wheel-list shows).
- **SC-004**: A maintainer can copy the generated HTML file to a different machine without the repo cloned and have all sections render correctly, with the only degradation being Mermaid diagrams when offline (which gracefully fall back to the metadata-only view).
- **SC-005**: When a local workflow shadows a plugin workflow, the override is visible in the viewer in 100% of test cases (no missed shadows; no false-positive shadow labels).
- **SC-006**: When kiln is not installed (no `docs/feedback-loop/` directory), the feedback-loops section is absent from the rendered page in 100% of cases — not present-and-empty.
- **SC-007**: When kiln IS installed and at least one loop file exists, every loop's Mermaid diagram renders identically to the diagram produced by `plugin-wheel/scripts/render/render-workflow.sh` against the same loop file (the viewer reuses the existing renderer's logic — does not produce divergent output).

## Assumptions

- Reuses the existing `wheel:wheel-list` scanner for workflow discovery — no new scanner code, no parallel discovery logic.
- The `2026-04-25-feedback-loop-doc-format` item ships its `_meta:` schema (kind, status, owner, triggers, metrics, anti_patterns, related_loops, last_audited, per-step `actor` + `doc`) before the feedback-loops section is required to render. Until then, the viewer ships with sections 1+2 only and section 3 layers in once `docs/feedback-loop/*.json` files exist.
- The `plugin-wheel/scripts/render/render-workflow.sh` renderer is the canonical Mermaid generator. The viewer either invokes it as a subprocess to get the Mermaid source, or uses the same jq pipeline — whichever is cheapest to ship without introducing rendering divergence.
- Workflow JSON schema is stable enough across wheel releases that the viewer doesn't need version-specific rendering paths. Schema additions are additive (per wheel's permissive-on-unknown-keys posture); the viewer renders any unknown top-level keys as raw JSON in the expanded view.
- Mermaid via CDN is acceptable for v1; offline-friendly pre-rendering is a v2 concern. The CDN URL is pinned to a specific version (no auto-update).
- The user's browser supports modern HTML5 + ES2018+ JavaScript (any current Chrome / Firefox / Safari / Edge). No IE / legacy-browser support.
- macOS and Linux are the primary target environments. Windows is a v2 concern; the v1 fallback (printing the file path to stdout for manual open) is sufficient on Windows.
- The viewer is read-only and cannot be misused to mutate workflow files or plugin install directories.
- Out-of-scope for v1 (called out so they're not surprises): search/filter across workflows, "what command triggers this workflow" cross-references from skills, cross-workflow navigation (clicking a feedback-loop step that references another loop), per-step token / model / cost summaries, drift checks vs. plugin-shipped baselines.
