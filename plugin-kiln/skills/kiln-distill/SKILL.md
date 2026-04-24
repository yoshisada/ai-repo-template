---
name: kiln-distill
description: Bundle open backlog items from `.kiln/issues/`, open strategic feedback from `.kiln/feedback/`, AND structured roadmap items from `.kiln/roadmap/items/` into a feature PRD. Groups items by theme (feedback + current-phase items lead the narrative; issues are the tactical layer). Supports `--phase <name>`, `--addresses <critique-id>`, `--kind <kind>` filters. Use as "/kiln:kiln-distill" (current phase + all open) or "/kiln:kiln-distill <category>" / `--phase <name>` to filter.
---

# Kiln Distill — Bundle Backlog + Feedback + Roadmap Items into a Feature PRD

Read open items from THREE input streams and generate a feature PRD that can be built with `/kiln:kiln-build-prd`:

1. `.kiln/feedback/*.md` (strategic — mission / scope / ergonomics / architecture) — FR-012 from `kiln-distill`.
2. `.kiln/roadmap/items/*.md` (structured planning layer — features / goals / research / constraints / non-goals / milestones / critiques) — FR-023 of `structured-roadmap`.
3. `.kiln/issues/*.md` (tactical — bugs / friction) — FR-012 from `kiln-distill`.

Feedback shapes the PRD narrative. Items from the current phase add concrete product-plan context (Background paragraph 2 cites recent items per contract §7.4). Issues form the tactical FR layer beneath the feedback + item framing (FR-024 of `structured-roadmap`).

### Backward compatibility

When `.kiln/roadmap/items/` is empty or no item matches the active filters, distill's existing feedback + issue behavior is UNCHANGED — same narrative, same frontmatter `derived_from:` ordering (feedback-first then issues), same status updates. The three-stream path only activates when at least one roadmap item is selected.

## User Input

```text
$ARGUMENTS
```

## Step 0: Parse Flags (FR-025 of structured-roadmap)

<!-- FR-025 / PRD FR-025: --phase / --addresses / --kind filters gate which roadmap items are ingested. -->

Before reading sources, parse `$ARGUMENTS` for the three new filter flags AND the legacy free-text category filter. Flags are OR-combinable (they all narrow the roadmap-items stream; feedback + issue filtering stays on the legacy free-text match).

```bash
# Defaults
DISTILL_PHASE="current"        # resolves to the one phase whose status: in-progress
DISTILL_ADDRESSES=""           # critique id (slug form) — bundle items whose addresses[] contains this
DISTILL_KIND=""                # one of: feature | goal | research | constraint | non-goal | milestone | critique
DISTILL_CATEGORY=""            # legacy free-text (matches issue.category / feedback.area)

# Parse (argv walk; accept --phase= and --phase <val>)
for token in $ARGUMENTS; do
  case "$token" in
    --phase=*)      DISTILL_PHASE="${token#--phase=}" ;;
    --phase)        NEXT=phase ;;
    --addresses=*)  DISTILL_ADDRESSES="${token#--addresses=}" ;;
    --addresses)    NEXT=addresses ;;
    --kind=*)       DISTILL_KIND="${token#--kind=}" ;;
    --kind)         NEXT=kind ;;
    *)
      case "${NEXT:-}" in
        phase)      DISTILL_PHASE="$token"; NEXT="" ;;
        addresses)  DISTILL_ADDRESSES="$token"; NEXT="" ;;
        kind)       DISTILL_KIND="$token"; NEXT="" ;;
        *)          DISTILL_CATEGORY="$token" ;;
      esac ;;
  esac
done
```

**`--phase current` resolution**: when `DISTILL_PHASE == "current"`, scan `.kiln/roadmap/phases/*.md` and pick the single phase with `status: in-progress`. If ZERO phases are in-progress, fall back to NO phase filter (include all non-shipped items). If MORE than one phase is in-progress, abort with a clear error naming the offending phases (violates FR-020 invariant).

## Step 1: Read All Three Sources (Feedback + Items + Backlog)

<!-- FR-023 / PRD FR-023: items are the third input stream. -->
<!-- FR-024 / PRD FR-024: narrative leads with feedback + current-phase items; issues are tactical. -->

