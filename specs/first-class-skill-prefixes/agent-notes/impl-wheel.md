# impl-wheel friction notes

Phase W of `first-class-skill-prefixes`. All 7 wheel skills renamed (`create`, `init`, `list`, `run`, `status`, `stop`, `test` → `wheel-<action>`). No NO-OPs. `plugin-wheel/workflows/example.json` left as-is (template, not a skill correspondence). `plugin-wheel/.claude-plugin/plugin.json` does not enumerate skills.

## Driving motivation

Per the brief: the user's preference for `wheel-stop` (and other plugin-prefixed skill names) was the motivation for this whole feature. Everything below should be read in that light — anything that makes future renames painful is a bug.

## What went smoothly

- `git mv` + frontmatter edit + grep sweep was entirely mechanical for 7 skills.
- The command-shape regex `/wheel:(create|init|list|run|status|stop|test)\b` surfaced every real reference without false positives. The collision-with-English concern called out in the task brief did not materialize — all hits were genuine command refs, because I anchored on `wheel:` (which never appears incidentally).
- Wheel's engine libs (`dispatch.sh`, `engine.sh`, `workflow.sh`) had only **one** command-shape reference each (a comment explaining who calls them). Those libs dispatch by workflow name, not skill name, so the rename didn't touch dispatch logic.

## Friction / mechanics-of-renaming observations

### 1. Filesystem-path references in SKILL.md are parallel to command references and easy to miss

`plugin-wheel/skills/wheel-test/SKILL.md` contains ~8 lines like `source "${WT_REPO_ROOT}/plugin-wheel/skills/test/lib/runtime.sh"`. These are shell `source` paths, not command references. My command-shape regex did NOT catch them — I only noticed because a second, broader grep (`plugin-wheel/skills/(create|init|list|run|status|stop|test)/`) was in my mental checklist.

**Implication**: future rename passes MUST include a filesystem-path-shape sweep as well as a command-shape sweep. A wheel skill that sources its own sub-library via an absolute-ish path will silently break after a `git mv` until those paths are rewritten. Consider baking this into the phase-sweep rubric: `grep "plugin-<name>/skills/<old>/"` alongside `grep "/<name>:<old>"`.

### 2. Multi-line frontmatter `description` fields carry self-referential command examples

Every wheel skill's frontmatter `description` contains at least one example invocation like `Usage: /wheel:create <description>`. These are inside YAML frontmatter, so they're documentation/discovery surface, not executable commands — but they still need updating for consistency. Easy to overlook because "frontmatter" mentally reads as "metadata, not content."

**Implication**: the rename checklist should call out frontmatter `description:` explicitly as a sweep target.

### 3. The user-facing command path becomes `/wheel:wheel-<action>`

Worth flagging prominently: the slash-command path for a renamed skill is `/<plugin>:<skill-name>`, which after this PR is `/wheel:wheel-<action>`. That's the "wheel-stop" ergonomics the user explicitly wanted. But it does mean every doc example goes from three characters (`/wheel:stop`) to eleven (`/wheel:wheel-stop`). I updated all of them verbatim inside `plugin-wheel/`, but the breaking-change note in the PR body must call out the muscle-memory cost for consumers.

### 4. Stale `specs/wheel:test-skill/` path typo fixed in passing

`plugin-wheel/skills/wheel-test/SKILL.md` had two references to `specs/wheel:test-skill/contracts/interfaces.md` (colon where a hyphen belonged — the real spec dir is `specs/wheel-test-skill/`). My grep regex caught them because `test` is an alternation match after `wheel:`. Both were broken filesystem paths regardless of this PR. I corrected them since they were directly adjacent to in-scope edits and the fix is two characters. Flagging here so the auditor does not assume this was part of the rename spec.

### 5. Shared `tasks.md` multi-writer churn slows down progress

While I was working, multiple Phase implementers were updating `tasks.md` concurrently. I hit several `File has been modified since read` errors trying to mark W-* rows `[X]`. Pattern: re-Read, re-Edit, repeat until the write lands. Mechanical but lossy — on a five-implementer feature you spend a measurable chunk of time retrying. Worth considering a per-phase tasks file (e.g., `tasks-phase-w.md`) for future large multi-agent renames, or a lockless patch-style update tool.

## Verification run

- `ls plugin-wheel/skills/` → all 7 entries start with `wheel-`.
- Command-shape grep (`/wheel:(create|init|list|run|status|stop|test)\b`) inside `plugin-wheel/` → zero hits.
- Filesystem-path grep (`plugin-wheel/skills/(create|init|list|run|status|stop|test)\b`) → zero hits.
- Frontmatter `name:` matches directory name for all 7 skills.

## Out of scope (flagged for auditor)

Cross-plugin references to wheel skills live in every other plugin's workflows and skills (e.g., other plugins that call `/wheel:run`, `/wheel:status`, `/wheel:stop`). Those are Phase X (auditor) scope per the brief. I did not touch anything outside `plugin-wheel/`.
