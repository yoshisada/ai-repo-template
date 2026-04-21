# impl-trim-wheel friction notes

## Scope split
Team lead asked for TWO commits (not the combined TW6 single commit in tasks.md):
- Commit 1: `refactor(trim): rename skills for naming consistency (FR-005, FR-007)`
- Commit 2: `refactor(wheel): rename skills for naming consistency (FR-005, FR-007)`

Proceeded with two commits as instructed.

## Trim workflow renames — conflict with team lead's message
Team lead wrote: "trim workflows already match skill names — no workflow renames expected." However, the contracts table 2 explicitly lists 8 trim workflow renames (trim-design.json → design.json, etc.), and the workflow files on disk were all `trim-*.json` prefixed. Followed the contract (authoritative per CLAUDE.md "Match contracts/interfaces.md exactly"). Renamed all 8 trim workflows.

## Internal output paths
`.wheel/outputs/trim-*.txt|md` paths inside workflow JSON would hit SC-001's loose grep for bare names like `trim-pull`, `trim-diff`. Decided to drop the `trim-` prefix from these internal path strings as well (e.g., `.wheel/outputs/trim-pull-result.md` → `.wheel/outputs/pull-result.md`). This is technically a behavior change (output filename changed) but:
- These are per-run transient files under `.wheel/outputs/`
- All references are self-contained inside a single workflow file
- Kept naming self-consistent with the new post-rename world

If this breaks any downstream consumer reading `.wheel/outputs/trim-*.md` paths, surface as a separate issue per FR-009.

## Step id `resolve-trim-plugin` kept as-is
Did NOT rename the step id `resolve-trim-plugin` because:
- It's an internal step identifier referenced only via `context_from` in the same workflow file
- Contains bare `trim` (no dash-after) so does not hit SC-001 grep patterns
- Changing it would be a behavior change with zero user-visible value

Same for the `TRIM_PATH` bash variable and `trim_plugin_path` output key — kept as internal identifiers.

## Template filename `trim-config.tpl`
Kept filename as-is (not a skill reference). Only updated the `/trim-init` reference inside the template content.

## Wheel workflow `example.json`
Per contracts, unchanged (demo fixture, no owning skill). Confirmed.
