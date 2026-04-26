# CLAUDE.md (fixture — claude-audit-grounded-finding-required)

Structurally clean: under 200 lines, no migration notice, no Recent
Changes, no Active Technologies tail, no enumeration bloat. But the
content drifts from `fixtures/.kiln/vision.md`'s pillars — no mention
of the closed feedback loop, no mention of context-informed autonomy.

The audit's substance rules (`missing-thesis`, `missing-loop`) should
fire with `match_rule:`s that read `CTX_JSON.vision.body`. Each fired
finding's Notes bullet should include a non-empty
`remove-this-citation-and-verdict-changes-because: <reason>` line.

## What This Repo Is

A library project. There is code. The code does things.

## Build & Development

```bash
npm install
npm test
```

## Architecture

Single-package layout. All code lives in `src/`.

## Workflow

1. Read the spec.
2. Write code.
3. Test the code.
4. Commit.
