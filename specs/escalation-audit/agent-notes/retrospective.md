# Friction Note — retrospective

**Phase**: Retrospective (task #6)
**Branch**: `build/escalation-audit-20260426`
**Date**: 2026-04-26
**Output**: GitHub issue #190 (https://github.com/yoshisada/ai-repo-template/issues/190)

## What this agent did

1. Ran `TaskList` safety-net gate — confirmed tasks #1–#5 all `completed` before proceeding (per team-lead's NON-NEGOTIABLE first step).
2. Read all 5 friction notes under `specs/escalation-audit/agent-notes/` (specifier, impl-themes-ab, impl-theme-c, audit-compliance, audit-tests-pr).
3. Cross-referenced with `blockers.md`, `git log main..HEAD`, and grepped `kiln-build-prd/SKILL.md` + `kiln-test/SKILL.md` + `wheel-test-runner.sh` to verify the SKILL.md-aspiration-vs-harness-reality gap concretely (line 140 of `wheel-test-runner.sh` only enumerates `test.yaml`-bearing dirs).
4. Synthesized 6 PI blocks in the bold-inline-marker format + filed retro issue #190 with both required labels (`build-prd`, `retrospective`).
5. Reported issue URL back to team-lead.
6. TaskUpdate #6 → completed (final action after this note).

## Friction observations

### F-1 — PI block format: code-fence-ban prevents quoting bash literals cleanly

The PI block format is "raw markdown, NEVER inside ``` code fences" so `parse-pi-blocks.sh` can extract via bold-inline markers. This is correct and load-bearing (commit a85bd63 / past parser-error issues), but it means when the **Current** or **Proposed** value contains literal `\n` newlines or shell snippets (e.g., `bash -c "echo \"\$VAR\" | grep"`), I have to inline-escape them in the prose with `\n` literals and embedded backticks. Two PIs in this run (PI-1 and PI-6) had multi-line **Current**/**Proposed** values that I rendered with `\n` markers inside the quoted string. That's parseable, but it's hard to read in the rendered issue. **PI candidate for retro-of-retros**: clarify whether multi-line **Current**/**Proposed** values should use literal `\n` markers (current shape, parseable), explicit `<br>` HTML breaks (rendered, but parser-friendly?), or a documented convention. Not surfacing as a PI block in #190 because it's a meta-concern about the retro format itself, not about this pipeline's prompts.

### F-2 — "Bold-inline markers, NOT in code fences" is reiterated 3× in the team-lead's brief

The team-lead's brief told me three times in the same message that PI blocks must NOT be code-fenced (NON-NEGOTIABLE marker, parser-error explanation, the "raw markdown — NEVER inside ``` code fences" line). I appreciate the emphasis (issue #170 / retros #166/#168 are direct lessons) but the triple-emphasis suggests the rule keeps being violated by retro agents. Worth folding into the retro-agent prompt as a single explicit `parse-pi-blocks.sh` self-check step: "after drafting your issue body, run `bash plugin-kiln/scripts/parse-pi-blocks.sh /tmp/retro-body.md` and ensure it parses N PI blocks, N == count(### PI-)". Not a PR-#189 prompt issue — this is retro-skill-side.

### F-3 — "Both labels required" is reiterated 2×

Same shape as F-2: the team-lead's brief flagged the `retrospective` label twice (NON-NEGOTIABLE marker + the issue #170/166/168 lesson explanation). The repetition suggests this gets dropped sometimes. I just used `--label "build-prd,retrospective"` on the gh CLI invocation and it worked first try. Not a PR-#189 prompt issue.

### F-4 — Retro-agent prompts could include a "PI block self-validation" step

After drafting the body file, the retro agent could grep the file for `^### PI-` count vs `^\*\*File\*\*:` count vs `^\*\*Current\*\*:` count vs `^\*\*Proposed\*\*:` count vs `^\*\*Why\*\*:` count — all 5 should be equal to N. If any differs, a PI block is malformed. I did this manually for #190's body (counted 6 PI headers, 6 File markers, 6 Current markers, 6 Proposed markers, 6 Why markers — all matched) but it could be a one-liner in the retro prompt template.

## What worked well

- **Both auditors handed off clean blockers.md.** SC-006 + FR-010 substrate gaps are documented with carve-out IDs (B-PUBLISH-CACHE-LAG carve-out 2b, B-1) — I just summarized the existing prose into the issue's "Proposed changes" section.
- **All 5 implementer/auditor friction notes were genuinely useful.** No "pipeline went fine, no notes" stubs — every note had substantive observations and at least one PI candidate. The framing in the team-lead's brief ("write friction notes per FR-009") clearly worked.
- **Specifier's "Open ambiguities deliberately deferred" section** was particularly useful for understanding which decisions were intentional vs which were guessed. PI-3 in #190 came directly from impl-themes-ab citing this format-deficit.
- **Cross-validation between agents.** impl-themes-ab and impl-theme-c independently flagged the same hook-bumped-artifacts staging hazard — confidence that PI-2 in #190 is real comes from two-source agreement, not one-implementer's preference.

## Time spent

~12m end-to-end:
- Safety-net + read 5 friction notes + blockers.md: ~4m
- Verify SKILL.md / wheel-test-runner.sh substrate gap concretely: ~2m
- Draft 6 PI blocks + issue body: ~5m
- File issue + this note + TaskUpdate: ~1m

## Deferrals / follow-ons

- F-1 (PI block format clarity for multi-line values) — not surfaced as a PI in #190 because it's about retro-skill-side conventions, not this pipeline's prompts. Could be a separate issue if the format-ambiguity recurs.
- F-2 + F-4 (retro-agent prompt could fold "PI block self-validation" into a one-liner self-check step) — same: retro-skill-side, not pipeline prompts.
