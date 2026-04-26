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

## Step 0.5: Un-promoted Source Gate (FR-004, FR-005 of workflow-governance)

<!-- FR-004 / workflow-governance FR-004: /kiln:kiln-distill MUST refuse to
     bundle raw issues/feedback that have not been promoted to roadmap items.
     FR-005 / workflow-governance FR-005: confirm-never-silent per-entry
     accept/skip prompt with a viable escape hatch to /kiln:kiln-roadmap
     --promote. -->

Before the three-stream read in Step 1, enumerate the candidate issue + feedback sources that would otherwise land in this run, classify them via `detect-un-promoted.sh`, and — if any are un-promoted — offer the user a per-entry promotion hand-off. This gate is the load-bearing governance claim of the workflow-governance PRD: the roadmap is the canonical intake, and raw issues/feedback are promotion sources, not direct PRD inputs.

### §0.5.1 — Enumerate candidate sources

Compute the candidate set from the same glob rules Step 1 will use (top-level only for `.kiln/issues/`; open-status for both):

```bash
CANDIDATE_SOURCES=()
while IFS= read -r f; do
  # Only include status: open entries — Step 1 will re-filter anyway.
  st=$(awk '/^---/{fm++;next} fm==1 && /^status:/ { sub(/^status:[ \t]*/,""); print; exit }' "$f" 2>/dev/null)
  if [[ "$st" == "open" ]]; then CANDIDATE_SOURCES+=("$f"); fi
done < <(find .kiln/issues -maxdepth 1 -type f -name '*.md' 2>/dev/null; \
         find .kiln/feedback -maxdepth 1 -type f -name '*.md' 2>/dev/null)
```

If `CANDIDATE_SOURCES` is empty, skip to Step 1 — the gate is a no-op when there are no raw sources in scope.

### §0.5.2 — Classify and filter

```bash
CLASSIFICATION=$(bash plugin-kiln/scripts/distill/detect-un-promoted.sh "${CANDIDATE_SOURCES[@]}")
UN_PROMOTED=$(printf '%s\n' "$CLASSIFICATION" | jq -r 'select(.status == "un-promoted") | .path')
```

If `UN_PROMOTED` is empty, every candidate is already promoted; skip to Step 1.

### §0.5.3 — Per-entry promote hand-off (FR-005, confirm-never-silent)

Otherwise, enumerate the hand-off envelopes and surface them to the user:

```bash
HANDOFF=$(bash plugin-kiln/scripts/distill/invoke-promote-handoff.sh $UN_PROMOTED)
# $HANDOFF is NDJSON — one {"path","title","prompt"} envelope per un-promoted source.
```

For each envelope, surface the `prompt` string to the user via the Skill tool (confirm-never-silent — do NOT read stdin shell-style). The prompt is per-entry, not a global confirm:

> Issues/feedback not yet promoted to roadmap items. Promote these before distilling?
>
> 1. [accept|skip] `.kiln/issues/2026-04-24-foo.md` — Foo needs dark mode
> 2. [accept|skip] `.kiln/feedback/2026-04-24-bar.md` — Bar feels slow
>
> Reply with one decision per entry (e.g. `accept, skip`) or `skip all`.

- **`accept <entry>`** → invoke `/kiln:kiln-roadmap --promote <path>` via the Skill tool. The skill runs the coached interview (Clarification 5 — pre-fill when body ≥ 200 chars) and writes a new roadmap item. On success, add the new `roadmap_item` path to the bundle for Step 1 re-read.
- **`skip <entry>`** → exclude this path from the run; do NOT emit a PRD for it.
- **`skip all`** → exclude every un-promoted entry from the run.

### §0.5.4 — Re-read after promotions

After the per-entry decision loop, re-run §0.5.2's classification to confirm no accepted entry landed back in the `un-promoted` bucket. If the resulting candidate bundle (accepted entries' newly-created roadmap items + pre-existing promoted items + any roadmap items Step 1 will pick up) is EMPTY, exit cleanly with:

> No promoted sources in this theme. Nothing to distill.

NO PRD is emitted. No side-effect writes. Exit 0 — the gate is non-punitive; the user declined every offer, which is a valid choice.

### §0.5.5 — What the gate does NOT do

