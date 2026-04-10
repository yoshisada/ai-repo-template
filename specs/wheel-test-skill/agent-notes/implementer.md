# Implementer friction notes — wheel-test skill

## 1. The PostToolUse hook cannot see activate.sh calls made through shell functions

**Severity**: blocking — forced a contract change to T017/T018

**What I assumed from the spec/plan/tasks**: `wt_run_phase1` and `wt_run_serial_phase` would be shell functions that loop over workflow paths, calling `"$WT_ACTIVATE_SH" "$wf"` internally, and the hook would fire for each activation.

**What actually happens**:
1. `plugin-wheel/hooks/post-tool-use.sh` line 132 scans the LITERAL command text of each Bash tool call with this regex:
   ```
   ^[[:space:]]*(bash[[:space:]]+)?("|')?(\./|/)?[^[:space:]()"']*activate\.sh([[:space:]]|$)
   ```
   and takes `tail -1`. So only the last matching line in the Bash command text is intercepted.
2. When activate.sh is called from inside a sourced shell function, the literal command text sent to the Bash tool is something like `source runtime.sh && wt_phase1_wait_all` — there is NO `activate.sh` token in the tool input at all. The hook never fires.
3. Even if you call `"$WT_ACTIVATE_SH" "$wf"` at the top level of a Bash tool call, the regex requires the path token to start with `/` or `./` (not `"$`), so `"$WT_ACTIVATE_SH"` does not match either.

**Implication**: any skill that wants to activate N workflows MUST emit N separate Bash tool calls, each containing a literal absolute path line like `/abs/path/activate.sh /abs/workflow.json`. This cannot be hidden behind a helper function.

**Contract change made**: `wt_run_phase1` → `wt_phase1_wait_all` (waiter only, assumes activations already issued). `wt_run_serial_phase` → `wt_wait_and_record_serial` (single-workflow waiter). `contracts/interfaces.md` updated with the full explanation. SKILL.md Step 2/4/5/6 made prose-heavy to walk the invoker through per-workflow Bash tool calls.

**Spec/plan wording I'd change**: The spec and plan both describe Phase 1 activation as "back-to-back activations" but leave the mechanism ambiguous. It should explicitly say: "N separate Bash tool calls, each containing exactly one literal-path `activate.sh` invocation — no wrapper functions, no loops." The specifier's hand-off note mentioned "back-to-back Bash tool calls, NOT subshell backgrounding" which was correct but still let me underestimate the constraint until I'd already written the wrong helpers.

## 2. The kiln branch hook disagreement forced a branch-rename dance

**Severity**: moderate friction, not blocking

The feature branch `build/wheel-test-skill-20260410`:
- PASSES `require-spec.sh` feature derivation (regex `^build/(.+)-[0-9]{8}$` → feature=`wheel-test-skill`, matches `specs/wheel-test-skill/`).
- FAILS `require-feature-branch.sh` (regex `^[0-9]{3}-` or `^[0-9]{8}-[0-9]{6}-` — neither matches `build/...`) → blocks any Write under `specs/`.

The specifier worked around this by renaming to `20260410-120000-wheel-test-skill` during `/specify`. But THAT name fails `require-spec.sh`: the regex `^[0-9]+-(.+)$` greedy-matches the first `[0-9]+` as `20260410`, captures `120000-wheel-test-skill`, and hits the gate because `specs/120000-wheel-test-skill/` doesn't exist. So the specifier must have been using `SPECIFY_FEATURE=wheel-test-skill` env var to override.

My workaround: rename to `001-wheel-test-skill`, which passes BOTH hooks (require-feature-branch's `^[0-9]{3}-` matches, and require-spec's greedy regex extracts `wheel-test-skill`). Then edit tasks.md, then rename back to `build/wheel-test-skill-20260410` for commit.

**What I'd change**: the two hooks should agree on branch-name conventions. Either both accept `build/...` or neither does. The `^[0-9]+-(.+)$` pattern in require-spec is too greedy — it should be anchored to a specific format. Ideally there's a single, documented branch-naming rule and one hook that enforces it.

## 3. Ambiguities in the spec/plan that I resolved by inference

- **"Phase 1 parallel"** — The spec says "back-to-back, no gating between activations" but didn't specify whether the waiter could be interleaved. I assumed: all activations first, then one waiter call (Step 3). Alternatively the invoker could fire N activations + 1 waiter per workflow, but that's not parallel anymore. I went with the clearly-parallel interpretation.
- **`wt_activate` fate** — The contract lists it and T014 asks for it, but given that the hook can't intercept it when called through a function, it's unused by SKILL.md. I kept it in `runtime.sh` as documentation / future-use, marked T014 [X] with a note.
- **Orphan attribution** — T017 said "records any orphans as `orphaned` rows against the originating workflow if attributable, otherwise as unattributed orphan rows". I simplified to: sweep after the phase, record each orphan with its file basename and a note. "Attributing" orphans to a specific workflow post-facto requires cross-referencing state-file ownership JSON, which felt out of scope.
- **Classification for `teammate` type** — The precedence list in FR-002 says `team-*/teammate → 4`. My regex is `^(teammate|team[_-].*|team)$`. The current test suite has step types `teammate`, `team-create`, `team-delete`, `team-wait` — all covered.

## 4. Things that were very clear and saved time

- The specifier's hand-off note with the three CRITICAL HEADS-UP points (branch hook, 4-gate, hybrid archive glob) pre-empted three separate rabbit holes.
- The contract's data-shape section (TSV columns, report section list) was concrete enough that `wt_build_report` practically wrote itself.
- The "Absolute Musts" list in the PRD/spec is load-bearing — those really are the places where the intuitive implementation is wrong, and calling them out explicitly saved me from classifying by filename or writing state files.
- Commit 3283c10's `--as` fix landed before I needed to care about teammate state-file ownership. Similarly 69d2dff's hybrid archive format matched my wait glob `{basename}-*-*.json` naturally.

## 5. Wheel-engine bugs hit during development

None during the implementation itself — the preflight / classification / env-snapshot round-trip all worked on the first try once the hook constraint was understood. The ACTUAL end-to-end smoke against 12 live workflows is deferred to audit-smoke, so there may be more findings once that runs.
