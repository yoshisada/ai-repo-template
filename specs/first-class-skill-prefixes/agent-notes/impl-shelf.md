# impl-shelf friction notes

## Summary

Phase S completed: 8 skill renames, 4 workflow JSON renames, frontmatter + internal cross-refs updated, `shelf:propose-manifest-improvement` workflow reference in `shelf-sync.json` rewired to `shelf:shelf-propose-manifest-improvement`. One commit on `build/first-class-skill-prefixes-20260421`.

## What went well

- Shelf was small (8 skills, 4 workflows) and had no `agents/`, `hooks/`, or skill listings in `plugin.json`. The blast radius was tight — almost all command-shape refs lived in SKILL.md bodies and a few workflow JSON instruction strings.
- `plugin-shelf/scripts/` had zero command-shape references (only common English matches like "sync", "create" in variable names / comments) — so the script sweep was a no-op.
- Wheel's workflow reference format `plugin:name` resolves by the workflow JSON's `"name"` field, not its filename. Confirmed by reading `plugin-wheel/lib/workflow.sh:240-262`. Since I renamed the `"name"` to `shelf-propose-manifest-improvement`, I had to rewrite the caller reference in `shelf-sync.json` from `shelf:propose-manifest-improvement` to `shelf:shelf-propose-manifest-improvement`. If you forget to update the caller you get a silent resolution failure at runtime.

## Friction points

1. **sed vs Edit for frontmatter batch update.** First batch of 8 parallel Edit calls failed with "File has not been read yet" — the tool requires a prior Read even when the existing content is visible from a previous bash `head` output. Fell back to `sed -i ''` per file, which worked but means no fine-grained review per edit. Future implementers: either Read every file first, or use sed for pure frontmatter-line swaps.

2. **Two levels of `shelf:` prefix can look wrong at a glance.** Strings like `/wheel:run shelf:shelf-propose-manifest-improvement` and `# shelf:shelf-create — Scaffold New Project` visually read as a typo. They are correct: the first `shelf:` is the plugin namespace, the second `shelf-` is the skill's first-class prefix. Anyone reviewing the diff should keep that in mind — it's not a duplication bug.

3. **Cross-plugin references I noticed but did NOT edit** (per brief):
   - `plugin-kiln/skills/kiln-report-issue/SKILL.md:52` — `` `shelf:sync` ``
   - `plugin-kiln/skills/kiln-fix/SKILL.md:377` — `` `shelf:sync` ``
   - `plugin-kiln/skills/kiln-mistake/SKILL.md:8,67` — `` `shelf:sync` ``
   - `plugin-kiln/workflows/kiln-mistake.json:14` (agent instruction) — contains `shelf:<something>` in agent-facing prose
   These should be picked up by impl-kiln's in-plugin sweep (K-037 through K-043). Flagging to auditor as a safety net.

4. **Unexpected agent-facing prose in workflow JSON instruction strings.** `shelf-propose-manifest-improvement.json` references its own skill name (`shelf:propose-manifest-improvement`) in four places inside long agent instructions, plus `kiln:mistake`, `kiln:report-issue`, `shelf:sync`. All four needed rewrites. If you grep only for filename/step-id/`activate_name` fields you'll miss these. Always grep the raw JSON text.

## Verification done

- `ls plugin-shelf/skills/` — all 8 dirs prefixed with `shelf-` (S-verify).
- Per-skill: `SKILL.md` frontmatter `name:` equals the dir name (exact match for all 8).
- `grep -rn 'shelf:(create|feedback|propose-manifest-improvement|release|repair|status|sync|update)\b' plugin-shelf/` returns zero hits.
- `jq .` on all four renamed workflow JSONs implicit via sed success; wheel reference in `shelf-sync.json` updated to match the renamed child workflow's `"name"`.