Read open items from ALL THREE directories. Preserve the source-type tag (`feedback`, `item`, or `issue`) on every entry throughout the rest of the flow.

```
# Pseudocode — reference shape (contract §7.1 of structured-roadmap)
feedback_files = glob(".kiln/feedback/*.md") with frontmatter.status == "open"
item_files     = glob(".kiln/roadmap/items/*.md") filtered by:
                   - status != "shipped"                           (always)
                   - (DISTILL_PHASE != "" AND phase == DISTILL_PHASE)   when --phase given / resolved
                   - (DISTILL_KIND != "" AND kind == DISTILL_KIND)      when --kind given
                   - (DISTILL_ADDRESSES != "" AND addresses[] contains DISTILL_ADDRESSES)  when --addresses given
issue_files    = glob(".kiln/issues/*.md", top-level only) with frontmatter.status == "open"

feedback_items = [{...parsed frontmatter, type_tag: "feedback", path: f} for f in feedback_files]
roadmap_items  = [{...parsed frontmatter, type_tag: "item",     path: f} for f in item_files]
issue_items    = [{...parsed frontmatter, type_tag: "issue",    path: f} for f in issue_files]

all_items = feedback_items + roadmap_items + issue_items   # three-group order — contract §7.2

if empty(all_items):
    report "No open backlog, feedback, or roadmap items. Use /kiln:kiln-feedback, /kiln:kiln-roadmap, or /kiln:kiln-report-issue to log items first."
    stop
```

Notes:

- For feedback files, parse: `id`, `title`, `type: feedback`, `date`, `status`, `severity`, `area`, `repo`, optional `files`. `type_tag` is `feedback`.
- For roadmap items, parse per contracts/interfaces.md §1.3 of `structured-roadmap`: `id`, `title`, `kind`, `date`, `status`, `phase`, `state`, `blast_radius`, `review_cost`, `context_cost`, optional `depends_on`, `addresses`, `implementation_hints`, `prd`, `spec`, and (for critiques) `proof_path`. `type_tag` is `item`.
- For issue files, parse: `title`, `type`, `severity`, `category`, `status`, `date`, `github_issue`. `type_tag` is `issue`.
- **Status filter**: feedback + issues require `status: open`; items require `status != shipped`.
- **Free-text filter** (`DISTILL_CATEGORY`): further filter feedback on `area`, issues on `category`. Does NOT further filter items (use `--phase` / `--addresses` / `--kind` instead).
- **`--addresses` soft-match on feedback** (contract §11): if a feedback entry's `area:` substring-matches `DISTILL_ADDRESSES`, include it. Best-effort — not a hard gate.
- **Top-level only** for `.kiln/issues/` — do NOT recurse into `completed/`.

### Use the shared roadmap helper

Instead of hand-rolling the item glob, invoke `bash plugin-kiln/scripts/roadmap/list-items.sh` (contract §2.4 — owned by impl-roadmap) with the parsed filters:

```bash
ROADMAP_ITEMS=$(bash plugin-kiln/scripts/roadmap/list-items.sh \
  ${DISTILL_PHASE:+--phase "$DISTILL_PHASE"} \
  ${DISTILL_KIND:+--kind "$DISTILL_KIND"} \
  ${DISTILL_ADDRESSES:+--addresses "$DISTILL_ADDRESSES"})
# Then drop any path whose status is "shipped" (list-items.sh does NOT filter status by default).
```

If `list-items.sh` is missing (structured-roadmap not yet installed), fall back to an empty item list and continue with the legacy feedback + issue flow — distill MUST NOT hard-fail when the roadmap substrate is absent.

## Step 2: Group by Theme (Feedback + Items First)

<!-- FR-024 / PRD FR-024: three-section grouping — feedback themes → item-led themes → issue-only themes. -->
<!-- Contract §7.2 of structured-roadmap: within each group, sort by filename ASC — determinism hook for NFR-003. -->

Analyze the open items and group them into coherent themes. A theme is a set of related items sharing:
- The same root cause or concern
- The same affected area (`area:` feedback, `phase:` / `addresses:` items, `category:` issues)
- A logical dependency (e.g., an item `addresses:` a critique; a feedback theme motivates a feature item)

