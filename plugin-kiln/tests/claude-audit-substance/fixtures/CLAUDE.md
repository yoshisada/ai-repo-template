# CLAUDE.md (fixture — claude-audit-substance)

This is a structurally-clean CLAUDE.md. It passes mechanical rules:
- under 200 lines (no length-density signal)
- no `## Recent Changes` section (no overflow / anti-pattern)
- no `## Active Technologies` accretion
- no migration notice
- no enumeration bloat in commands

But it makes no reference to any vision pillar from
`fixtures/.kiln/vision.md`. The audit's `missing-thesis` substance
rule should fire and propose inserting a thesis paragraph derived
from vision.md content.

## What This Repo Is

A small Bash utility library for parsing log files. The library
exposes three commands: `parse`, `summarize`, `tail`.

## Build & Development

```bash
make build
make test
```

## Architecture

```
src/
├── parse.sh
├── summarize.sh
└── tail.sh
```

## Workflow

1. Edit a script under `src/`.
2. Run `make test`.
3. Open a PR.