- It does NOT touch existing roadmap items. `.kiln/roadmap/items/*.md` bypass this gate entirely (they're already promoted by construction).
- It does NOT validate pre-existing PRDs. FR-008 grandfathering is by construction — the gate only looks at INPUT candidates, not at committed PRDs under `docs/features/`. Any PRD with `distilled_date:` before `2026-04-24` (the gate-rollout date) is unaffected by this section. See "FR-008 grandfathering" note under Step 4 frontmatter emission.

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

## Step 3: Select Scope (Multi-Theme Picker — FR-017 of `coach-driven-capture-ergonomics`)

<!-- FR-017: present a multi-select picker after theme-grouping. User picks N≥1 themes; one PRD is emitted per selection. Backward-compat: single-theme path stays byte-identical (FR-021 / NFR-005). -->

Ask the user which themes to include. Unlike the legacy single-PRD path, **you MAY bundle multiple themes into multiple PRDs in one run** — one PRD per selected theme.

Present the picker as:

```markdown
Pick one or more themes to distill into PRDs. Each selection emits one PRD.

  [1] <theme-1 name> — N entries (highest severity: <sev>)
  [2] <theme-2 name> — N entries
  [3] <theme-3 name> — N entries
  ...

Reply with:
  - A single theme name or number (single-PRD, legacy behavior)
  - A comma-separated list of numbers, e.g. "1,3" (multi-PRD)
  - "all" to bundle every theme as its own PRD
  - "cancel" to abort without writing anything
```

**Shortcut**: if there is exactly ONE theme, skip the prompt and proceed with that theme (FR-021 byte-identical single-theme behavior).

### Resolving the selection machine-readably

Once the user answers, build a `grouped-themes.json` file in-memory or `/tmp/` representing all themes (one object per theme, field `slug` required, other fields optional), then invoke the selection normalizer:

```bash
# Write the grouped-themes JSON — SKILL body builds this from Step 2 output.
cat > /tmp/distill-themes-$$.json <<'JSON'
[
  {"slug":"<theme-1-slug>","entries":[...],"severity_hint":"highest"},
  {"slug":"<theme-2-slug>","entries":[...],"severity_hint":"med"},
  {"slug":"<theme-3-slug>","entries":[...],"severity_hint":"low"}
]
JSON

# Channel 1 — user picked by index ("1,3").
DISTILL_SELECTION_INDICES="1,3" \
  SELECTION_JSON=$(bash plugin-kiln/scripts/distill/select-themes.sh /tmp/distill-themes-$$.json)

# Channel 2 — user picked by slug ("ergo, cleanup").
# DISTILL_SELECTION_SLUGS="ergo,cleanup" bash plugin-kiln/scripts/distill/select-themes.sh ...

# Channel 3 — user said "cancel".
# DISTILL_SELECTION_CANCEL=1 bash plugin-kiln/scripts/distill/select-themes.sh ... (exit 1, stdout empty)

# Fallback — no env var set → select ALL themes. This keeps the single-theme
# case (N=1) byte-identical to pre-change behavior (FR-021 / NFR-005).

if [ -z "$SELECTION_JSON" ]; then
  echo "Selection cancelled — no PRDs written."
  exit 0
fi

SELECTED_SLUGS=$(echo "$SELECTION_JSON" | jq -r '.selected_slugs[]')
N_SELECTED=$(echo "$SELECTION_JSON" | jq '.selected_slugs | length')
```

`select-themes.sh` preserves input order (contract: "Selection MUST preserve input order") so downstream emission stays deterministic.

## Step 3.5: Research-Block Propagation (FR-005 — FR-008 of research-first-completion)

<!-- T006 / FR-005 / FR-006 / FR-007 / FR-008 / NFR-003 / NFR-005 /
     contracts/interfaces.md §5 + §6 (research-first-completion).
     Propagate optional research-block fields (needs_research,
     empirical_quality, fixture_corpus, fixture_corpus_path,
     promote_synthesized, excluded_fixtures) from selected source artifacts
     into the generated PRD frontmatter. Skip path is byte-identical (FR-008
     / NFR-005). -->

Before emitting per-theme PRDs in Step 4, project research-block fields
from every selected source artifact, detect conflicts, and union-merge into
a per-theme research-block JSON that the frontmatter writer will inline
between the `theme:` key and any future schema extension. **Skip when no
selected source declares `needs_research: true`** — this preserves byte-
identity (NFR-005) for backlogs without research-block intent.

### §3.5.1 — Per-theme research-block JSON

Per theme, walk the bundled entries (`BUNDLED_ENTRIES_JSON` from Step 4's
loop preview) and extract research-block fields from each via
`plugin-kiln/scripts/research/parse-research-block.sh`:

```bash
# RESEARCH_PARSER is the universal frontmatter→research-block extractor
# (handles items / issues / feedback uniformly via flow-style YAML parse).
RESEARCH_PARSER="plugin-kiln/scripts/research/parse-research-block.sh"

per_theme_research_jsons=()  # one JSON projection per source path
for path in $FEEDBACK_PATHS $ITEM_PATHS $ISSUE_PATHS; do
  proj=$(bash "$RESEARCH_PARSER" "$path" 2>/dev/null) || continue
  per_theme_research_jsons+=("$proj")
done

# Collapse to a single JSON array (one entry per source).
SOURCES_JSON=$(printf '%s\n' "${per_theme_research_jsons[@]}" | jq -s -c '.')
```

### §3.5.2 — Detect conflicts (FR-006 / NFR-004)

Conflicts arise when two or more sources declare the **same** `metric` with
**different** `direction` values, or different scalar values for any of
`fixture_corpus | fixture_corpus_path | promote_synthesized`, or different
`reason` for the same `excluded_fixtures[].path`.

```bash
# Axis-direction conflicts (per metric).
AXIS_CONFLICTS=$(jq -c '
  [.[] | (.empirical_quality // []) | .[]]
  | group_by(.metric)
  | map(select((map(.direction) | unique | length) > 1))
' <<<"$SOURCES_JSON")

# Scalar-value conflicts (per scalar key).
SCALAR_CONFLICTS=$(jq -c '
  reduce .[] as $s ({};
    (.fixture_corpus // []) += ([$s.fixture_corpus] | map(select(. != null))) |
    (.fixture_corpus_path // []) += ([$s.fixture_corpus_path] | map(select(. != null))) |
    (.promote_synthesized // []) += ([$s.promote_synthesized] | map(select(. != null)))
  )
  | to_entries
  | map(select((.value | unique | length) > 1))
' <<<"$SOURCES_JSON")
```

If `AXIS_CONFLICTS` or `SCALAR_CONFLICTS` are non-empty, surface the
**FR-006 conflict prompt** (verbatim shape from contracts §6):

```
Conflict on <key>: <metric-or-scalar-key>
  <source-path-A> declares <key>: <value-A>
  <source-path-B> declares <key>: <value-B>
  ...
Pick one <key> or specify a third.
> _
```

The user picks one of the listed values OR types a fresh value (validated
against the relevant ALLOWED enum). Typing `abandon` or sending EOF →
distill **exits 2 without writing the PRD**. Empty input → re-prompts. NO
cap on N (OQ-1 — confirmed no cap in v1).

This is a **confirm-never-silent** prompt — distill MUST NOT silently merge
or pick a winner. NFR-004 verbatim contract: bad shape "axes conflict,
please resolve"; good shape names both source paths and both
`(metric, direction)` pairs.

### §3.5.3 — Union-merge axes (FR-005 — canonical jq expression)

After conflicts are resolved (or absent), compute the merged research-block
per theme. The canonical jq expression is the single source of truth for
axis ordering (NFR-003 determinism hook):

```bash
MERGED_AXES=$(jq -c '
  [.[] | (.empirical_quality // []) | .[]]
  | group_by(.metric + ":" + .direction)
  | map({
      metric: .[0].metric,
      direction: .[0].direction,
      priority: (
        if any(.priority == "primary") then "primary" else "secondary" end
      )
    } + (
      if .[0].metric == "output_quality" then {rubric: .[0].rubric} else {} end
    ))
  | sort_by(.metric, .direction)
' <<<"$SOURCES_JSON")
```

Scalar-key propagation (FR-007 verbatim — no synthesis, no normalization):

```bash
NEEDS_RESEARCH=$(jq -r 'any(.needs_research == true)' <<<"$SOURCES_JSON")
FIXTURE_CORPUS=$(jq -r 'map(.fixture_corpus) | map(select(. != null)) | unique | first // empty' <<<"$SOURCES_JSON")
FIXTURE_CORPUS_PATH=$(jq -r 'map(.fixture_corpus_path) | map(select(. != null)) | unique | first // empty' <<<"$SOURCES_JSON")
PROMOTE_SYNTHESIZED=$(jq -r 'map(.promote_synthesized) | map(select(. != null)) | unique | first // empty' <<<"$SOURCES_JSON")
EXCLUDED_FIXTURES=$(jq -c '
  [.[] | (.excluded_fixtures // []) | .[]]
  | group_by(.path)
  | map(.[0])
  | sort_by(.path)
' <<<"$SOURCES_JSON")
```

### §3.5.4 — Skip path (FR-008 byte-identity)

When `NEEDS_RESEARCH` is `false` (no source declared `needs_research: true`),
distill **OMITS all research-block keys** from the generated PRD frontmatter
and emits the existing three-key skeleton (`derived_from`, `distilled_date`,
`theme`) byte-identically to pre-research-first behavior (NFR-005). No
"needs_research: false" key is written; structural absence is the byte-
identity reference path (matches the classifier NFR-006 pattern).

### §3.5.5 — Emit research-block keys (FR-005 / FR-007 / contracts §1)

When `NEEDS_RESEARCH == true`, the frontmatter emitter inlines the
research-block keys **after** `theme:` in this exact order (contracts §1
PRD frontmatter authoritative key order):

```yaml
theme: <theme-slug>
needs_research: true
empirical_quality: <merged_axes_inline_flow>
fixture_corpus: <value>            # only when set
fixture_corpus_path: <value>       # only when set
promote_synthesized: <bool>        # only when set
excluded_fixtures: <list>          # only when non-empty
```

Empty / null scalar keys are OMITTED entirely (NOT emitted as `null`) —
absence is the structural-default per the schema contract.

## Step 4: Generate the Feature PRD(s)

Using the selected themes, generate **one PRD per selected theme** — loop over `SELECTED_SLUGS` and emit N distinct PRDs (FR-017 of `coach-driven-capture-ergonomics`). Each PRD follows the same structure as `/kiln:kiln-create-prd` Mode B (feature addition), and each PRD independently satisfies the `derived_from:` three-group determinism invariant (FR-020 / NFR-003).

### PRD Location (multi-theme — FR-017 slug disambiguation)

<!-- FR-017 + research.md §4: when two selections share date+slug, the second (and subsequent) get numeric suffixes `-2`, `-3`. Also skip over committed `docs/features/<date>-<slug>/` directories from earlier runs. -->

Compute one directory name per selected slug via the disambiguator:

```bash
DATE=$(date -u +%Y-%m-%d)

# shellcheck disable=SC2086 — we intentionally split SELECTED_SLUGS on whitespace.
DISAMBIG_OUTPUT=$(bash plugin-kiln/scripts/distill/disambiguate-slug.sh "$DATE" $SELECTED_SLUGS)

# Parallel arrays: SELECTED_SLUGS[i] → DISAMBIG_DIRS[i].
mapfile -t DISAMBIG_DIRS <<<"$DISAMBIG_OUTPUT"
mapfile -t SLUGS_ARR <<<"$SELECTED_SLUGS"
```

The first occurrence of each unique slug stays un-suffixed (`2026-04-24-coaching`); subsequent occurrences get `-2`, `-3`, … AND the algorithm skips past any committed `docs/features/<date>-<slug>/` directory left by earlier distill runs (research.md §4).

Emit each PRD under: `docs/features/<DISAMBIG_DIRS[i]>/PRD.md`

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
- **FR-007 three-group shape (workflow-governance)**: the three-group SORT ORDER (feedback → item → issue, filename ASC within each) MUST be preserved even when the feedback or issue groups are empty. An item-only bundle emits a `derived_from:` list with only item paths but still in the stable order; re-running with identical inputs MUST produce byte-identical frontmatter. Tests `distill-gate-three-group-shape` and `distill-multi-theme-determinism` lock this invariant.
- **FR-008 grandfathering (workflow-governance)**: the new gate (Step 0.5) operates only on INPUT candidates (`.kiln/issues/*.md`, `.kiln/feedback/*.md`). Pre-existing PRDs under `docs/features/` with raw-issue `derived_from:` entries are NOT revisited by the gate — their `distilled_date:` predates the rollout (`2026-04-24`) and grandfathering is by construction. If a future validator ever needs to check existing PRDs under the new gate, the cutoff constant lives at `plugin-kiln/scripts/distill/detect-un-promoted.sh` header comment (currently: gate only touches input candidates, no validator needed).

### Per-Theme Emission Loop (FR-017 / FR-019 / FR-020 — multi-theme scope)

<!-- FR-019: source-entry status flips MUST be partitioned per-PRD. Each emitted PRD only flips the entries it actually bundled. The implementation MUST assert per-flip that the target entry is in the current PRD's bundle. -->

For each selected theme, build a **per-theme bundle** (the subset of all selected entries that belong to THIS theme), then emit the PRD and, in Step 5, flip the state ONLY of entries in this bundle.

```bash
for i in "${!SLUGS_ARR[@]}"; do
  SLUG="${SLUGS_ARR[i]}"
  DIR="${DISAMBIG_DIRS[i]}"
  PRD_PATH="docs/features/$DIR/PRD.md"

  # BUNDLED_ENTRIES[i] is the set of source-entry paths belonging to this
  # theme — computed from Step 2's theme-grouping step. Each entry carries
  # its type_tag (feedback / item / issue) so the three-group sort runs per-PRD.
  BUNDLED_ENTRIES_JSON=$(echo "$GROUPED_THEMES_JSON" | jq --arg s "$SLUG" '.[] | select(.slug == $s) | .entries')

  # Sort into the three-group derived_from order ONCE per PRD (FR-020).
  # This is the determinism hook — sort MUST run with LC_ALL=C for
  # byte-identical output across platforms.
  FEEDBACK_PATHS=$(echo "$BUNDLED_ENTRIES_JSON" | jq -r '.[] | select(.type_tag == "feedback") | .path' | LC_ALL=C sort)
  ITEM_PATHS=$(echo "$BUNDLED_ENTRIES_JSON"    | jq -r '.[] | select(.type_tag == "item")     | .path' | LC_ALL=C sort)
  ISSUE_PATHS=$(echo "$BUNDLED_ENTRIES_JSON"   | jq -r '.[] | select(.type_tag == "issue")    | .path' | LC_ALL=C sort)

  # Render the PRD — frontmatter derived_from: uses FEEDBACK + ITEM + ISSUE
  # in that three-group order, filename ASC within each (NFR-003 hook).
  # See "YAML Frontmatter Emission" below.
  write_prd "$PRD_PATH" "$SLUG" "$FEEDBACK_PATHS" "$ITEM_PATHS" "$ISSUE_PATHS"

  # Stash this PRD's bundle for Step 5 state flips.
  # Flat list of paths; Step 5 iterates and asserts each path belongs here.
  PRD_BUNDLES+=("$PRD_PATH|$FEEDBACK_PATHS|$ITEM_PATHS|$ISSUE_PATHS")
done
```

**Critical invariant** (FR-019): each PRD's Step-5 state flips MUST ONLY touch the paths in its own `FEEDBACK_PATHS | ITEM_PATHS | ISSUE_PATHS`. Cross-PRD overwrites are prohibited. The assertion guard lives in Step 5.

**Byte-identical determinism** (FR-020 / NFR-003 + SC-005): re-running `/kiln:kiln-distill` against unchanged inputs MUST produce the same per-PRD frontmatter byte-for-byte. The `LC_ALL=C sort` above is the determinism hook; no timestamps or env-varying strings are inserted into frontmatter.

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

After **each** PRD is written, update each included source entry. In multi-theme mode, iterate the per-PRD bundles captured in Step 4 and flip state ONLY for entries in the current bundle (FR-019 partition guarantee).

```bash
# For each emitted PRD, flip the state of its bundled entries only.
for bundle_row in "${PRD_BUNDLES[@]}"; do
  IFS='|' read -r PRD_PATH FEEDBACK_PATHS ITEM_PATHS ISSUE_PATHS <<<"$bundle_row"

  # Build the guard: a set of paths that SHOULD be flipped by this PRD.
  # Every actual flip must match one of these paths — otherwise it's a
  # cross-PRD contamination bug (FR-019).
  BUNDLED_PATHS=$(printf '%s\n%s\n%s\n' "$FEEDBACK_PATHS" "$ITEM_PATHS" "$ISSUE_PATHS" | LC_ALL=C sort -u | sed '/^$/d')

  assert_in_bundle() {
    local path="$1"
    if ! echo "$BUNDLED_PATHS" | grep -qxF "$path"; then
      echo "ERROR: refused to flip state of $path — not in bundle for $PRD_PATH (FR-019 guard)" >&2
      return 1
    fi
    return 0
  }

  # Flip feedback + issue entries (5a protocol).
  for path in $(echo "$FEEDBACK_PATHS"; echo "$ISSUE_PATHS"); do
    [ -z "$path" ] && continue
    assert_in_bundle "$path" || continue
    flip_feedback_or_issue "$path" "$PRD_PATH"
  done

  # Flip roadmap items (5b protocol — atomic-ish state flip + prd: patch).
  for path in $ITEM_PATHS; do
    [ -z "$path" ] && continue
    assert_in_bundle "$path" || continue
    flip_roadmap_item "$path" "$PRD_PATH"
  done
done
```

The protocol branches on `type_tag`:

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

Emit one "PRD Created" block per emitted PRD. When N≥2 PRDs were emitted, append the **run-plan block** (FR-018) at the VERY END of the output.

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

### Run-Plan Block (FR-018 — emitted only when N≥2)

<!-- FR-018 of `coach-driven-capture-ergonomics`: run-plan block summarizes emitted PRDs with a suggested pipeline order and one-line rationale per line. MUST be OMITTED when only 1 PRD was emitted (single-theme byte-identical compat — FR-021 / NFR-005). -->

After every "PRD Created" block has been printed, if `N_SELECTED >= 2`, build an emissions JSON and invoke `emit-run-plan.sh`:

```bash
if [ "$N_SELECTED" -ge 2 ]; then
  EMISSIONS_JSON=$(mktemp)
  # Build array: one element per emitted PRD. `severity_hint` and
  # `rationale` are optional — emit-run-plan.sh derives a default rationale
  # from the severity label when rationale is absent.
  {
    echo '['
    for i in "${!SLUGS_ARR[@]}"; do
      SLUG="${SLUGS_ARR[i]}"
      DIR="${DISAMBIG_DIRS[i]}"
      # Comma separator between objects (not after the last one).
      [ "$i" -gt 0 ] && echo ','
      printf '{"slug":"%s","path":"docs/features/%s/PRD.md","severity_hint":"%s"}' \
        "$SLUG" "$DIR" "${PRD_SEVERITY_HINTS[i]:-null}"
    done
    echo ']'
  } > "$EMISSIONS_JSON"

  # Emit block to stdout (empty when N<2 — defensive double-check).
  bash plugin-kiln/scripts/distill/emit-run-plan.sh "$EMISSIONS_JSON"
  rm -f "$EMISSIONS_JSON"
fi
```

**Example output for N=2** (FR-018 rendering):

```markdown
## Run Plan

Suggested pipeline order for the emitted PRDs:

1. `/kiln:kiln-build-prd foundation` — foundational — touches shared infrastructure
2. `/kiln:kiln-build-prd user-flow` — highest severity from bundle
```

Ordering: `foundational` first, then `highest`, `med`, `low`, `null`. Ties break on input order (stable-sort, contract §emit-run-plan.sh).

## Rules

- Never delete feedback, item, or issue entries — only update their status / state
- If the user has no parent PRD (`docs/PRD.md` doesn't exist), the generated PRD is standalone — don't require a parent
- Don't invent requirements that aren't backed by a source entry — the PRD should address what was captured, nothing more
- If an issue entry references a GitHub issue, include the issue number in the PRD for traceability (feedback + items have no GitHub issue column)
- Keep the PRD focused — if themes are too different to fit in one coherent PRD, suggest splitting into multiple PRDs
- Feedback leads the narrative; roadmap items anchor Background paragraph 2 concretely; issues are tactical — do NOT bury a feedback theme beneath tactical issues in the PRD body (FR-012 + FR-024 of structured-roadmap)
- **Item state updates are atomic-ish**: state flip → prd: patch. Rollback the state flip if the patch fails (FR-026 / contract §7.5). Never leave an item with `state: distilled` but no `prd:`.
- **Implementation hints flow through, don't re-elicit** (FR-027): if an item carries `implementation_hints:`, render them in `## Implementation Hints` with an item-id back-reference. Do NOT ask the user to restate them.
- **Determinism** (NFR-003 + FR-037): the three-group sort (feedback → item → issue, filename ASC within each group) is the byte-identical output guarantee. Do NOT reorder entries for aesthetics. In multi-theme mode, this invariant holds **per-PRD** (FR-020 of `coach-driven-capture-ergonomics`).
- **Multi-theme state-flip partition** (FR-019 of `coach-driven-capture-ergonomics`): each emitted PRD only flips the entries it actually bundled. The `assert_in_bundle` guard in Step 5 is NON-NEGOTIABLE — a flip of a path not in the current PRD's bundle is a cross-contamination bug and MUST abort the flip.
- **Single-theme byte-identical compat** (FR-021 / NFR-005): when N=1 (only one theme picked, or only one theme present in the backlog), the emitted PRD + status flips MUST be byte-identical to pre-multi-theme distill behavior. The picker appears but auto-resolves; the run-plan block is OMITTED.
- Don't auto-commit — let the user review first