**Ordering rules (FR-012 + FR-024 of structured-roadmap)**:
1. Within a theme, list entries in this order: feedback → items → issues.
2. Themes are presented in THREE sections:
   a. **Feedback-shaped themes** — any theme containing at least one feedback entry (items may join).
   b. **Item-led themes** — themes anchored on a roadmap item with no feedback (but may pull issues).
   c. **Issue-only themes** — themes with only issues.
3. Within each section, sort by highest severity in the theme; ties break on filename ASC.
4. Within each group (feedback / items / issues) inside a theme, sort entries by filename ASC (byte-wise POSIX sort). This is the NFR-003 determinism hook.

Present the grouping to the user with the three-section shape:

```markdown
## Backlog Summary: N open entries (F feedback + M items + I issues)
**Filters**: phase=<DISTILL_PHASE|all>  kind=<DISTILL_KIND|all>  addresses=<DISTILL_ADDRESSES|all>

### Feedback-shaped themes

#### Theme 1: <theme name>
**Entries**: N | **Highest severity**: <severity>
- [feedback] [<title>](.kiln/feedback/<file>) — <area>, <severity>
- [item]     [<title>](.kiln/roadmap/items/<file>) — <kind>, phase:<phase>, state:<state>
- [issue]    [<title>](.kiln/issues/<file>) — <type>, <severity>

### Item-led themes

#### Theme 2: <theme name>
**Entries**: N | **Highest severity/kind**: <severity|kind>
- [item]  [<title>](.kiln/roadmap/items/<file>) — <kind>, phase:<phase>
- [issue] [<title>](.kiln/issues/<file>) — <type>, <severity>

### Issue-only themes

#### Theme 3: <theme name>
**Entries**: N | **Highest severity**: <severity>
- [issue] [<title>](.kiln/issues/<file>) — <type>, <severity>

### Ungrouped
- [feedback] [<title>](.kiln/feedback/<file>) — <area>, <severity>
- [item]     [<title>](.kiln/roadmap/items/<file>) — <kind>, phase:<phase>
- [issue]    [<title>](.kiln/issues/<file>) — <type>, <severity>
```

If there are no feedback items in the run, the "Feedback-shaped themes" section is omitted. If there are no roadmap items, the "Item-led themes" section is omitted and the grouping reverts to the two-section feedback + issue shape.

## Step 3: Select Scope

Ask the user which themes to include in the PRD:

- **All themes**: "Bundle everything into one PRD"
- **Specific themes**: "Just themes 1 and 3"
- **Single theme**: "Only theme 2"
- **Custom selection**: "These specific items: <list>"

If there's only one theme, skip this step and proceed.

## Step 4: Generate the Feature PRD

Using the selected items, generate a feature PRD following the same structure as `/kiln:kiln-create-prd` Mode B (feature addition).

### PRD Location

Create: `docs/features/<YYYY-MM-DD>-<theme-slug>/PRD.md`

### YAML Frontmatter Emission (FR-001, FR-002, FR-003 — spec `prd-derived-from-frontmatter`; extended by FR-024 / FR-026 of `structured-roadmap`)

The generated PRD MUST begin with a YAML frontmatter block. The block contains exactly three keys in this exact order:

1. `derived_from:` — YAML block sequence of repo-relative paths to the selected source entries across all three streams.
2. `distilled_date:` — UTC ISO-8601 date (`YYYY-MM-DD`) produced by `date -u +%Y-%m-%d`.
3. `theme:` — the slug portion of the PRD directory name (i.e. `<YYYY-MM-DD>-<slug>` → `<slug>`).

**Literal block skeleton** (contract §1.1 of `specs/prd-derived-from-frontmatter/contracts/interfaces.md`, extended per contract §7.2 of `structured-roadmap`):

```yaml
---
derived_from:
  - .kiln/feedback/<file>.md
  - .kiln/roadmap/items/<file>.md
  - .kiln/issues/<file>.md
distilled_date: <YYYY-MM-DD>
theme: <theme-slug>
---
```

Rules:

