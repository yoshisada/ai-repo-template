You are acting as a solo developer setting up kiln in a brand-new empty git repo. The
current directory is already an initialized empty git repo. You are running HEADLESS
(non-interactive) — so for any wizard question, pick the stated default and proceed; do
NOT wait for input. Be concise.

Do these three steps in order, then report:

1. Run the `/kiln:kiln-init` skill to set up kiln in this repo. It should scaffold the
   project structure including the new Phase 0 config files. Run it non-interactively:
   skip the vision interview (defer it) and accept the default review mode, design_first=no,
   and branching style. Do NOT get stuck on interactive prompts — choose defaults and move on.

2. Run the `/kiln:kiln-doctor` skill (diagnose mode) and capture its diagnosis table,
   including the new Config Foundation rows.

3. Run the `/kiln:kiln-next` skill and capture its recommended next action.

Then report EXACTLY this, filling in real values:

```
=== PHASE 0 DOGFOOD RESULT ===
config.json present:        yes|no  (value of config_version: ___)
standards.md present:       yes|no
test-strategy.json present: yes|no
doctor config rows:         <paste the | Config foundation / .kiln/config.json | rows>
doctor overall:             HEALTHY|NEEDS ATTENTION
kiln-next recommended:      <the single suggested next command>
kiln-next read review_mode: yes|no  (what did it print for review mode?)
notes:                      <anything that broke or looked wrong>
```

Keep total output under 60 lines. Do not start building features — this is a setup smoke test.
