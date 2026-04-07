# Language Analysis Report

## Detection Result

- **Detected Language**: unknown
- **Method**: Checked for `package.json` (JavaScript), `Cargo.toml` (Rust), and `go.mod` (Go). None found at repo root.

## Analysis

This repository does not match any of the standard language indicators. It is primarily a Markdown and Bash-based project (a Claude Code plugin repository) rather than a traditional application codebase.

### Key Stats

- **Total files** (depth 3): 293
- **Primary content**: Markdown skill definitions, Bash shell scripts, JSON configuration
- **No build system detected**: No package.json, Cargo.toml, or go.mod at the repo root

## Branch Path Taken

The branch step `check-js` evaluated to non-zero (no JavaScript detected), so the workflow followed the `fallback-analysis` path and skipped `analyze-js`.