- Key order is NON-NEGOTIABLE. Reordering / inserting other keys / renaming is a contract violation. Future schema extensions go AFTER `theme:`.
- List items use two-space indentation + `- ` prefix + unquoted repo-relative path (forward slashes, no leading `./` or `/`).
- **Sort order — THREE-GROUP** (FR-024 of `structured-roadmap`, contract §7.2):
  1. Feedback entries (`.kiln/feedback/*`) — filename ASC.
  2. Roadmap item entries (`.kiln/roadmap/items/*`) — filename ASC.
  3. Issue entries (`.kiln/issues/*`) — filename ASC.
  This three-group sort IS the determinism hook (NFR-003): second distill run on unchanged inputs MUST emit byte-identical frontmatter.
- The frontmatter block precedes IMMEDIATELY (on the next line) the existing `# Feature PRD: <Theme Name>` heading.
- **Empty-list case** (hand-authored PRDs per spec Decision D3): `derived_from: []` on a single inline line is valid. Typical `/kiln:kiln-distill` runs always have at least one selected entry, so this is primarily a shape the readers must accept — distill itself emits block-sequence form when the list is non-empty.
- **Backward compat**: when NO roadmap items are selected, the middle group collapses and the list reverts to the two-group feedback-then-issues shape (byte-identical to pre-`structured-roadmap` distill output).

### FR-002 Single-Source-of-Truth Invariant (extended for three streams)

The frontmatter `derived_from:` list AND the `### Source Issues` body table MUST be rendered from the SAME in-memory list of selected entries. Pseudocode (contract §1.6 of `prd-derived-from-frontmatter`, extended per contract §7.2 of `structured-roadmap`):

```python
source_entries = feedback_sorted + item_sorted + issue_sorted   # three groups, filename ASC within each
write_frontmatter(source_entries)                                # produces derived_from: list
write_source_issues_table(source_entries)                        # same order, Type column records "feedback" / "item" / "issue"
assert [entry.path for entry in source_entries] == [row.path for row in parsed_table]
```

**Drift-abort check**: BEFORE the PRD file is finalized, verify that the ordered list of paths in `derived_from:` byte-for-byte equals the ordered list of paths extracted from the `### Source Issues` table's first-column markdown links. Mismatch → abort with a clear error; NO partial PRD is written to disk. This invariant prevents future refactors from silently introducing drift between the two renderings.

### Feedback-first + item-led narrative shape (FR-012 + FR-024 / FR-027 of `structured-roadmap`)

When the selected entries include ANY feedback OR any roadmap item, the PRD narrative MUST lead with feedback themes first, then item framing:

- **`## Background`**:
  - **Paragraph 1**: synthesize the strategic concerns raised by feedback (if any).
  - **Paragraph 2** (NEW — contract §7.4): cite the roadmap items concretely. Use the pattern:
    > "Recently the roadmap surfaced these items in the **<phase>** phase: <item-id> (<kind>), <item-id> (<kind>), …"
    Do NOT write "related items" — write the actual item-ids. If NO items were selected, omit this paragraph (backward compat).
  - **Paragraph 3+**: issues as the tactical layer that reinforces both feedback and items.
- **`## Problem Statement`**: feedback-first order. Open with the strategic problem from feedback, then name the item-level gaps, then the tactical pain points from issues.
- **`## Goals`**: bullets keyed off feedback themes wherever any exist, with item-derived goals immediately under them. Issue-only themes contribute additional goal bullets at the bottom.
- **`## Implementation Hints`** (NEW — FR-027 of `structured-roadmap`): a new top-level section ONLY emitted when at least one selected item has a non-empty `implementation_hints:` field. Each block is rendered verbatim with an item-id back-reference:

  ```markdown
  ## Implementation Hints

  <verbatim implementation_hints body from item>

  *(from: `<item-id>`)*
  ```

  Multiple items concat their blocks in the same three-group sort order used for `derived_from:`. NO re-elicitation — do NOT ask the user to restate hints already captured during `/kiln:kiln-roadmap` interview.
- **`## Requirements → ### Functional Requirements`**: within each theme, feedback-derived FRs appear first, then item-derived FRs, then issue-derived FRs. Each FR references its source file (`FR-001 (from: <file>.md)`).
- **`### Source Issues`** table: `Type` column takes values `feedback` | `item` | `issue`. Rows sort per the §7.2 three-group order (feedback → item → issue, filename ASC within each group).

