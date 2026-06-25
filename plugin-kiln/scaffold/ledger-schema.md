# Kiln Ledger — Schema Reference

> **Reference document.** This file is kept in `plugin-kiln/scaffold/` for
> discoverability but is **not** copied into consumer projects by `init.mjs`.
> Consumer projects store the ledger under `.kiln/ledger/` (created on first
> write or by `kiln init`).

---

## Directory Layout

```
.kiln/
└── ledger/
    ├── <YYYY-MM-DD-slug>.json     # one file per ledger entry
    └── proposals/
        └── <YYYY-MM-DD-slug>.json # one file per improvement proposal
```

Both directories are created empty by `kiln init`. They are **not** tracked by
git by default (add to `.gitignore` if entries contain sensitive detail;
otherwise tracking is fine for team sharing).

---

## Ledger Entry Schema — `.kiln/ledger/<id>.json`

```json
{
  "id":           "YYYY-MM-DD-<slug>",
  "kind":         "mistake | fix | retro | friction",
  "summary":      "one-line description (required)",
  "detail":       "full prose — what happened, why, what was learned",
  "blast_radius": "local | cross-plugin | cross-project",
  "tags":         ["mistake/assumption", "topic/hooks", "language/typescript"],
  "source_path":  ".kiln/mistakes/YYYY-MM-DD-<slug>.md",
  "ts":           "ISO-8601 timestamp"
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Stable unique identifier. Format: `YYYY-MM-DD-<kebab-slug>`. Must be unique across all entries. |
| `kind` | enum | yes | Entry classification. `mistake` = AI/human error; `fix` = corrective action taken; `retro` = retrospective insight; `friction` = repeated pain point without a single root cause. |
| `summary` | string | yes | One-line description. Used in table views. Keep ≤ 100 chars. |
| `detail` | string | no | Full prose: what happened, root cause, what changed. Plain text or markdown. |
| `blast_radius` | enum | no | Impact scope. `local` = affects one file/step; `cross-plugin` = affects kiln plugin boundary; `cross-project` = pattern applies across consumer projects. |
| `tags` | string[] | no | Free-form hierarchical tags. Conventions: `mistake/<type>` (e.g. `mistake/assumption`, `mistake/hallucination`), `topic/<area>` (e.g. `topic/hooks`, `topic/wheel`), `language/<lang>` (e.g. `language/typescript`). |
| `source_path` | string | no | Path to the originating artifact (mistake markdown, retro file, etc.) relative to the project root. |
| `ts` | string | yes | ISO-8601 creation timestamp (e.g. `2026-06-24T14:30:00Z`). Used for sort order by `/kiln:kiln-ledger`. |

### `kind` Value Guide

- **`mistake`** — a concrete error: wrong assumption, hallucinated API, broken workflow step. Created by `kiln-mistake-record` from `mistake-data.json`.
- **`fix`** — a correction applied after a mistake. May reference the originating mistake via a `ledger_refs` field (future extension).
- **`retro`** — an insight surfaced during a retrospective. May be positive ("this worked well") or negative.
- **`friction`** — recurring pain that isn't a single mistake: slow feedback loops, confusing skill names, excessive permission prompts.

### Tag Conventions

Tags follow a `namespace/value` format. Recognised namespaces:

| Namespace | Purpose | Examples |
|-----------|---------|---------|
| `mistake/` | Error classification | `mistake/assumption`, `mistake/hallucination`, `mistake/scope-creep` |
| `topic/` | Technical area | `topic/hooks`, `topic/wheel`, `topic/obsidian`, `topic/shelf` |
| `language/` | Programming language | `language/typescript`, `language/bash`, `language/python` |
| `phase/` | Pipeline phase where it occurred | `phase/specify`, `phase/implement`, `phase/audit` |
| `severity/` | Impact severity | `severity/low`, `severity/medium`, `severity/high` |

Free-form tags without a namespace are allowed but less queryable.

---

## Proposal Schema — `.kiln/ledger/proposals/<id>.json`

```json
{
  "id":           "YYYY-MM-DD-<slug>",
  "target":       "plugin-kiln/skills/plan/SKILL.md",
  "patch":        "unified diff or prose instruction string",
  "risk":         "low | high",
  "blast_radius": "local | cross-plugin",
  "rationale":    "why this change — connects to the failure pattern",
  "ledger_refs":  ["YYYY-MM-DD-<slug>"]
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Stable unique identifier. Same format as ledger entries. |
| `target` | string | yes | Repo-relative path to the file this proposal would modify. |
| `patch` | string | yes | Either a unified diff or a prose instruction ("Add a note at the top of the Skills section explaining X"). Tools consuming this field decide which format to apply. |
| `risk` | enum | yes | `low` = config/template/doc target; `high` = hook/skill/agent/workflow target. Used by `kiln-self-improve` to decide L1 (auto-apply) vs L2 (surface for human review). |
| `blast_radius` | enum | no | `local` = affects only the named file; `cross-plugin` = the change ripples into other plugins or consumer behavior. |
| `rationale` | string | yes | Human-readable explanation of why this change addresses the failure pattern. |
| `ledger_refs` | string[] | no | IDs of ledger entries that motivated this proposal. Used to trace proposals back to concrete failures. |

### Risk Classification

| Target file pattern | Risk |
|---------------------|------|
| `plugin-kiln/scaffold/*.json`, `plugin-kiln/scaffold/*.md` | `low` |
| `plugin-kiln/templates/*.md`, `plugin-kiln/templates/*.json` | `low` |
| `*.kiln/standards.md`, `*.kiln/config.json` | `low` |
| `plugin-kiln/skills/*/SKILL.md` | `high` |
| `plugin-kiln/agents/*.md` | `high` |
| `plugin-kiln/hooks/*.sh` | `high` |
| `plugin-kiln/workflows/*.json` | `high` |
| `plugin-kiln/bin/*.mjs` | `high` |

---

## Run Manifest Schema — `.kiln/runs/<run_id>/manifest.json`

Created by `kiln-build-prd` at the start of each pipeline run. Used by
`kiln-resume` to continue from the last completed step.

```json
{
  "run_id":     "uuid",
  "prd":        "docs/features/<slug>/PRD.md",
  "phase":      "specify | plan | tasks | implement | audit | pr | done",
  "branch":     "build/<slug>-YYYYMMDD",
  "pr":         null,
  "decisions":  [],
  "escalations": [],
  "cursor":     "last-completed-step-id"
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `run_id` | string (uuid) | Unique run identifier. Stable across resume. |
| `prd` | string | Repo-relative path to the driving PRD. |
| `phase` | enum | Current pipeline phase. Updated at phase boundaries. |
| `branch` | string | Git branch this run writes to. |
| `pr` | string \| null | GitHub PR URL, populated after the PR step. |
| `decisions` | object[] | Log of autonomy decisions made during the run (what was auto-applied vs. escalated). Future schema; currently `[]`. |
| `escalations` | object[] | Log of items routed to human review. Future schema; currently `[]`. |
| `cursor` | string | ID of the last successfully completed wheel step. `kiln-resume` reads this to skip already-done steps. |

---

## Notes for Implementers

1. **IDs are immutable.** Once written, an entry's `id` never changes. If you
   need to update an entry, write a new `fix` entry with a `ledger_refs` back to
   the original.

2. **No partial writes.** Write the full JSON atomically (write to a `.tmp` file,
   then `mv`). A partial entry is worse than no entry.

3. **`/kiln:kiln-ledger` is the read surface.** Do not build ad-hoc readers;
   route all human queries through the skill.

4. **Proposals are human-reviewed before apply.** The `kiln-self-improve` workflow
   auto-applies only `risk: "low"` proposals. `risk: "high"` proposals are surfaced
   as text for human review (L2 escalation path).
