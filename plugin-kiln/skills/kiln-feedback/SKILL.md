---
name: kiln-feedback
description: Log strategic product feedback about the core mission, scope, or direction to `.kiln/feedback/`. Distinct from `/kiln:kiln-report-issue` which captures bugs and friction. Use as `/kiln:kiln-feedback <description>`.
---

# Kiln Feedback — Log Strategic Product Feedback

Capture higher-altitude product feedback (mission, scope, ergonomics, architecture, direction) to `.kiln/feedback/`. This is the counterpart to `/kiln:kiln-report-issue`: issues are tactical bugs/friction; feedback is strategic. Both are consumed by `/kiln:kiln-distill` to shape the next PRD — feedback leads the narrative; issues form the tactical layer.

Unlike `/kiln:kiln-report-issue`, this skill does NOT run a wheel workflow, does NOT write to Obsidian, and does NOT kick off a background sync. It writes one local file and exits.

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate Input

If `$ARGUMENTS` is empty, ask the user: "What's the feedback? Describe the strategic concern about mission, scope, ergonomics, architecture, or direction." Wait for a non-empty response before continuing.

Otherwise, use the provided text as the feedback body.

## Step 2: Derive Slug

Derive `slug` from the first ~6 words of the feedback description:

```bash
# Slug: lowercase, non-alphanumerics → '-', collapse runs of '-', trim trailing '-'
slug=$(printf '%s' "$FIRST_SIX_WORDS" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-60)
```

Use the first ~6 words only. If the resulting slug is empty (edge case: all non-alphanumeric input), fall back to `feedback`.

Compose `today` as UTC date:

```bash
today=$(date -u +%Y-%m-%d)
```

The target file path is `.kiln/feedback/${today}-${slug}.md`. If that exact path already exists, append a short disambiguator (`-2`, `-3`, …) to the slug until it's unique — matching `/kiln:kiln-report-issue` behavior.

## Step 3: Auto-detect Repo URL

```bash
# Detect repo URL — graceful failure if gh unavailable, not authenticated, or no remote
REPO_URL=$(gh repo view --json url -q '.url' 2>/dev/null || echo "")
```

If `REPO_URL` is non-empty, the frontmatter gets `repo: <URL>`.
If empty (gh not installed, not authenticated, or no remote), the frontmatter gets the literal `repo: null`. The `repo:` key is always present — this is Contract 1.

## Step 3b: Extract File Paths from Description

Scan `$ARGUMENTS` for file paths — strings containing `/` with common code extensions (`.ts`, `.tsx`, `.js`, `.jsx`, `.md`, `.json`, `.sh`, `.mjs`, `.py`, `.go`, `.rs`) or paths that start with `src/`, `plugin-`, `specs/`, `.kiln/`, `docs/`, etc. Match the regex behavior used by `/kiln:kiln-report-issue`.

If any paths are found, include them as:

```yaml
files:
  - path/to/file1.ts
  - path/to/file2.md
```

If no file paths are found in the description, omit the `files` field entirely.

## Step 4: Classify Severity and Area

Inspect `$ARGUMENTS` and classify:

- `severity`: exactly one of `low | medium | high | critical`. Signals: "blocking", "critical", "cannot ship" → `critical`; "hurts every run", "major gap", "principled concern" → `high`; neutral strategic concern → `medium`; "nice to have", "musing", "idle thought" → `low`.
- `area`: exactly one of `mission | scope | ergonomics | architecture | other`. Signals:
  - `mission` — the product's fundamental purpose, north star, who it's for
  - `scope` — what's in / out of the product; what we're building vs. not building
  - `ergonomics` — developer/user experience, friction, workflow feel (strategic, not tactical bug)
  - `architecture` — structural decisions, boundaries, plugin shape, tech posture
  - `other` — doesn't fit the four above

**If either classification is ambiguous, ASK the user — do not guess.** This is a hard rule (Contract 1 validation). Only proceed after both values are confirmed.

## Step 5: Write the File

Write the file to `.kiln/feedback/${today}-${slug}.md` with frontmatter matching Contract 1 exactly:

```yaml
---
id: ${today}-${slug}
title: <one-line title derived from $ARGUMENTS — non-empty>
type: feedback
date: ${today}
status: open
severity: <low|medium|high|critical>
area: <mission|scope|ergonomics|architecture|other>
repo: <URL or null>
files:
  - <path>      # omit entire `files:` block if none detected
---

<$ARGUMENTS verbatim as the body>
```

Required keys (MUST all be present, non-empty except `repo` which may be literal `null`): `id`, `title`, `type`, `date`, `status`, `severity`, `area`, `repo`. Optional keys (omit when absent): `prd`, `files`.

`type:` is always the literal string `feedback` — it is not user-picked.

The `.kiln/feedback/` directory is committed (same policy as `.kiln/issues/`). Create the directory if it does not yet exist:

```bash
mkdir -p .kiln/feedback
```

## Step 6: Confirm

Print a single confirmation line:

```
Feedback logged: .kiln/feedback/<file>.md
```

Do NOT write to Obsidian. Do NOT run a wheel workflow. Do NOT spawn a background sync. The file on disk is the source of truth.

## Rules

- No MCP writes, no wheel workflow, no Obsidian sync — just write the local file and exit.
- Classification is a hard gate: if `severity` or `area` is ambiguous from the description, ASK before writing.
- `type:` is always the literal `feedback` — never let the user override.
- The `.kiln/feedback/` directory is committed (not gitignored), matching `.kiln/issues/` policy.
- `/kiln:kiln-distill` picks up open feedback files on its next run and leads PRD narratives with them (FR-012).
- If the user reports multiple pieces of feedback at once, run the skill once per item — one file per piece.
- If `$ARGUMENTS` is empty, ask before writing — don't write an empty file.
