# Quickstart: Trim Design Lifecycle

## What's Being Built

4 new skills and 3 wheel workflows for the trim plugin (`plugin-trim/`), adding design lifecycle management: edit, verify, redesign, and user flow tracking.

## Deliverables

| Deliverable | Path | Type |
|-------------|------|------|
| /trim-edit skill | `plugin-trim/skills/trim-edit/SKILL.md` | Markdown |
| /trim-verify skill | `plugin-trim/skills/trim-verify/SKILL.md` | Markdown |
| /trim-redesign skill | `plugin-trim/skills/trim-redesign/SKILL.md` | Markdown |
| /trim-flows skill | `plugin-trim/skills/trim-flows/SKILL.md` | Markdown |
| trim-edit workflow | `plugin-trim/workflows/trim-edit.json` | JSON |
| trim-verify workflow | `plugin-trim/workflows/trim-verify.json` | JSON |
| trim-redesign workflow | `plugin-trim/workflows/trim-redesign.json` | JSON |
| Plugin manifest update | `plugin-trim/.claude-plugin/plugin.json` | JSON |

## Key Patterns

- Skills follow the pattern in `plugin-shelf/skills/shelf-sync/SKILL.md`
- Workflows follow the pattern in `plugin-shelf/workflows/shelf-create.json`
- Plugin path resolved at runtime via `installed_plugins.json` (same as shelf)
- Command-first/agent-second workflow pattern
- Step outputs written to `.wheel/outputs/`

## No-Go List

- Do NOT auto-sync Penpot changes to code (edit and redesign leave changes in Penpot)
- Do NOT use pixel-diffing for visual comparison (use Claude vision)
- Do NOT commit screenshots to git (store in `.trim-verify/`, gitignored)
- /trim-flows does NOT need a wheel workflow (simple file CRUD)
