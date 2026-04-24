# `plugin-kiln/scripts/context/`

Shared project-context reader — emits a deterministic JSON snapshot of
capture-relevant repo signals. Consumed by `/kiln:kiln-roadmap`,
`/kiln:kiln-roadmap --vision`, `/kiln:kiln-claude-audit`, and
`/kiln:kiln-distill` to ground coached prompts in real repo state.

## Scripts

| Script | Purpose |
|---|---|
| `read-project-context.sh` | Top-level entry — emits a `ProjectContextSnapshot` JSON object to stdout. |
| `read-prds.sh` | Helper — scans `docs/features/<date>-<slug>/PRD.md` files. |
| `read-plugins.sh` | Helper — scans `plugin-*/.claude-plugin/plugin.json` files. |

## Usage

```bash
bash plugin-kiln/scripts/context/read-project-context.sh               # current repo
bash plugin-kiln/scripts/context/read-project-context.sh --repo-root /path/to/repo
```

## Contract

The JSON schema, field semantics, sort guarantees, exit codes, and invocation
patterns are defined in:

- **`specs/coach-driven-capture-ergonomics/contracts/interfaces.md`** (canonical)

Do not duplicate the schema here — the contract file is the single source of
truth. If the schema needs to change, follow the Signature Change Protocol at
the bottom of that file.

## Invariants

- **NFR-001 (performance)**: <2 s on a repo with ~50 PRDs + ~100 roadmap items.
- **NFR-002 (determinism)**: byte-identical stdout on two invocations against
  unchanged repo state. All collections sorted ASC by `path` (or `name` for
  phases + plugins). No timestamps, PIDs, CWD, or env-varying strings. All
  scripts set `LC_ALL=C` before any `sort` call.
- **NFR-006 (hook-safety)**: never invoked from a PreToolUse hook — only from
  skill bodies. This keeps hook overhead unchanged.

## Tests

Fixture tests live under `plugin-kiln/tests/`:

- `project-context-reader-determinism/` — populated fixture, two invocations,
  byte-identical output asserted.
- `project-context-reader-empty/` — empty fixture, all fields `[]` or `null`,
  exit 0.
- `project-context-reader-performance/` — synthesized 50-PRD + 100-item
  fixture, wall-clock <2 s budget.

Run a single test:

```bash
bash plugin-kiln/tests/project-context-reader-determinism/run.sh
```
