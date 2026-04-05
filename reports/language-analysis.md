# Language Analysis

## Detection Result

Language detected: **unknown** — no root-level `package.json`, `Cargo.toml`, or `go.mod` was found. This is expected for a plugin monorepo where package manifests live in subdirectories (`plugin-kiln/`, `plugin-shelf/`, `plugin-wheel/`) rather than the repo root.

## Fallback Analysis

The fallback analyzer found **245 files** across the repository (within 3 levels of depth). The primary languages are actually Markdown (skills, agents, specs, docs), Bash (hooks, engine libs), and JavaScript (init scripts), but the root-level detection missed them since there's no top-level manifest.

## Observation

The `detect-language` step should be enhanced to check `plugin-*/package.json` or scan for file extensions when no root manifest exists.
