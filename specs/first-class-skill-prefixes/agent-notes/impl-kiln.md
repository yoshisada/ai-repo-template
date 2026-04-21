# impl-kiln friction note

Implementer for Phase K (plugin-kiln) of the first-class-skill-prefixes pipeline.

## What was clear

- The rename table in `plan.md` + `tasks.md` was unambiguous for the 27 renames and 7 no-ops. Directory + frontmatter + workflow JSON filename were easy to execute mechanically.
- FR-008 (pipeline-internal skills stay bare) is phrased tightly in both spec and plan — easy to translate into a rewrite regex that simply omits `specify|plan|tasks|implement|audit` from the OLD list.
- The `/kiln:next` whitelist (FR-005) was already colocated in the skill body with a clear "allowed" / "blocked" / "replacement" structure, so updating it in-place was straightforward.

## What was ambiguous

1. **Cross-plugin references inside plugin-kiln.** The brief said "update every internal cross-reference inside plugin-kiln/" but the in-plugin sweep task list (K-039 to K-043) focuses on bare `/old-kiln-name` forms. Cross-plugin references like `shelf:sync`, `clay:create-repo`, `wheel:run` inside plugin-kiln skills/agents/workflows were not explicitly called out as my responsibility — they could arguably belong to the auditor's Phase X. I chose to rewrite them in my phase because:
   - My workflow JSONs (`kiln-mistake.json`, `kiln-report-issue.json`) call `shelf:sync` and `shelf:propose-manifest-improvement` as sub-workflows. After Phase S lands, those names become `shelf:shelf-sync` / `shelf:shelf-propose-manifest-improvement`. Leaving them bare would silently break my workflows post-merge.
   - The `/kiln:next` whitelist references `/clay:create-repo`. FR-005 says the whitelist must list every first-class command in its new prefixed form — that implies cross-plugin prefixing too.
   - Next time: spec should explicitly assign cross-plugin rewrites inside a given plugin's files to that plugin's owner, OR explicitly reserve them for the auditor. Right now it's a judgment call per phase.

2. **Filepath false positives vs command shape.** The K-044 verification regex `/(name)\b` matches things like `.kiln/logs/next-<timestamp>.md` (matches `/next`), `/scripts/fix.md` (matches `/fix`), `@vitest/coverage-v8` (matches `/coverage`), `.specify/memory/constitution.md` (matches `/constitution`). These are all legitimate filesystem paths, not commands. A naive `grep` for the K-044 regex returns hundreds of these false positives. I wrote a tighter regex with a negative lookbehind `(?<![\w./])` to exclude path-prefix contexts, and a negative lookahead `(?!\.[a-zA-Z])` to exclude filename suffixes (e.g. `/fix.md`, `/next-<ts>.md`). Recommend the plan's verification step (K-044) call out these classes of false positives, or provide a tighter regex, because the literal "zero hits from the listed regex" bar is unreachable without this refinement.

3. **Pre-existing dangling references.** `plugin-kiln/skills/fix/SKILL.md` had references to `/fix-diagnose` and `/fix-fix` — commands that don't exist (the debug loop was inlined into `/fix` at some point, but these references weren't cleaned up). My rename regex turned them into `/kiln:kiln-fix-diagnose` / `/kiln:kiln-fix-fix`, which are also dangling. I repaired them to refer to the actual helper scripts (`scripts/debug/diagnose.md`, `scripts/debug/fix.md`). Flagging as a pre-existing issue surfaced by this refactor — there may be similar stale references elsewhere.

4. **`.gitignore` collision with `coverage/`.** The repo's `.gitignore` contains `coverage/` (for test-coverage output), which matched `plugin-kiln/skills/coverage/SKILL.md` — making it untracked. `git mv` fails with "source directory is empty" because git sees no tracked files in the source. I worked around with a plain `mv` and `git add` after. Next time: either scope-exclude `plugin-kiln/skills/coverage/` in `.gitignore` OR consider whether this skill needs a different name (it's misleading since the skill is about checking coverage, not the output of coverage tools).

5. **git mv + content edits on same run confuse ls-files.** After `git mv` of many directories + frontmatter sed edits inline, `git ls-files` returned a stale view that omitted some of the renamed files. My first sweep-rewrite pass used `git ls-files` to enumerate targets and silently skipped some newly-renamed files. I switched to `os.walk` on the filesystem to get full coverage. Worth documenting in the plan: "for this kind of rename-plus-content-edit pass, walk the filesystem, not the git index."

## What would be better next time

- **Explicit cross-plugin rewrite ownership.** The plan should say, for each phase: "within your plugin's files, rewrite cross-plugin references to other plugins using their planned new names." Or assign them all to the auditor.
- **Tighter K-044 regex.** The current `/(...)\b` regex has a high false-positive rate against filesystem paths. Suggest a refined version such as `(?<![\w./])/({patterns})\b(?!\.[a-zA-Z])` and document which contexts are legitimately excluded (filepath fragments, log paths, filenames with extensions).
- **Batch primitive.** A `/kiln:rename-skill <old> <new>` helper that does `git mv` + frontmatter update + cross-ref sweep atomically would reduce error surface. This refactor touched 27 skills and hit three distinct classes of edge cases; a dedicated primitive would make it cheap.
- **Mistake capture.** Consider filing a `kiln:mistake` for the "used `git ls-files` after mass rename and got partial file set" trap — it's the kind of thing a future agent doing similar work would benefit from reading.

## Summary

27 directories renamed, 27 frontmatter `name:` fields updated, 2 workflow JSON files renamed + internal `name` fields updated, 236 in-plugin command-shape cross-references rewritten (`/<old>` → `/kiln:kiln-<old>`, `kiln:<old>` → `kiln:kiln-<old>`), 7 cross-plugin bare references rewritten (`shelf:sync` → `shelf:shelf-sync`, etc.), 2 stale `/fix-diagnose` / `/fix-fix` references repaired to script-path references. 5 pipeline-internal skills (`audit`, `implement`, `plan`, `specify`, `tasks`) and 2 already-prefixed skills (`kiln-cleanup`, `kiln-doctor`) verified unchanged. Zero remaining command-shape hits against the old bare names in plugin-kiln/.
