# version-increment hook fans out across all plugins in monorepo

**Source**: GitHub #115 (manifest-improvement retrospective), implementer friction note
**Priority**: medium
**Suggested command**: `/fix scope version-increment.sh to only the plugin(s) actually touched by the current edit`
**Tags**: [auto:continuance]

## Description

On every code edit, `hooks/version-increment.sh` auto-stages `VERSION`, `plugin-*/package.json`, and `plugin-*/.claude-plugin/plugin.json` across ALL six plugins in this monorepo — regardless of which plugin the edit touches. Every phase commit includes 10+ unrelated version bumps, degrading commit signal and making diffs noisy. The hook should detect which plugin the edit lives under and increment only that plugin's manifests (plus root VERSION).
