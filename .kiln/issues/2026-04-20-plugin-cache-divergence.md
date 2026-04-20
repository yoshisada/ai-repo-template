# Plugin cache diverges from source — new workflows not discoverable in consumer repos

**Source**: Live-test of /kiln:build-prd manifest-improvement-subroutine
**Priority**: high
**Suggested command**: `/fix` — formalize a "publish + reload-plugins" step in the pipeline retrospective phase, or add a dev-mode symlink from the cache to plugin-*/  source dirs
**Tags**: [auto:continuance]

## Description

After merging PR #114 and invoking `shelf:propose-manifest-improvement`, `validate-workflow.sh` returned "Plugin workflow not found" — the plugin cache at `~/.claude/plugins/cache/yoshisada-speckit/shelf/000.000.000.1143/` didn't have files from source v1162. Manually copying the workflow + scripts into v1143's directory worked, but this is fragile: any new plugin file (skill, workflow, script) authored in a build-prd session is invisible to the running Claude until the plugin is republished AND the cache is refreshed. Today that requires `npm publish` + user action. Two fix directions: (a) `plugin-*/bin/init.mjs` exposes a `dev-link` subcommand that symlinks the cache version dir to the source dir, or (b) the pipeline retrospective step reminds the user to publish and reload.
