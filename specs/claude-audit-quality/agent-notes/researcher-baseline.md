# Agent friction note — researcher-baseline

## Confusing / hard-to-measure

1. **"Audit duration" is ambiguous when the audit is a Skill, not a script.** The PRD's NFR-001 says "audit duration MUST NOT increase by more than 30%." A Skill invocation has two cost regions: bash-side (rubric load, cheap rules, cache fetch, reader) and editorial-side (LLM calls). The bash side is shell-measurable, deterministic, and ~0.79s median on this repo. The editorial side is intrinsically model time, varies by routing, and isn't `time`-able from a sub-agent's bash. The team-lead's brief acknowledged this and let me pick the bash-side scope — but the PRD itself doesn't say which scope NFR-001 binds to. The auditor (task #5) needs the spec to pin this down or NFR-001 will be untestable.

2. **The latest audit log was a smoke-test-scope run, not a full audit.** It's labeled as such in its own `## Smoke-test verification` section. I used its byte counts as the NFR-003 reference because no other recent log exists, but the auditor needs to be aware that a *full* audit on unchanged inputs will produce different byte counts than the smoke-scope log. NFR-003 ("byte-identical post-implementation") is a within-scope gate, not a cross-scope one.

3. **Signal-type categories don't quite match what the rubric emits.** The team-lead's brief asked for a breakdown by `signal_type` ∈ {substance / freshness / bloat / coverage / external}. The rubric does emit `signal_type` field per rule, but `external` isn't a `signal_type` value — it's a *separate section* (`## External best-practices deltas`) with its own table shape. I rendered the breakdown honoring both: the four-bucket signal-type table for in-summary signals + a one-liner for the external-deltas count. If the spec intends `external` to be a real signal_type going forward (Theme C of the PRD?), that's a rubric-schema change and the spec should call it out.

4. **The project-context reader is currently broken on this repo.** It hits the jq 1.7.1-apple control-character bug (the same one documented in the most recent commit on this branch and in the latest audit log's `## Notes`). The benchmark tolerates it with `|| true`, but a faithful "what does the audit actually do" measurement should ideally include a working reader. Fix priority is on the reader, not on this PRD's scope.

5. **No clear "main vs build branch" baseline distinction for current-baseline.** This branch's CLAUDE.md, rubric, best-practices cache, and `plugin-kiln/scripts/context/` files are byte-identical to `main` (no claude-audit changes have landed on this build branch yet — the branch was just created and the PRD distilled). So the "current main" baseline === "current branch" baseline. If the PRD changes that prerequisite (e.g., the implementer lands a partial change before the auditor re-times), the auditor should re-baseline from a known-clean checkout, not trust this number.

## What guidance was missing

- **No worked example of how a sub-agent should time a Skill.** The team-lead said "time it via wall-clock between Skill invocation and output drop" but my tool surface here is bash + Read/Write — not the foreground Skill harness. The fallback ("measure the underlying script work via bash") was the right escape hatch, but we should write that pattern into the kiln researcher-runner / researcher-baseline conventions so the next person doesn't re-derive it.

- **NFR-001 + NFR-003 didn't tell me what scope to bind to.** Both NFRs were stated as "duration" / "byte-identical" without saying *which run shape* counts. I picked defensible scopes and documented them in research.md, but the spec needs explicit text. The auditor will otherwise get to make this call mid-audit, which is exactly the kind of unspecified gate that retros catch.

## PI proposals (bold-inline format)

**File: `plugin-kiln/agents/researcher.md` / `plugin-kiln/agents/research-runner.md` (whichever role-instance owns "capture a baseline measurement")** — **Current**: agent prompts assume the measurement target is shell-runnable. **Proposed**: add an explicit decision tree — "if target is a Claude Code Skill, measure (a) the bash-side script work the Skill performs OR (b) the wall-clock between Skill-invocation and output drop in main chat; document which scope you chose and why; pin the scope to a specific NFR ID." — **Why**: this PRD's NFR-001 had no such guidance and I had to derive scope from first principles. The next baseline-capture task will hit the same gap.

**File: `plugin-kiln/skills/kiln-claude-audit/SKILL.md` (Step 4 — Required rendering rules)** — **Current**: NFR-002 says two runs on unchanged inputs are byte-identical, but the SKILL emits a `## Smoke-test verification` trailer on smoke-scope runs that *isn't* part of the contracted output shape, blurring the comparison. **Proposed**: either (a) drop the Smoke-test trailer entirely (smoke is a caller decision, not a Skill output mode), or (b) gate it behind an explicit `--smoke` flag and document the flag in the SKILL header. — **Why**: when the next baseline task tries to compare smoke-vs-full runs against NFR-003, it'll pull two different shapes off the same Skill and get false-positive drift. This bit me here — I had to caveat the byte counts because the latest log carries a non-contract trailer.

**File: `plugin-kiln/scripts/context/read-project-context.sh`** — **Current**: emits jq parse errors on `.kiln/roadmap/items/*.md` frontmatter under jq 1.7.1-apple (control-character class bug). **Proposed**: surface this as a tracked issue (it's been hit at least twice now — this audit and the most recent commit on this branch). Either upgrade the jq version requirement, switch to python3 + PyYAML for frontmatter parsing, or sanitize control chars in the awk step before piping to jq. — **Why**: the reader is the FR-013 anchor for the audit ("every preview MUST cite a project-context signal"). A degraded reader degrades every audit it touches. Out of scope for *this* PRD but worth flagging in the spec's "out of scope" or "blockers" list.

## Coordination metadata

- Task: #1
- Started: 2026-04-25 (session-relative)
- Owner: researcher-baseline
- Blocks: task #2 (specifier needs the median number documented above)
- Output artifacts: `specs/claude-audit-quality/research.md`, this note
