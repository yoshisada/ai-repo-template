# Project Language Analysis

## Detected Language

The automated language detection classified this repository as **unknown**. The project does not contain a top-level `package.json`, `Cargo.toml`, or `go.mod` file, so none of the specialized analyzers were triggered.

This is expected: the repository is a Claude Code plugin source repo consisting primarily of Markdown skill/agent definitions, Bash shell scripts (hooks), and JSON configuration files rather than a conventional application codebase.

## Key Stats

- **File count** (up to 3 levels deep): 273
- **Primary file types**: Markdown (`.md`), Shell (`.sh`), JSON (`.json`)
- **Analysis path taken**: fallback (no specialized analyzer matched)

## Summary

This repository does not fit neatly into a single-language category. It is a multi-plugin monorepo (`plugin-kiln/`, `plugin-shelf/`, `plugin-wheel/`) where the "source code" is largely declarative Markdown and configuration. Each plugin subdirectory contains its own `package.json` for npm distribution, but the root does not, which is why the top-level detection returned unknown.
