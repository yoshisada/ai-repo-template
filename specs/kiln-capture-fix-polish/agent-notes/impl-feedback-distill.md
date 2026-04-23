# Agent Notes — impl-feedback-distill

Track: Phases C + D + E (T010..T021).

## Friction observed

1. **Deferred tool schemas.** At session start, `TaskGet`, `TaskList`, `TaskUpdate`, and `SendMessage` were deferred and had to be loaded via `ToolSearch select:...` before use. This is a predictable startup cost but not obvious from the skill/task instructions — a quick one-liner in the brief ("ToolSearch select:TaskGet,TaskList,TaskUpdate,SendMessage before starting") would save ~1 round-trip per new team member.

2. **Noisy working tree at commit time.** `git status` showed ~40 unrelated `.wheel/history/*` + `.kiln/logs/*` + `.shelf-config` + `VERSION` + `plugin-*/package.json` modifications from concurrent background/hook activity during the session. I committed only the Phase-owned files via explicit `git add <paths>` — but had the team brief not said "Commit per phase" with an implicit narrow scope, a wide `git add -A` would have swept in a lot of cross-cutting churn. Worth making explicit in future implementer briefs: "commit only files you wrote in this phase."

3. **Sibling-implementer file overlap risk was low.** Plan.md's file ownership table was accurate — Phase A/B owner (impl-fix-polish) touched only `plugin-kiln/skills/kiln-fix/**` while I touched `kiln-feedback/**`, `kiln-distill/**` (renamed), `kiln-next/SKILL.md`, `continuance.md`, `architecture.md`, `CLAUDE.md`. No merge conflicts, no SendMessage coordination needed. The parallel-track design held.

4. **`kiln-next` whitelist placement is subtle.** The whitelist lives in two places (`plugin-kiln/skills/kiln-next/SKILL.md:248` and `plugin-kiln/agents/continuance.md:69`) with identical shape. Easy to update one and miss the other. The grep catches it but the `kiln-next` SKILL.md's line 342 ("Suggested next: ... `/kiln:kiln-issue-to-prd`") is a separate reference — three distinct sites for a single command name.

5. **One cosmetic deprecation-breadcrumb caught by the strict grep gate.** I initially wrote `Renamed from /kiln:kiln-issue-to-prd (Apr 2026)` as a migration note in CLAUDE.md's new `/kiln:kiln-distill` entry. That is textbook "intentional historical breadcrumb" — but the SC-006 grep gate requires literal zero live hits, so I stripped the breadcrumb. Future: if we want migration breadcrumbs to be allowed, the grep in SC-006 / FR-014 needs a named exemption list (e.g., `| grep -v 'Renamed from'`).

## What went well

- `git mv` rename preserved history cleanly (`git log --follow plugin-kiln/skills/kiln-distill/SKILL.md` will walk back through `kiln-issue-to-prd` commits).
- Single-file SKILL.md changes meant no contract coordination with impl-fix-polish beyond the shared decision-2 name (kiln-distill) the team-lead handed us at unblock.
- Phase C created a brand-new file; Phase D was a focused rewrite of the renamed file; Phase E was 4 small edits + 2 CLAUDE.md additions. Minimal blast radius per commit — if audit finds a regression, the three phase commits are individually revertable.

## Suggestions for future runs

- For hard-rename features, codify the "breadcrumb exemption" question in plan.md so implementers don't have to judgment-call it mid-sweep.
- The distill skill's narrative shape is now LONG (~250 lines of markdown). If it grows another major capability, split the PRD-rendering rules into `contracts/` or a separate reference doc so the SKILL.md body stays scannable.
