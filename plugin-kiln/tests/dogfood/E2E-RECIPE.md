# E2E testing for kiln wheel-workflows

How to run a kiln **wheel workflow** end-to-end (hook-driven, all steps) in an isolated
subprocess. This is distinct from skill dogfooding (`run-scenario.sh`), which can't drive
wheel workflows.

## The problem

Wheel workflows advance via wheel's **PostToolUse + Stop hooks**. Two non-obvious facts make
this hard to reproduce in a test subprocess:

1. **`--plugin-dir` does NOT activate a plugin's hooks** in `claude --print` (verified: a
   `--plugin-dir`-only subprocess creates no `.wheel/` state; wheel's own test fixtures
   document that their harness subprocess "does NOT fire PostToolUse/Stop hooks"). So loading
   `plugin-wheel` via `--plugin-dir` gives you the `wheel-run` *skill* but not the hook engine.
2. The **activate** hook creates state and parks step 1 at `working` but emits **no directive**.
   The **Stop hook** is what emits each step's instruction (`{"decision":"block",
   "additionalContext":"<step instruction>"}`) at turn boundaries. If the model never cleanly
   ends a turn — e.g. it calls `wheel-status`/`wheel-stop` to "check" — the Stop hook never
   delivers the directive and the run stalls / gets killed.

## The recipe (`run-workflow-e2e.sh`)

Three things together:

1. **Inject wheel's hooks via `--settings`.** Pass `plugin-wheel/hooks/hooks.json` as
   `--settings`. The hook commands are `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<x>.sh"`; those
   scripts self-derive `PLUGIN_ROOT` from their own location, so they resolve to local wheel.
   (We also export `CLAUDE_PLUGIN_ROOT=<local plugin-wheel>` as belt-and-suspenders.) This is
   what makes the hook engine fire in the subprocess.
2. **Isolation:** env-wipe (`-u CLAUDECODE -u AI_AGENT -u CLAUDE_CODE_ENTRYPOINT -u
   CLAUDE_CODE_EXECPATH`) + unique `--session-id` + separate `/tmp` cwd, and the workflow file
   copied to `./workflows/<name>.json` (wheel resolves local workflows by name). `--plugin-dir`
   the plugins for skill availability.
3. **A strict driving-loop prompt.** The model MUST follow wheel's loop: do one hook-directed
   action → **end the turn** → obey the next Stop-hook `additionalContext` → repeat. It MUST
   NOT run `wheel-status`/`wheel-stop`, read state/workflow files, or try to "unstick" a parked
   step. (The wheel-run skill spells this out; the prompt must reinforce it or the model panics.)

## Proof

`run-workflow-e2e.sh kiln-mistake-record <strict-loop-prompt>` →
`history/success/`, `cursor=3 steps=done,done,done`, and the real artifacts written
(`.kiln/mistakes/<id>.md` + `.kiln/ledger/<id>.json`). 448s, ~$1.05 on sonnet.

## Notes / limits

- Verified on a 3-step agent+command workflow. Team workflows (build-prd's audit panel) use
  `team-create`/`teammate`/`team-wait`; wheel's own team fixtures prove that machinery, and the
  same recipe should drive them — running `kiln-build-prd` E2E is the next step (heavier: needs
  a real PRD + creates a PR, so budget ~$5+ and scope it deliberately).
- Manual hook debugging (firing `post-tool-use.sh` / `stop.sh` with a crafted stdin JSON) is a
  fast way to confirm the dispatch logic independent of model behavior — see the git history of
  this file's introduction for the exact commands.
- The model occasionally re-runs an agent step (we saw a duplicate mistake entry once). Harmless
  for verification; tighten the step instruction if it matters.