If NO feedback and NO roadmap items are selected, fall back to the prior issue-only narrative shape (no forced feedback / item framing).

### PRD Content

The PRD must:

1. **Reference every source entry** it addresses — link to the source file (`.kiln/feedback/...`, `.kiln/roadmap/items/...`, or `.kiln/issues/...`) and GitHub issue number (if any, issues only)
2. **Synthesize, don't copy-paste** — combine related entries into coherent requirements, don't just list them
3. **Include these sections**:

```markdown
---
derived_from:
  - .kiln/feedback/<file>.md
  - .kiln/roadmap/items/<file>.md
  - .kiln/issues/<file>.md
distilled_date: YYYY-MM-DD
theme: <theme-slug>
---
# Feature PRD: <Theme Name>

**Date**: YYYY-MM-DD
**Status**: Draft
**Parent PRD**: [link to docs/PRD.md if exists]

## Background

<Paragraph 1 — feedback themes when any feedback present.>
<Paragraph 2 — "Recently the roadmap surfaced these items in the <phase> phase: ..." when any items selected. Contract §7.4.>
<Paragraph 3+ — tactical issues as supporting evidence.>

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [title](.kiln/feedback/file.md)           | .kiln/feedback/    | feedback | — | high / mission |
| 2 | [title](.kiln/feedback/file.md)           | .kiln/feedback/    | feedback | — | medium / ergonomics |
| 3 | [title](.kiln/roadmap/items/file.md)      | .kiln/roadmap/     | item     | — | <kind> / phase:<phase> |
| 4 | [title](.kiln/issues/file.md)             | .kiln/issues/      | issue    | #N or — | high / <category> |

(Three-group order — feedback rows first, item rows second, issue rows third — FR-012 + FR-024 of structured-roadmap.)

## Implementation Hints

<Only emitted when at least one selected item carries a non-empty `implementation_hints:` field. Render each hint block verbatim, followed by `*(from: <item-id>)*`. Omit entire section otherwise — FR-027 of structured-roadmap.>

*(from: `2026-04-24-example-item`)*

## Problem Statement

<1-2 paragraphs — feedback-first when any feedback is present. Strategic problem stated from feedback, tactical evidence from issues.>

## Goals

<Bulleted list — feedback-theme goals first, issue-theme goals beneath>

## Non-Goals

<What this PRD explicitly does NOT address>

## Requirements

### Functional Requirements

<FR-001 through FR-NNN. Within each theme, feedback-derived FRs come FIRST. Each FR traceable to source file.>

### Non-Functional Requirements

<Performance, reliability, backwards compatibility constraints>

## User Stories

<Derived from the source items — who needs what and why>

## Success Criteria

<Measurable outcomes — how do we know this worked>

## Tech Stack

<Inherited from parent PRD, plus any additions needed>

## Risks & Open Questions

<Unknowns, dependencies, things that could go wrong>
```

4. **Map requirements to source items**: every FR-NNN should reference which source it addresses (e.g., `FR-001 (from: .kiln/feedback/2026-04-22-scope-creep.md)` or `FR-005 (from: .kiln/issues/broken-button.md)`)
5. **Prioritize**: within a theme, order by feedback-first, then by severity (critical > high > medium > low; for issues: blocking > high > medium > low)

## Step 5: Update Source Status (Feedback, Items, and Issues)

After the PRD is written, update each included source entry. The protocol branches on `type_tag`:

### 5a — Feedback + Issues (unchanged from FR-013)

Both `.kiln/feedback/*.md` and `.kiln/issues/*.md` files get the same update:

- Change `status: open` → `status: prd-created`
- Append a new frontmatter key: `prd: docs/features/<date>-<slug>/PRD.md`

### 5b — Roadmap Items (FR-026 / PRD FR-026 + contract §7.5 of `structured-roadmap`)

For each selected item, run this atomic-ish sequence — state flip FIRST, then the `prd:` patch; roll back the state flip if the patch fails:

