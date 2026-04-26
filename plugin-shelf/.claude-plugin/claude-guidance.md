## When to use

Reach for shelf when the user wants the project's state — status, progress, captured issues, feedback, mistakes, fixes, releases, retros — mirrored into Obsidian, where they actually do their thinking. It's the bridge between code-side capture (the raw `.kiln/` artifacts) and a human-readable, cross-linked vault that survives across sessions, projects, and team handoffs.

## Key feedback loop

Shelf's role in the loop is projection: kiln captures structured artifacts in the repo, shelf mirrors them to the Obsidian vault as templated notes, and human review happens there. Improvement proposals (template tweaks, manifest corrections, mistake-driven changes) land as files in the vault's `@inbox/open/` for explicit accept-or-reject — proposals never apply themselves, but they accumulate visibly so a session-of-review can clear them in a batch.

## Non-obvious behavior

- A `.shelf-config` file at the repo root holds per-repo settings, including a counter that gates how often expensive reconciliation runs (cheap path on every capture; full sync on a configurable cadence). Don't treat the file as cosmetic — it's load-bearing for performance.
- Mirror writes go through the Obsidian MCP; if the MCP server isn't reachable, shelf skills degrade gracefully (skip-with-log) rather than failing the calling skill. The mirror is best-effort, not a hard dependency for code-side work.
- The vault is the source of truth for human-curated narrative (about, status, decisions); the repo is the source of truth for code-side artifacts. Repair-style skills preserve user-edited sections — never overwrite human content during a re-template.
