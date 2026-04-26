## When to use

Reach for wheel when a skill needs to dispatch a multi-step workflow with state tracked between steps, hook-enforced transitions, and per-step model selection. Wheel is deliberately plugin-agnostic infrastructure — it executes any well-formed workflow JSON regardless of which plugin authored it; features belong in the owning plugin, not in wheel (per `.kiln/vision.md` "Plugins ship independently — wheel is plugin-agnostic infrastructure").

## Key feedback loop

Wheel's value to the system is consistency, not features: every plugin that needs a workflow gets the same hook substrate, state machine, agent-resolver primitive, and `WORKFLOW_PLUGIN_DIR` injection contract. New skills, agents, and workflows ship inside their owning plugin and the harness discovers them at session start — no wheel release is needed to add a new capability.

## Non-obvious behavior

- Workflow scripts that need plugin-relative paths MUST resolve through `${WORKFLOW_PLUGIN_DIR}` (exported into command-step env, templated into agent-step instruction text). Repo-relative paths silently work in the source repo and silently break in consumer installs — treat them as portability bugs, not stylistic preferences.
- Agents register as `<plugin>:<role>` via the harness's filesystem scan at session start. Bare-name lookups against a central registry are an anti-pattern (the registry no longer exists) — always spawn with the plugin-prefixed name.
- A new agent file shipped in a given session is NOT spawnable in that same session; live-spawn validation has to wait one session because filesystem discovery runs at session start.
- The architectural test for any wheel change: *"does this require wheel to know about another plugin's contents?"* If yes, push the change into the owning plugin instead.
