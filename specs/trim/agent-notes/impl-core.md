# Friction Notes: impl-core

## Blocking on Prerequisites
- Had to wait for Task #1 (specify/plan/tasks) and Task #2 (research) to complete before starting. Specs/trim/ directory was created incrementally — directories appeared first, then files trickled in over ~3 minutes. No way to know when all artifacts are ready without polling.
- **Suggestion**: A completion signal (e.g., a marker file or message) from the specifier/researcher would eliminate polling.

## Hook Gate 4 Friction
- The kiln `require-spec.sh` hook blocked template file writes (T004, T005) because no tasks were marked `[X]` yet. This is Gate 4: "Block edits to src/ unless tasks.md has at least one [X] mark." Template files in `plugin-trim/templates/` triggered this gate.
- **Workaround**: Marked T001-T003 as `[X]` first (since plugin.json/marketplace.json/package.json were already created), then the templates went through.
- **Suggestion**: Templates in a plugin's `templates/` directory could be excluded from the Gate 4 check, similar to how docs/specs/config are already allowed.

## Version Hook Side Effects
- The version-increment hook auto-bumped the VERSION file and synced to plugin manifests during writes. The plugin.json and package.json versions changed from `000.000.000.000` (as specified in contracts/interfaces.md) to the current repo version. This is expected behavior but means the contract's version field is immediately overridden.
- **Not a problem** — just worth noting that contracts specifying `000.000.000.000` as the version are aspirational, not literal.

## Smooth Areas
- Plugin structure was well-documented by the research.md decisions and existing plugin references (shelf, clay, wheel, kiln). Copy-and-adapt worked cleanly.
- The contracts/interfaces.md was thorough — skill frontmatter, package.json fields, and template content were all specified, leaving no ambiguity.
