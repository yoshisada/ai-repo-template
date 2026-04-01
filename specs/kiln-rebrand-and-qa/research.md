# Research: Kiln Rebrand, Infrastructure & QA Reliability

**Date**: 2026-03-31
**Feature**: [spec.md](./spec.md)

## Research Tasks & Findings

### 1. Skill Directory Rename Impact

**Decision**: Rename skill directories by removing `speckit-` prefix (e.g., `speckit-specify` -> `specify`). The Claude Code plugin system discovers skills by scanning the `skills/` directory — directory name becomes the skill name.

**Rationale**: Claude Code auto-discovers skills from directory names. Renaming directories changes the skill names automatically. No plugin system configuration needed beyond the directory rename.

**Alternatives considered**:
- Aliasing old names to new (rejected — plugin system doesn't support aliases, and maintaining both adds confusion)
- Keeping old names with new prefix (rejected — defeats the purpose of the rebrand)

### 2. npm Package Rename Strategy

**Decision**: Publish new package `@yoshisada/kiln` and deprecate `@yoshisada/speckit-harness` with a deprecation message.

**Rationale**: npm supports package deprecation via `npm deprecate`. This is the standard approach — users running `npm install @yoshisada/speckit-harness` will see the deprecation notice directing them to `@yoshisada/kiln`.

**Alternatives considered**:
- Unpublishing the old package (rejected — npm policy restricts unpublishing after 72 hours, and it breaks existing installs)

### 3. Cross-Reference Update Scope

**Decision**: Update all internal cross-references within SKILL.md files that reference other skills using the old `speckit-harness:speckit-*` format.

**Rationale**: Skills reference each other (e.g., build-prd references speckit-specify). These must all use the new `kiln:*` format. A grep for `speckit` across all plugin files identifies every reference.

**Alternatives considered**: None — this is a mechanical find-and-replace task.

### 4. .kiln/ Directory Git Tracking Strategy

**Decision**: Track `.kiln/workflows/` and `.kiln/issues/` in git. Exclude `.kiln/agents/`, `.kiln/qa/`, and `.kiln/logs/` via .gitignore.

**Rationale**: Workflow definitions and issues are authored content that should be version-controlled. Agent run logs, QA test artifacts, and pipeline logs are transient outputs that would bloat the repository.

**Alternatives considered**:
- Track everything (rejected — agent logs and QA screenshots would bloat repos)
- Track nothing (rejected — issues and workflows need version control for team collaboration)

### 5. QA Version Verification Approach

**Decision**: Version check is implemented as instructions in the qa-engineer agent markdown and skill SKILL.md files, not as a separate script. The agent reads VERSION file and checks the app output.

**Rationale**: This plugin consists of markdown instructions for Claude Code agents, not executable code. The "implementation" is adding pre-flight instructions that the agent follows. No new scripts needed.

**Alternatives considered**:
- Shell script for version comparison (rejected — the agent needs to interact with the running app via /chrome tools, which can't be done from a shell script)

### 6. Backwards Compatibility Strategy

**Decision**: Existing consumer projects continue working without changes. The plugin's new skill names are discovered automatically when the plugin updates. Old skill names (`speckit-harness:speckit-*`) stop working but documentation points to new names.

**Rationale**: The plugin system loads skills from the installed plugin directory. When the directory names change, old names are simply not found. Adding deprecation guidance in CLAUDE.md and README handles the transition.

**Alternatives considered**:
- Symlinks from old to new directories (rejected — adds maintenance burden and delays adoption of new names)

### 7. Doctor Manifest Format

**Decision**: JSON manifest stored in `plugin/templates/kiln-manifest.json`. Defines expected directories, git tracking policy, and legacy path migrations.

**Rationale**: JSON is parseable by both shell scripts and JavaScript. The manifest is small and static — a template shipped with the plugin that the doctor skill reads to validate consumer projects.

**Alternatives considered**:
- YAML (rejected — adds a parsing dependency; JSON is natively supported in Node.js)
- Inline in the skill (rejected — separating the manifest makes it maintainable and versionable)
