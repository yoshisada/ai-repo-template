---
id: 2026-04-24-claude-audit-sibling-preview-file-undocumented
title: "claude-audit has no convention for 'show me the proposed final file' — sibling preview pattern emerged ad-hoc but isn't codified"
type: improvement
date: 2026-04-24
status: open
severity: low
area: kiln
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-claude-audit/SKILL.md
---

## Summary

The skill writes proposals as unified diffs in `.kiln/logs/claude-md-audit-<TIMESTAMP>.md`. Diffs are good for git-apply review but bad for "show me what the final file would actually look like." When the user asked exactly that ("show me what the full file would look like first"), the audit had to invent a sibling-preview pattern on the fly:

- `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-CLAUDE.md` — the proposed final source CLAUDE.md
- `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-scaffold-CLAUDE.md` — the proposed final scaffold

This worked. The pattern is useful — side-by-side review in VSCode is cleaner than reading a 200-line unified diff. But:

- The skill's permitted-files list says: "The *only* files this skill is permitted to modify are: `.kiln/logs/claude-md-audit-<TIMESTAMP>.md` (the preview), `plugin-kiln/rubrics/claude-md-best-practices.md` (cache), `.kiln/logs/` (the directory itself)." Sibling preview files are arguably a deviation from this list (still under `.kiln/logs/`, so the spirit holds, but the letter doesn't explicitly allow them).
- There's no naming convention — I picked `-proposed-CLAUDE.md` and `-proposed-scaffold-CLAUDE.md` ad-hoc.
- The audit log itself doesn't mention the sibling preview files exist, so a maintainer reading just the audit log won't know to look for them.
- After the apply lands, the sibling preview files are stale artifacts. There's no convention for cleanup.

## Proposed direction

Codify the sibling-preview pattern in `kiln-claude-audit/SKILL.md`:

### 1. Add it to the permitted-files list

```
The *only* files this skill is permitted to modify are:
- `.kiln/logs/claude-md-audit-<TIMESTAMP>.md` (the audit log)
- `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` (one sibling preview per audited file, when proposed diffs are non-empty)
- `plugin-kiln/rubrics/claude-md-best-practices.md` (cache body + fetched: date)
- `.kiln/logs/` (directory itself, if absent)
```

### 2. Add a Step 4.5 — render sibling previews

After Step 4 (write the audit log), the skill renders one sibling preview file per audited path that has at least one proposed diff. The naming convention is `<audit-log-basename>-proposed-<basename-with-slashes-replaced>.md`. So `CLAUDE.md` → `-proposed-CLAUDE.md`; `plugin-kiln/scaffold/CLAUDE.md` → `-proposed-plugin-kiln-scaffold-CLAUDE.md`.

### 3. Cross-reference in the audit log

The audit log's `## Proposed Diff` section header gets a one-line note: "Side-by-side preview: see `<audit-log-basename>-proposed-<basename>.md` for the proposed final state of this file."

### 4. Cleanup convention

After the maintainer applies the diffs, the sibling preview files are redundant. Two options:

- The next `/kiln:kiln-doctor` run flags `claude-md-audit-*-proposed-*.md` files as cleanup-candidates (only if their corresponding audit log says `applied: true` somewhere — which today it doesn't).
- The skill writes a footer note in the audit log: "Once the proposed diffs land, this audit log + sibling preview files can be archived to `.kiln/logs/archive/` or deleted."

(Option 2 is simpler — defer the doctor integration.)

## Why low-severity

The pattern works without codification — it just emerged in this session. Codifying it removes the ad-hoc-ness and gives every future audit run the same pattern. Not blocking, but worth tightening.

## Pipeline guidance

Low. SKILL.md edit + permitted-files list update + a footer-note convention. Likely a single small fix. `/kiln:kiln-fix` candidate or roll into the same PRD as the higher-severity audit-improvement issues.
