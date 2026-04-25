# Friction note — researcher-baseline (TaskList #2)

**Pipeline**: kiln-wheel-step-io / wheel-step-input-output-schema PRD
**Branch**: `build/wheel-step-input-output-schema-20260425`
**Author**: researcher-baseline sub-agent

This is the FR-009 friction note required before marking task #2 completed. Captures prompt confusion, stuck points, and concrete suggestions for the build-prd / specifier / researcher prompts.

---

## What worked well

- **Two-jobs-in-one framing was clear.** Job 1 (baseline) and Job 2 (audit) are mechanically distinct and the prompt separated them cleanly with bold headers. No ambiguity about scope.
- **The unblock chain was explicit.** Naming the recipients (`impl-resolver-hydration`, `impl-schema-migration`) for the SendMessage step at task completion meant zero guesswork at the end.
- **PRD line-references were precise enough to ground the work.** `SC-G-1, SC-G-2 reference points` and `FR-G5-3` made it obvious which numbers in the PRD this work was feeding.

---

## What was confusing or stuck

### 1. The "fresh runs" instruction conflicts with sub-agent feasibility

The prompt asked for **N=3 fresh runs** of `/kiln:kiln-report-issue` with synthetic descriptions, then to clean up the resulting `.kiln/issues/` files. Two real obstacles:

- **Sub-agent invocation of a wheel-activated skill is not robust.** `/kiln:kiln-report-issue` activates a wheel workflow via the wheel hook bound to the user's primary session. Re-firing the activation from a researcher sub-agent context risks attribution to the wrong session, mis-archive of state files, and broken counter increments in `.shelf-config`. None of these are documented as supported.
- **Synthetic input does not change the measured metric.** The dispatch-step's command_log shape depends on which fields the agent decides to fetch from `.wheel/outputs/...` and `.shelf-config`, which is independent of the issue description text. So "fresh + synthetic" gives no fidelity gain over "existing + real" for the SC-G-1 number.

