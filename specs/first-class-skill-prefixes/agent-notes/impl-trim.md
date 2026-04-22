# impl-trim friction notes

## Summary
Phase T (10 skill renames + 7 workflow renames + full in-plugin cross-ref sweep) completed cleanly.
Final grep gate: zero live command-shape hits for the 10 old bare names inside `plugin-trim/`.

## What went well
- Layout is tidy: `plugin-trim/` has only `skills/`, `workflows/`, `templates/`, plus `.claude-plugin/`
  and `package.json`. No `agents/`, `hooks/`, or `scripts/` dirs, which narrowed the sweep surface.
- Every SKILL.md frontmatter `name:` already matched its directory name, so the rename mapping was
  1:1 with no surprises.
- Every workflow JSON had a simple top-level `"name"` field and `"activate_name": null`, so only
  the `name` field needed updating post-rename.
- One workflow (`library-sync.json`) is intentionally NOT a skill correspondence — left as-is per
  T-018. This is documented in the workflow name itself (`library-sync`, not a bare skill name).

## Friction / surprises
1. **BSD sed vs `\b`**: macOS `sed` doesn't support `\b` word boundaries, which made my first
   sweep pass silently no-op. Switched to `perl -i -pe 's{...\b...}{...}g'` which handled it
   cleanly. Worth flagging to other phase implementers if they hit the same issue.
2. **`/trim:trim-<name>` reads awkwardly** but is correct under the new convention — the
   plugin namespace (`trim:`) plus skill name (`trim-<action>`) naturally doubles the prefix.
   This is FR-001 behavior, not a bug. Example:
   - `/wheel:run trim:trim-pull` (was `/wheel:run trim:pull`)
   - Workflow `"name": "trim-pull"` invoked via plugin `trim`.
3. **Sweep surface was wider than just the 10 skill SKILL.md files**: cross-refs appeared in
   every workflow JSON's inline bash (e.g., `"Run /trim:init first"` inside error messages),
   and in `templates/trim-config.tpl`. The perl sweep caught all of them because it matched
   across all file types under `plugin-trim/`.
4. **The `wheel:run trim:<workflow>` form**: activations use the workflow's `name` field, not
   the skill's name. Since every non-init skill has a matching workflow, both the skill name
   and the workflow name moved together — no divergence. `trim-init` is the one skill without
   a dedicated workflow JSON (it runs inline in the SKILL.md).

## Cross-plugin heads-up
No trim references found in other plugins during my sweep (only searched inside
`plugin-trim/`). If the auditor's cross-repo grep turns anything up, that would need a
follow-up.

## Verification evidence
All five grep categories returned "none":
- `/trim:<oldname>` pattern: no hits
- `wheel:run trim:<oldname>` (excluding `library-sync`): no hits
- Bare `trim:<oldname>` in command-shape contexts: no hits
- Workflow JSON `"name": "<oldname>"`: no hits
- SKILL.md frontmatter `^name: <oldname>$`: no hits

Directory state: every `plugin-trim/skills/*/` is `trim-<action>`. Every workflow JSON except
`library-sync.json` is `trim-<action>.json` with matching internal `name`.
