# Smoke Tests: Kiln Capture-and-Fix Loop Polish

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Tasks**: [tasks.md](./tasks.md)

One smoke command per success criterion from spec.md §Success Criteria. Run from repo root. Each test is either a shell one-liner (fast) or a skill invocation (manual, requires vault connectivity). None of them are wired into CI — the auditor and the retrospective run them by hand before closing the feature.

## SC-001 — `/kiln:kiln-fix` has zero team-spawn tool references

**Command:**

```bash
grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md
```

**Expected output:** no lines printed; command exits with status 1.

**What it proves:** Phase A's inline refactor removed every `TeamCreate` / `TaskCreate` / `TaskUpdate` / `TeamDelete` token from the skill. The only Obsidian writes left are the two direct `mcp__claude_ai_obsidian-*__create_file` calls in Steps 7.6 and 7.7.

## SC-002 — Reflect gate is deterministic (three-condition predicate)

**Command:**

```bash
grep -n 'reflect_fires' plugin-kiln/skills/kiln-fix/SKILL.md
```

**Expected output:** at least two hits — the `reflect_fires()` function definition under Step 7.7 and the call site below it. The function body contains all three `jq -e` predicates from `contracts/interfaces.md` Contract 2 (files_changed regex, issue/root_cause substring, fix_summary template path).

**What it proves:** the reflect gate is a deterministic bash predicate, not inline model judgement. Reproducible, flake-free, ~2k-token budget per NFR-003.

## SC-003 — `/kiln:kiln-fix` renders "What's Next?" on every terminal path

**Command (automated check):**

```bash
grep -c "## What's Next" plugin-kiln/skills/kiln-fix/SKILL.md
```

**Expected output:** a count of at least 4 (Step 5 example block, Step 6 escalation example, Step 7.8 reference, Step 8 heading, plus any Step 8 internal references).

**Command (manual check):** run `/kiln:kiln-fix` on a trivial bug. The final report MUST end with a `## What's Next?` block. Run it again on a deliberately unfixable bug to force the escalation path (Step 6) — that report MUST also end with a `## What's Next?` block. If Obsidian MCP is disconnected during a third run, the skipped-path report MUST still end with `## What's Next?`.

**What it proves:** FR-007 / FR-008 coverage across success, escalation, and Obsidian-skipped terminal paths.

## SC-004 — `/kiln:kiln-feedback` writes a schema-conformant frontmatter

**Command:**

```bash
/kiln:kiln-feedback "smoke test feedback — mission"
ls .kiln/feedback/
head -20 .kiln/feedback/$(date -u +%Y-%m-%d)-smoke-test-feedback-mission.md
```

**Expected output:** the file exists with all seven required keys present and non-empty: `id`, `title`, `type: feedback`, `date`, `status: open`, `severity`, `area`, `repo` (either a URL or `null`). `severity` is one of `low|medium|high|critical`; `area` is one of `mission|scope|ergonomics|architecture|other`.

**Validation rule:** per `contracts/interfaces.md` Contract 1, `severity` and `area` enum values outside the allowed set are an error. If the skill prompted for ambiguous values rather than guessing, that's also SC-004 pass.

**What it proves:** Phase C created a schema-conformant `/kiln:kiln-feedback` skill.

## SC-005 — `/kiln:kiln-distill` reads both feedback and issues, feedback-first

**Seed setup:**

```bash
cat > .kiln/feedback/2026-04-22-smoke-feedback.md <<'EOF'
---
id: 2026-04-22-smoke-feedback
title: Smoke feedback for SC-005
type: feedback
date: 2026-04-22
status: open
severity: medium
area: scope
repo: null
---

Smoke feedback body.
EOF

cat > .kiln/issues/2026-04-22-smoke-issue.md <<'EOF'
---
id: 2026-04-22-smoke-issue
title: Smoke issue for SC-005
type: issue
date: 2026-04-22
status: open
category: smoke
priority: medium
repo: null
---

Smoke issue body.
EOF
```

**Command:** `/kiln:kiln-distill`.

**Expected output:** the generated PRD at `docs/features/<date>-<slug>/PRD.md` has a `## Background` section that mentions the feedback item before the issue item. The `### Source Issues` table has a `Type` column, and the feedback row appears above the issue row. Both seed files have their frontmatter flipped from `status: open` to `status: prd-created` with a new `prd:` key.

**What it proves:** Phase D's dual-source read (FR-011) and feedback-first narrative shape (FR-012) are live.

## SC-006 — Zero live references to the old `kiln-issue-to-prd` name

**Command:**

```bash
grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/architecture.md
```

**Expected output:** either no lines, or only lines inside plainly-historical contexts (PRD / spec / retrospective / `.kiln/issues/` text blobs that describe the feature itself). Zero hits in live skill/agent code or `docs/architecture.md` prose.

**Manual check:** if any hit appears in `plugin-kiln/skills/<other>/SKILL.md`, `plugin-kiln/agents/*.md`, `plugin-shelf/`, or `docs/architecture.md` narrative prose, SC-006 fails and Phase E sweep missed it.

**What it proves:** Phase E cross-reference sweep (FR-014) touched every live pointer to the renamed skill.

---

## How to run the full smoke suite

```bash
# Automated checks (fast, no MCP required)
grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md  # SC-001
grep -n 'reflect_fires' plugin-kiln/skills/kiln-fix/SKILL.md                                  # SC-002
grep -c "## What's Next" plugin-kiln/skills/kiln-fix/SKILL.md                                 # SC-003 automated part
grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/architecture.md                         # SC-006
```

Manual checks (SC-003 manual, SC-004, SC-005) require a live `/kiln:kiln-fix`, `/kiln:kiln-feedback`, and `/kiln:kiln-distill` run and are covered by the auditor's final pass before the PR lands.
