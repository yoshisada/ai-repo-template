An `agent` task is a meta-task: the artifact under change is itself an agent prompt
(`plugin-<name>/agents/<role>.md`). Substrate is the structural-validity fixture
pattern (grep for forbidden content: verb tables, enumerated tool references, model
directives, step-by-step task prose) plus — in a fresh session — live spawn of the
agent with a known task spec to confirm role identity holds.

Report: structural assertions (every grep gate passed), `tools:` allowlist
verification, absence of `model:` frontmatter where forbidden, and (when feasible) a
live-spawn smoke result. Agent registration is session-bound, so live-spawn validation
of newly-shipped agents is queued for the next session — flag this explicitly rather
than pretending in-session validation is possible.
