# Parity Result — deferred

**Status**: deferred to auditor-run E2E

The snapshot-diff harness (`plugin-shelf/scripts/obsidian-snapshot-diff.sh`)
is built, sanity-checked on synthetic fixtures (T007 green), and ready to
be invoked once both v3 and v4 have been run against the same Obsidian
vault. See `benchmark-results.md` §"Minimum to clear SC-003" for the exact
command sequence the auditor should run.

Caveat flagged in benchmark-results.md: v3's LLM-driven rendering may
produce cosmetically different bodies than v4's deterministic rendering
even with identical inputs. The auditor should decide whether SC-003
requires strict body-hash equality or relaxed structural equality (path +
type + status + tags intersection).