```bash
# FR-026 / PRD FR-026: promote item state and annotate the source PRD path.
PRD_PATH="docs/features/<date>-<slug>/PRD.md"

for ITEM_PATH in "${SELECTED_ITEMS[@]}"; do
  # Step 1 — flip state to "distilled"
  STATE_RESULT=$(bash plugin-kiln/scripts/roadmap/update-item-state.sh "$ITEM_PATH" distilled)
  if ! echo "$STATE_RESULT" | jq -e '.ok == true' >/dev/null; then
    echo "WARNING: failed to flip $ITEM_PATH state → distilled; skipping item" >&2
    continue
  fi

  # Step 2 — patch the prd: field
  if ! patch_item_frontmatter "$ITEM_PATH" "prd" "$PRD_PATH"; then
    # Rollback — restore state to in-phase so the item is re-considered next distill run.
    bash plugin-kiln/scripts/roadmap/update-item-state.sh "$ITEM_PATH" in-phase >/dev/null 2>&1 || true
    echo "ERROR: failed to patch prd: field for $ITEM_PATH; rolled back state to in-phase" >&2
    continue
  fi
done
```

`patch_item_frontmatter` is a small inline awk / sed helper that inserts-or-updates a single key in the YAML frontmatter (same shape as the feedback / issue path uses). Do NOT touch any other frontmatter key.

### Transition semantics (contract §7.5)

- `state: in-phase` → `state: distilled` is the expected transition for an item captured via `/kiln:kiln-roadmap` and then run through `/kiln:kiln-distill`.
- `state: planned` items (not yet in an active phase) ARE accepted by `update-item-state.sh distilled` but distill would NOT normally select them — they're filtered out upstream by the `--phase` logic.
- Atomic-ish: if the `prd:` patch fails, the state flip is reverted; the item is left in `in-phase` so the next distill run can re-pick it. Partial writes never leave an item with `state: distilled` but no `prd:` back-reference.
- Items with existing `prd:` values (re-distill) are overwritten with the NEW PRD path — this is the intended behavior when a user deliberately re-bundles an item into a replacement PRD.

Source type is ALWAYS preserved in the status update choice — feedback + issues flow through 5a, items flow through 5b.

## Step 6: Report

```markdown
## PRD Created

**Location**: docs/features/<date>-<slug>/PRD.md
**Addresses**: N entries (F feedback + M items + I issues)
**Requirements**: N functional requirements
**Filters applied**: phase=<DISTILL_PHASE|all>  kind=<DISTILL_KIND|all>  addresses=<DISTILL_ADDRESSES|all>

### Included feedback:
- [x] <title> — <severity> / <area>

### Included roadmap items:
- [x] <item-id> — <kind>, phase:<phase>, state: in-phase → **distilled**

### Included issues:
- [x] <title> — <severity>

### Remaining open: F feedback + M items + I issues

**Next step**: Review the PRD, then run `/kiln:kiln-build-prd <slug>` to execute the full pipeline.
```

## Rules

- Never delete feedback, item, or issue entries — only update their status / state
- If the user has no parent PRD (`docs/PRD.md` doesn't exist), the generated PRD is standalone — don't require a parent
- Don't invent requirements that aren't backed by a source entry — the PRD should address what was captured, nothing more
- If an issue entry references a GitHub issue, include the issue number in the PRD for traceability (feedback + items have no GitHub issue column)
- Keep the PRD focused — if themes are too different to fit in one coherent PRD, suggest splitting into multiple PRDs
- Feedback leads the narrative; roadmap items anchor Background paragraph 2 concretely; issues are tactical — do NOT bury a feedback theme beneath tactical issues in the PRD body (FR-012 + FR-024 of structured-roadmap)
- **Item state updates are atomic-ish**: state flip → prd: patch. Rollback the state flip if the patch fails (FR-026 / contract §7.5). Never leave an item with `state: distilled` but no `prd:`.
- **Implementation hints flow through, don't re-elicit** (FR-027): if an item carries `implementation_hints:`, render them in `## Implementation Hints` with an item-id back-reference. Do NOT ask the user to restate them.
- **Determinism** (NFR-003 + FR-037): the three-group sort (feedback → item → issue, filename ASC within each group) is the byte-identical output guarantee. Do NOT reorder entries for aesthetics.
- Don't auto-commit — let the user review first
