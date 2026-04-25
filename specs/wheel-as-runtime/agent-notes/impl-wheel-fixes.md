# impl-wheel-fixes — friction & phase-0 notes

Track owner: impl-wheel-fixes
Branch: build/wheel-as-runtime-20260424
Scope: Themes C (FR-C1..C4, hook newline preservation) + D (FR-D1..D4, WORKFLOW_PLUGIN_DIR env parity)

## Phase 0 — T020 Option A viability spike (FR-D1, research.md R-001)

**Verdict: Option A is NOT viable for agent-step sub-agents. Option B is the shipped path.**

### Evidence & reasoning

1. Wheel's agent step (`plugin-wheel/lib/dispatch.sh:506-614`, `dispatch_agent`) does NOT fork a sub-process. It returns a hook response `{"decision": "block", "reason": <instruction>}` to the harness. The harness injects `reason` as additionalContext into the parent LLM's conversation. The LLM then decides to call the `Agent` tool. The harness creates the sub-agent.
2. Wheel's bash hook process terminates immediately after emitting the JSON hook response. Any env vars `export`ed inside the hook die with the hook process. They do NOT reach the parent LLM process, nor the harness process, nor any sub-agent the harness later spawns.
3. The only existing Option-A-shaped export today is in `dispatch_command` (`plugin-wheel/lib/dispatch.sh:889`): `export WORKFLOW_PLUGIN_DIR="$wf_plugin_dir"; eval "$command"`. That works because wheel DIRECTLY forks the bash subshell that runs the command — wheel owns the process boundary. For agent steps wheel does not own the spawn boundary.
4. There is no documented (or undocumented-but-stable) hook in Claude Code's harness that lets a PostToolUse handler inject env vars into a subsequently-spawned Agent sub-process. The harness baselines its own env for sub-agent spawns; wheel has no seat at that table.
5. Empirical probe (in the existing source-repo layout): `bash "${WORKFLOW_PLUGIN_DIR}/scripts/..."` in `plugin-kiln/workflows/kiln-report-issue.json`'s dispatch-background-sync agent step only "works" today because the parent foreground process happens to have `WORKFLOW_PLUGIN_DIR` exported from a prior wheel command-step run — NOT because the hook re-exports it for the agent-tool spawn. In a fresh consumer-install where no prior command step exported it, the var is undefined and the bg sub-agent no-ops silently. This matches FR-D (SC-007, SC-002) exactly.

### Implementation: Option B (templated into instruction)

The fix is to template the concrete absolute path of `WORKFLOW_PLUGIN_DIR` into the agent-step's instruction string at dispatch time. Concretely: when `context_build` assembles the instruction for an agent step, it prepends a `## Runtime Environment` block naming `WORKFLOW_PLUGIN_DIR=<absolute-path>` so the LLM sees it as text. The LLM then passes `WORKFLOW_PLUGIN_DIR=...` explicitly into every Bash tool call it makes (or into the sub-agent prompt when it spawns a bg sub-agent).

This is "prompt-templating the absolute path into the sub-agent prompt at dispatch time" per FR-D1 Option B.

### Why this is reliable