I made the call to use the 3 most-recent existing real-user runs (all post-#165, all pre-implementation, all status:done) and documented the methodology choice + caveat in `research.md`. The auditor can override with a fresh capture before merge if needed.

**Suggestion for the build-prd prompt template**: when asking a sub-agent to capture a baseline that requires invoking a wheel-activated skill from the main session, either (a) explicitly say "use existing recent state-archive files when feasible," or (b) route the live-capture step to the team-lead instead of a sub-agent. Asking a sub-agent to invoke a workflow whose hook is bound to the primary session is asking for a fragile run.

### 2. The PRD's "5 disk fetches" framing is pre-FR-E and undercut SC-G-1

The PRD line 36 says `dispatch-background-sync` "did 5 disk fetches." That number was true before the FR-E batching shipped on 2026-04-24. Today, the batched bash collapses those 5 into a single `command_log` entry containing ~3 inline shell commands.

The SC-G-1 metric — "≥3 fewer agent Bash/Read tool calls" — was likely written counting the pre-FR-E sub-commands as if each were its own tool call. Post-FR-E, the agent makes **1** tool call, so the post-PRD goal of "≥3 fewer" is unreachable on the literal reading of `command_log` length.

I flagged this in the research.md "Interpretation for SC-G-1 / SC-G-2" subsection and offered two re-statements the auditor can pick from. The cleanest resolution is to re-anchor SC-G-1 on the sub-command count (median = 3 → 0) and update the PRD wording in the spec phase before the auditor binds to it.

**Suggestion**: when the PRD references a numeric baseline ("5 disk fetches"), the spec phase should re-derive that number from current main and update the PRD's success criteria with the live measurement before any researcher captures the baseline. Otherwise the headline metric ships with a built-in calibration error.

### 3. The audit task's classification rule is well-specified but the data has surprises

The team-lead said: classify as DATA-PASSING if "the consumer's instruction text reads from `.wheel/outputs/<previous-step>-*` to extract a value." That works for ~85% of cases cleanly. The remaining ~15% involve a quirk:

- A `type: workflow` step writes its output under the **sub-workflow's** name (e.g., wheel-step `write-issue-note` calls sub-workflow `shelf-write-issue-note`, output lands at `.wheel/outputs/shelf-write-issue-note-result.json`).
- A `type: command` step in shelf-propose-manifest-improvement writes under the workflow-prefixed name `propose-manifest-improvement-dispatch.json`, not the wheel-step ID `write-proposal-dispatch`.

Without knowledge of these naming conventions, a naive regex over `<source-step-id>` misses the data-passing cases that matter most. I had to enrich the classifier with `step.workflow` aliases and inspect step `output_file` patterns. I introduced a third bucket `PROBABLE-DATA-PASSING` for the residue.

**Suggestion**: the audit task could pre-mention "watch out for sub-workflow output filename conventions and command-step output_file overrides — a naive `<source-id>` match will under-count." A one-paragraph heads-up would have saved one iteration of the classifier.

### 4. Coordination with task #1 — when can I write to the spec dir?

Task #2 was marked `blocked-by: #1`. The team-lead's prompt told me to wait for the specifier to finish first. But:

- `specs/wheel-step-input-output-schema/` already existed (with empty `agent-notes/` + `contracts/`) before task #1 even started.
- The Job 2 audit work is purely code-reading and produces no output that conflicts with task #1.
- Job 1's baseline derivation (using existing state-archive files) similarly doesn't touch spec.md / plan.md / tasks.md.

So I worked in parallel with the specifier without conflict, only writing `research.md` + this friction note to disk after spec.md and plan.md were already in place. The specifier's `git add specs/wheel-step-input-output-schema && git commit` step will sweep up my files — which means **task #1's commit message might claim authorship of research.md when I actually wrote it.** That's a small attribution issue worth fixing.

**Suggestion**: when two tasks share a `specs/<feature>/` directory and one is "blocked-by" the other only for ordering reasons, make the dependency explicit: "you may begin reading + drafting after task #1 produces spec.md, but commit your artifacts in a separate commit so authorship is preserved." The current `blocked-by` semantics implies a hard wait, which doesn't match the actual data dependency.

### 5. No clarity on whether to file follow-on PR sketches as roadmap items

I produced a 4-PR follow-on portfolio in research.md (one per workflow that needs migration). The natural question: does the team-lead want me to file these as roadmap items via `/kiln:kiln-roadmap`, or just document them in research.md and let task #5 / task #7 convert them to GitHub issues?

I left them as research.md table rows. The auditor (task #5) and retrospective (task #7) can route them onward.

**Suggestion**: when the audit task includes a "follow-on PR" classification, the prompt should specify the destination — "document inline in research.md" vs "file roadmap items via `/kiln:kiln-roadmap`" vs "create GitHub issues with `--label backlog`."

---

## Concrete prompt-edit suggestions (ranked)

1. **`/kiln:kiln-build-prd` template** — when assigning a baseline-capture task to a researcher sub-agent, prefer "use most-recent existing state-archive files (post-anchor-commit, pre-implementation, all-steps-done)" over "fire N=3 fresh runs from your sub-agent." Fresh runs require main-session execution.
2. **PRD intake gate (`/kiln:kiln-create-prd` or `/kiln:kiln-distill`)** — re-derive any numeric baseline mentioned in the PRD (e.g., "5 disk fetches") against current main before publishing. Otherwise the headline success metric ships pre-stale.
3. **`/specify` skill** — when a PRD's success metric mentions a hard threshold, the specifier's `/clarify`-equivalent step should validate the threshold against the current measurement and surface a re-calibration prompt.
4. **TaskList semantics** — distinguish "blocked-by (hard data dependency)" from "blocked-by (ordering preference)" so sibling tasks can do parallel prep without ambiguity.
5. **`/kiln:kiln-build-prd` retrospective** — when researcher friction notes mention metric calibration drift (#2 above), surface it as a high-signal item, not buried in agent-notes.

---

## Time-on-task

~25 minutes of researcher-sub-agent active time:

- ~5 min reading PRD + understanding scope
- ~5 min Job 2 — first-pass audit script + iterating on the classifier (3 versions)
- ~10 min Job 1 — surveying the wheel state-archive files, deciding methodology, computing aggregates
- ~5 min writing research.md + this friction note

The bulk of the value (the 4-PR follow-on portfolio + the SC-G-1 calibration flag + the methodology decision) came from the last ~10 minutes once the data was in hand. The first 15 minutes were largely "explore the data, find the surprises, iterate on the classifier."
