---
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: low
suggested_command: /kiln:kiln-fix
tags: [retro, wheel, preprocess, docs]
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-24-sc-grep-doc-references-carve-out.md
---

# Documentary references to `${WHEEL_PLUGIN_<name>}` / `${WORKFLOW_PLUGIN_DIR}` inside agent instructions trip both the runtime tripwire and the SC grep

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; impl-migration-perf friction note §"T050 migration — escape grammar gotcha"

## Description

While migrating `kiln-report-issue.json`, impl-migration-perf added a closure note to the dispatch-background-sync agent instruction that documented the new system, with text like:

> "the previous gap when `${WORKFLOW_PLUGIN_DIR}` resolved to plugin-kiln but the scripts lived in plugin-shelf"

These were intended as documentary references — literal text the agent would read, not substitution targets. But:

1. The grammar `${WHEEL_PLUGIN_<name>}` (with `<` / `>`) doesn't match the substitution regex (`<` isn't in `[a-zA-Z0-9_-]+`), so the preprocessor's substitution stage skipped them.
2. The post-substitution tripwire (FR-F4-5) prefix-pattern `\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)` matched the prefix and fired loudly.
3. Even with `$$` escaping (FR-F4-4), the post-decode form survived to the archived state file and would trip the SC-F-6 historical-grep audit.

Net: documentary token references inside agent instructions are **structurally hostile** to the wheel preprocessor's safety system. The only durable form is plain prose that doesn't reproduce the token grammar.

## Proposed fix (not a prompt rewrite — author docs)

**File**: `plugin-wheel/lib/preprocess.sh` (module comment) AND `plugin-wheel/README.md` (workflow-authoring section)

**Current**: No author-facing documentation of the "documentary references trip the tripwire" gotcha. Authors discover it on first migration.

**Proposed**: Add to the `preprocess.sh` module-level comment AND to wheel README's workflow-authoring section:

```markdown
> **Workflow-author rule — token grammar in instructions**: do NOT include
> documentary references to `${WHEEL_PLUGIN_<name>}` or
> `${WORKFLOW_PLUGIN_DIR}` inside agent `instruction` text, even when
> describing the system's design or referencing legacy behavior. Reasons:
>
> 1. The runtime tripwire (FR-F4-5 prefix-pattern) fires on any
>    post-substitution `${WHEEL_PLUGIN_…}` / `${WORKFLOW_PLUGIN_DIR}`
>    match, even on grammar variants the substitution regex skips (e.g.
>    `${WHEEL_PLUGIN_<name>}`).
> 2. `$$` escaping (FR-F4-4) lets the literal text survive the tripwire,
>    but the post-decode form lands in `.wheel/history/success/*.json` and
>    trips the SC-F-6 archive-grep audit.
>
> If you need to reference the system design in agent instructions, use
> plain prose (e.g. "the wheel runtime substitutes plugin-relative tokens
> with absolute paths before this instruction runs") that does NOT
> reproduce the token grammar verbatim.
```

**Why**: This bit impl-migration-perf mid-migration and cost a fix-attempt cycle (try `$$` escaping → still trips SC-F-6 → rewrite as plain prose). Documenting the rule in two places (the lib's module comment for code-reading authors; the README for first-time workflow authors) prevents the next author's rediscovery.

## Forwarding action

- Add the rule to `plugin-wheel/lib/preprocess.sh` module comment.
- Add the rule to `plugin-wheel/README.md` (workflow-authoring section, if present; otherwise add a "Writing agent instructions" section).
- Optional: extend the FR-F4-5 tripwire's error text to include "If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with `$$` escaping" so authors hit the explanation directly on first violation.