- The value is computed at wheel's dispatch time from the workflow file's plugin path (same computation as `dispatch_command`'s existing export).
- The value travels as conversation context, not as OS env — harness env baselining is irrelevant.
- Sub-agents spawned from the foreground agent inherit the value via prompt-pass-through (the parent agent is instructed to propagate it in the spawn prompt).
- A bg sub-agent written by hand (as the one in `kiln-report-issue.json` is) can also `export WORKFLOW_PLUGIN_DIR=<literal-value>` at the top of its own bash commands because it sees the value in its prompt.

### Consequence for FR-D3 CLAUDE.md note

CLAUDE.md's "Plugin workflow portability" section MUST state: "Wheel templates `WORKFLOW_PLUGIN_DIR=<absolute-path>` into the instruction of every agent step. Command steps continue to receive the var via direct env export (`dispatch_command`). The same value is visible in foreground and background sub-agents; sub-agent authors must propagate it via the spawn prompt if they nest further."

## Phase 0 — T021 R-004 blast-radius audit (FR-C1, research.md R-004)

`git grep -n 'tool_input\.command\|tr .\\\\n. ' plugin-wheel/` enumerates every site in plugin-wheel that reads `tool_input.command` OR applies a newline flatten:

| Site | Line | Reads command? | Flattens? | Verdict |
|---|---|---|---|---|
| `plugin-wheel/hooks/post-tool-use.sh` | 11 | — | **YES (`tr '\n' ' ' | sed 's/[[:cntrl:]]/ /g'`)** | **fix-in-PRD** (the primary FR-C1 target) |
| `plugin-wheel/hooks/post-tool-use.sh` | 25 | YES (`jq -r '.tool_input.command'`) | derives from already-flattened `$HOOK_INPUT` | fix-in-PRD (inherits the fix from line 11 removal + direct raw extract) |
| `plugin-wheel/hooks/block-state-write.sh` | 16 | YES (`jq -r '.tool_input.command'` on raw `$INPUT`) | no pre-flatten, BUT `\|\| true` silently swallows jq failures | **fix-in-PRD** (same jq-fails-on-control-chars vulnerability; on failure, COMMAND is empty → regex misses → write slips through undetected. Exactly the NFR-2 silent-failure shape) |
| `plugin-wheel/lib/engine.sh` | 187 | YES (`jq -r '.tool_input.command'` on `$hook_input_json`) | no pre-flatten | leave-as-is IF the caller passes unflattened input. Post-FR-C1, `post-tool-use.sh` passes the unflattened raw input here via `$HOOK_INPUT`, so this site becomes safe by transitive fix. Verify with unit test. |
| `plugin-wheel/bin/activate.sh:9` | comment-only | N/A | N/A | leave-as-is (documentation reference to hook behavior) |
| `plugin-wheel/bin/deactivate.sh:12` | comment-only | N/A | N/A | leave-as-is |

No other regex anchored to line-start/line-end that would break when multi-line content reappears. The existing `grep -E '^[[:space:]]*(bash[[:space:]]+)?...activate\.sh...'` regex in `post-tool-use.sh:122` already runs on `$COMMAND` via a line-delimited pipe (`printf '%s\n' "$COMMAND" | grep -E ... | tail -1`) — so once `$COMMAND` carries real newlines, the grep iterates lines correctly, which is exactly what FR-C2 requires. No regex-widening needed (T072 becomes a no-op verification rather than a code change).

### R-004 fix-in-PRD items (sibling tasks)

- **post-tool-use.sh (T070)**: Drop the `tr '\n' ' '` pre-flatten on `RAW_INPUT`. Extract `.tool_input.command` directly via `jq -r` on raw input. Fall back to `python3 -c "import json,sys; ... strict=False"` on jq parse failure (python's `strict=False` permits literal control chars in strings where jq rejects them). Defensive sanitization of OTHER fields (logging metadata) is allowed but MUST NOT touch the command string.
- **block-state-write.sh (T071)**: Replace the silent-`\|\| true` pattern with the same two-tier jq → python3 extraction. On total extraction failure, emit an identifiable stderr line (not silent) AND continue to allow by default (since this hook's job is only to block on positive match, not to block on uncertainty).
- **engine.sh:187**: No code change. Add a unit test that hands `engine_handle_hook` a raw hook input with a multi-line `tool_input.command` and asserts `state_append_command_log` stores the value with newlines preserved.

## Running friction log

(Appended as work progresses. Per pipeline-contract FR-009, retrospective reads this instead of polling.)

- 2026-04-24 T17:10Z — Specifier dispatched C+D bundled. Starting Phase 0.
- 2026-04-24 T17:15Z — T020 verdict: Option A infeasible. Option B is the ship.
- 2026-04-24 T17:15Z — T021 R-004 findings: two fix-in-PRD sites (post-tool-use.sh pre-flatten + block-state-write.sh silent-jq-swallow). No regex widening needed for FR-C2; inherited correctness from pre-flatten removal.
- 2026-04-24 T17:17Z — **Parallel-track staging friction**: my Phase 0 commit swept in Theme A's pre-staged agent-file renames (`plugin-kiln/agents/* → plugin-wheel/agents/*`) because parallel implementer tracks share a single git index. `git add <specific-files>` adds to the shared index, and `git commit` without `--only` takes everything staged. This isn't fatal (both tracks land in the same PR) but it muddles commit attribution. **Mitigation for this track going forward**: before each commit, explicitly unstage everything first with `git restore --staged .` then re-stage only this track's files. OR use `git commit -- <paths>` to scope the commit. Flagging for the retrospective as a pipeline friction signal — parallel tracks without per-track branches or per-track staging discipline will keep producing mixed-attribution commits.
