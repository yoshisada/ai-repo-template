---
name: kiln-roadmap
description: Capture a product-direction idea (feature / goal / research / constraint / non-goal / milestone / critique) as a structured item under `.kiln/roadmap/items/`. Runs an adversarial interview, classifies kind, routes cross-surface (issue / feedback / roadmap) with confirm-never-silent hand-off, migrates legacy `.kiln/roadmap.md` on first run, and mirrors to Obsidian via `shelf:shelf-write-roadmap-note`. Flags — `--quick` (no interview), `--vision` (vision update), `--phase start|complete|create <name>`, `--check` (lifecycle audit), `--check --fix` (confirm-never-silent fixer for merged-PR drift; FR-010 of merge-pr-and-sc-grep-guidance), `--reclassify` (promote unsorted), `--promote <path>` (promote a raw issue/feedback file into a roadmap item; FR-006 of workflow-governance). Use as `/kiln:kiln-roadmap <description>`.
---

# Kiln Roadmap — Structured Product-Direction Capture

Replaces the old `.kiln/roadmap.md` scratchpad. Captures one item per file under `.kiln/roadmap/items/<YYYY-MM-DD>-<slug>.md` with typed frontmatter, AI-native sizing (no human-time / T-shirt fields — schema-enforced), and an adversarial interview that pushes back on thin ideas.

Contract: `specs/structured-roadmap/contracts/interfaces.md`. Spec: `specs/structured-roadmap/spec.md`. PRD: `docs/features/2026-04-23-structured-roadmap/PRD.md`.

## User Input

```text
$ARGUMENTS
```

Arguments may include the free-text description and/or any of these flags:

- `--quick` — skip the adversarial interview; write a minimal item to `phase: unsorted` (FR-018 / PRD FR-018). Also auto-activated in non-interactive sessions (FR-018 / FR-039).
- `--vision` — update `.kiln/vision.md` instead of capturing an item (FR-019 / PRD FR-019). When invoked alone, runs the coached interview (NFR-005 byte-identical pre-PRD path); when invoked with one of the simple-params flags below, runs the deterministic ≤3-second writer in §V-A and SKIPS the coached interview (vision-tooling FR-001/FR-002/FR-005/FR-014).
  - `--vision --add-constraint <text>` — append a bullet under `## Guiding constraints`.
  - `--vision --add-non-goal <text>` — append a bullet under `## What it is not`.
  - `--vision --add-signal <text>` — append a bullet under `## How we'll know we're winning`.
  - `--vision --update-what <body>` — replace the body of `## What we are building`.
  - `--vision --update-not <body>` — replace the body of `## What it is not`.
  - `--vision --update-signals <body>` — replace the body of `## How we'll know we're winning`.
  - `--vision --update-constraints <body>` — replace the body of `## Guiding constraints`.
  - At most ONE simple-params flag per invocation; conflicts and unknown `--add-*`/`--update-*` flags exit non-zero before any I/O (FR-005 / SC-002). Section-flag mapping table is single-sourced in `plugin-kiln/scripts/roadmap/vision-section-flag-map.sh` (FR-021).
- `--phase start <name>` / `--phase complete <name>` / `--phase create <name> --order <N>` — phase management (FR-020 / PRD FR-020).
- `--check` — report items whose `state` is inconsistent with phase/spec/PR reality (FR-022 / PRD FR-022).
- `--check --fix` — confirm-never-silent fixer for the merged-PR drift Check 5 surfaces. Prompts `[fix all / pick / skip]`; on accept invokes the shared `auto-flip-on-merge.sh` helper per item. Empty/unknown input is treated as `skip` (NFR-004). Required for items merged via the GitHub web UI or `gh pr merge` directly (i.e. NOT through `/kiln:kiln-merge-pr`). FR-010 / FR-011 of merge-pr-and-sc-grep-guidance.
- `--reclassify` — walk all `phase: unsorted` items through the interview to promote them (FR-028 follow-up).
- `--promote <source-path-or-issue-number>` — promote a raw `.kiln/issues/*.md` or `.kiln/feedback/*.md` source into a structured roadmap item with `promoted_from:` back-reference, and flip the source's frontmatter to `status: promoted` + `roadmap_item:` (FR-006 of workflow-governance). See **§M: Promote source** below.

## Constants and paths (FR-001..FR-004 / PRD FR-001..FR-004)

```bash
VISION_FILE=".kiln/vision.md"
PHASES_DIR=".kiln/roadmap/phases"
ITEMS_DIR=".kiln/roadmap/items"
LEGACY_FILE=".kiln/roadmap.md"
LEGACY_ARCHIVE=".kiln/roadmap.legacy.md"

# Helper scripts (FR-038 / spec FR-038: shared helpers exposed for other skills)
SCRIPTS="plugin-kiln/scripts/roadmap"
H_PARSE_ITEM="$SCRIPTS/parse-item-frontmatter.sh"
H_VALIDATE_ITEM="$SCRIPTS/validate-item-frontmatter.sh"
H_VALIDATE_PHASE="$SCRIPTS/validate-phase-frontmatter.sh"
H_LIST_ITEMS="$SCRIPTS/list-items.sh"
H_UPDATE_STATE="$SCRIPTS/update-item-state.sh"
H_UPDATE_PHASE="$SCRIPTS/update-phase-status.sh"
H_MIGRATE="$SCRIPTS/migrate-legacy-roadmap.sh"
H_SEED="$SCRIPTS/seed-critiques.sh"
H_CLASSIFY="$SCRIPTS/classify-description.sh"
H_MULTI="$SCRIPTS/detect-multi-item.sh"

# Templates
T_VISION="plugin-kiln/templates/vision-template.md"
T_PHASE="plugin-kiln/templates/roadmap-phase-template.md"
T_ITEM="plugin-kiln/templates/roadmap-item-template.md"
T_CRITIQUE="plugin-kiln/templates/roadmap-critique-template.md"
```

---

## Step 0: First-run bootstrap (FR-001, FR-002, FR-028, FR-029 / PRD FR-001, FR-002, FR-028, FR-029)

<!-- FR-001 / PRD FR-001: create .kiln/vision.md from template on first run.
     FR-002 / PRD FR-002: create .kiln/roadmap/{phases,items}/ on first run.
     FR-028 / PRD FR-028: migrate legacy .kiln/roadmap.md if present.
     FR-029 / PRD FR-029: seed three named critiques when items dir is empty. -->

Run this bootstrap on every invocation — it's idempotent and cheap.

```bash
mkdir -p "$PHASES_DIR" "$ITEMS_DIR"

# 1. Vision
if [ ! -f "$VISION_FILE" ]; then
  if [ -f "$T_VISION" ]; then
    cp "$T_VISION" "$VISION_FILE"
    echo "bootstrap: created $VISION_FILE from template"
  else
    printf '# Product Vision\n\n_Fill this in._\n' > "$VISION_FILE"
  fi
fi

# 2. Default phases (foundations, current, next, later, unsorted)
seed_phase() {
  local name="$1" order="$2" status="$3"
  local file="$PHASES_DIR/$name.md"
  [ -f "$file" ] && return 0
  if [ -f "$T_PHASE" ]; then
    sed -e "s/<phase-name>/$name/g" "$T_PHASE" \
      | awk -v s="$status" -v o="$order" '
          /^status: planned$/ { print "status: " s; next }
          /^order: 0$/        { print "order: "  o; next }
          { print }
        ' > "$file"
  else
    cat > "$file" <<EOF
---
name: $name
status: $status
order: $order
---

# $name

## Items
EOF
  fi
}
seed_phase "foundations" 0 "planned"
seed_phase "current"     1 "planned"
seed_phase "next"        2 "planned"
seed_phase "later"       3 "planned"
seed_phase "unsorted"    99 "planned"

# 3. Legacy migration (one-shot, idempotent)
MIG="$(bash "$H_MIGRATE" 2>/dev/null || echo '{"migrated":0}')"
MIG_COUNT="$(echo "$MIG" | grep -oE '"migrated":[0-9]+' | cut -d: -f2)"
if [ -n "$MIG_COUNT" ] && [ "$MIG_COUNT" -gt 0 ]; then
  echo "bootstrap: migrated $MIG_COUNT items from legacy .kiln/roadmap.md"
  echo "bootstrap: run '/kiln:kiln-roadmap --reclassify' to promote them out of unsorted"
fi

# 4. Seed critiques (FR-029) — only fires when items dir is empty
SEED="$(bash "$H_SEED" 2>/dev/null || echo '{"created":0}')"
SEED_COUNT="$(echo "$SEED" | grep -oE '"created":[0-9]+' | cut -d: -f2)"
if [ -n "$SEED_COUNT" ] && [ "$SEED_COUNT" -gt 0 ]; then
  echo "bootstrap: seeded $SEED_COUNT named critiques"
fi
```

### `.shelf-config` warning (FR-040 / spec FR-040)

If `.shelf-config` is missing or lacks `slug` + `base_path`, print ONE warning per session and continue — do not fail.

```bash
if [ ! -f ".shelf-config" ] || ! grep -qE '^slug[[:space:]]*=' .shelf-config || ! grep -qE '^base_path[[:space:]]*=' .shelf-config; then
  echo "warn: Obsidian mirror skipped — .shelf-config incomplete (FR-040)" >&2
  SHELF_MIRROR_ENABLED=0
else
  SHELF_MIRROR_ENABLED=1
fi
```

---

## Step 1: Dispatch on flag (routing gate)

Parse `$ARGUMENTS` for the mode flags in this order. First match wins. If none match, fall through to the capture pipeline (Step 2 onward).

- `--vision` AND any of `--add-constraint`, `--add-non-goal`, `--add-signal`, `--update-what`, `--update-not`, `--update-signals`, `--update-constraints` → jump to **§V-A: Vision simple-params CLI** (vision-tooling FR-001 / FR-002 / FR-005 / FR-014). The simple-params dispatch is checked BEFORE the coached interview path so any matched flag short-circuits §V (FR-001 final sentence).
- `--vision` (no simple-params flags) → jump to **§V: Vision update** (coached interview, NFR-005 byte-identical pre-PRD path).
- `--phase` → jump to **§P: Phase management**.
- `--check` → jump to **§C: Consistency check**. If the same invocation also includes `--fix`, set `FIX_MODE=true` BEFORE entering §C, then run §C-fix immediately after §C completes (FR-010 of merge-pr-and-sc-grep-guidance).
- `--reclassify` → jump to **§R: Reclassify unsorted**.
- `--promote <source>` → jump to **§M: Promote source** (FR-006 of workflow-governance).
- `--quick` → set `QUICK_MODE=1`, strip the flag, continue to capture pipeline.
- Otherwise → the remaining text is the description; continue.

If the session is non-interactive (no TTY), auto-set `QUICK_MODE=1` regardless (FR-018 / FR-039).

```bash
# Detect non-interactive
if ! [ -t 0 ] || ! [ -t 1 ]; then
  NON_INTERACTIVE=1
else
  NON_INTERACTIVE=0
fi
```

---

## Step 1b: Load context (FR-013 / PRD FR-013)

<!-- FR-013 / PRD FR-013: MUST first read .kiln/vision.md, all .kiln/roadmap/phases/*.md, and all .kiln/roadmap/items/*.md to build context BEFORE classification. -->

This step runs ONLY when proceeding to the capture pipeline (i.e., when no flag dispatched the skill to §V, §P, §C, or §R). If `QUICK_MODE=1` and `NON_INTERACTIVE=1`, still read for context — the classifier uses it.

```bash
# FR-013: read existing state for context before classification
VISION_CONTENT="$(cat "$VISION_FILE" 2>/dev/null || echo "(no vision yet)")"

# Summarise existing phases for context
PHASES_SUMMARY=""
if [ -d "$PHASES_DIR" ]; then
  while IFS= read -r pf; do
    pname="$(basename "$pf" .md)"
    pstatus="$(awk '/^status:[[:space:]]/ { sub(/^status:[[:space:]]*/,""); print; exit }' "$pf" 2>/dev/null)"
    PHASES_SUMMARY="${PHASES_SUMMARY}  - ${pname} (${pstatus:-unknown})\n"
  done < <(ls "$PHASES_DIR"/*.md 2>/dev/null)
fi

# Count and summarise existing items for context (don't load every file — just the list)
ITEMS_PATHS="$(bash "$H_LIST_ITEMS" 2>/dev/null || true)"
ITEMS_COUNT="$(printf '%s' "$ITEMS_PATHS" | grep -c . || echo 0)"

# Surface context summary to the AI agent (used implicitly in classification and interview)
echo "context: vision=$([ -f "$VISION_FILE" ] && echo present || echo absent)  phases=$(echo "$PHASES_SUMMARY" | grep -c . || echo 0)  items=$ITEMS_COUNT"

# coach-driven-capture FR-001: load the richer ProjectContextSnapshot (offline,
# deterministic — see specs/coach-driven-capture-ergonomics/contracts/interfaces.md).
# Consumed by the orientation block (§1c) and by per-question coaching (§5).
# Gracefully degrade on reader failure: we keep the legacy uncoached pipeline.
READER="plugin-kiln/scripts/context/read-project-context.sh"
if [ -f "$READER" ]; then
  CTX_JSON="$(bash "$READER" 2>/dev/null)" || CTX_JSON=""
fi
if [ -z "${CTX_JSON:-}" ]; then
  CTX_JSON='{"schema_version":"1","prds":[],"roadmap_items":[],"roadmap_phases":[],"vision":null,"claude_md":null,"readme":null,"plugins":[]}'
  echo "warn: project-context reader unavailable; falling back to uncoached interview" >&2
  COACH_AVAILABLE=0
else
  COACH_AVAILABLE=1
fi
```

The AI agent SHOULD also scan the first 20 lines of each existing phase file and a random sample of recent item files to build richer classification context, but this bash preamble ensures the *minimum required context* (vision, phase list, item count) is available before Step 2.

---

## Step 1c: Orientation block (coach-driven-capture FR-006)

<!-- coach-driven-capture FR-006: Before the first interview question, emit a
     one-paragraph ORIENTATION block that cites:
       (a) the current phase (from roadmap_phases[] where status == in-progress),
       (b) up to 3 nearby items (in that phase),
       (c) any open critiques whose addresses[] might be relevant,
       (d) a short vision summary if .kiln/vision.md exists.
     This block MUST precede every non-`--quick` invocation. It MUST NOT appear
     under `--quick` (NFR-005) and MUST NOT appear in `NON_INTERACTIVE` sessions. -->

Skip the orientation block entirely when `QUICK_MODE == 1` OR `NON_INTERACTIVE == 1` OR `COACH_AVAILABLE == 0`. This is the NFR-005 byte-identical guarantee for the `--quick` path.

Otherwise, derive orientation data from `CTX_JSON` and emit a single paragraph of prose framed collaboratively — "Here's what I think the landscape looks like, tell me if I'm off":

```bash
CURRENT_PHASE="$(echo "$CTX_JSON" | jq -r '.roadmap_phases[] | select(.status=="in-progress") | .name' | head -1)"
NEARBY_ITEMS="$(echo "$CTX_JSON" | jq -r --arg p "${CURRENT_PHASE:-}" '.roadmap_items[] | select(.phase==$p) | .id' | head -3)"
OPEN_CRITIQUES="$(echo "$CTX_JSON" | jq -r '.roadmap_items[] | select(.kind=="critique" and .state != "shipped" and .state != "archived") | .id')"
VISION_HEAD="$(echo "$CTX_JSON" | jq -r '.vision.body // empty' | awk 'NF' | head -3)"
```

Render the block to the user BEFORE Question 1. Example shape:

```
Here's what I think the landscape looks like — tell me if I'm off:

We're in the current phase (`<CURRENT_PHASE>`). Nearby items: <up to 3 ids>.
Open critiques that this idea might address: <list>. And from .kiln/vision.md:
<one-line summary>.

If that framing is wrong, say so now and we'll re-anchor before the questions.
```

Rendering rules (tone calibration for FR-007 / PRD FR-006):

- When `CURRENT_PHASE` is empty (no in-progress phase), say "No phase is in progress yet — I'll treat this as a `planned` idea unless you tell me otherwise."
- When `NEARBY_ITEMS` is empty, say "No nearby items to compare against."
- When `OPEN_CRITIQUES` is empty, say "No open critiques to worry about right now."
- When `VISION_HEAD` is empty, say "No vision summary yet — running `/kiln:kiln-roadmap --vision` would help me calibrate future captures."
- NEVER invent content. If a signal is missing, SAY it's missing — placeholder values degrade trust fast (see edge case "Coached suggestions low-quality on sparse repos" in the spec).

---

## Step 2: Cross-surface routing (FR-014, FR-014b / PRD FR-014, FR-014b — confirm-never-silent)

<!-- FR-014 / PRD FR-014: tactical → offer kiln-report-issue; strategic → offer kiln-feedback; product-intent → stay in roadmap.
     FR-014b / PRD FR-014b: hand-off MUST invoke target skill via the Skill tool, not print instructions.
     FR-036 / spec FR-036: test asserts skill invocation, not printed text.
     Absolute Must #6: NEVER silently re-route. -->

If the user typed no description, ask:

> What's the item? (feature, critique, research question, non-goal, milestone — the adversarial interview will figure out the kind)

With a description in hand, classify:

```bash
DESC="$*"          # or the remaining args after flag parsing
CLASSIFY_JSON="$(bash "$H_CLASSIFY" "$DESC")"
SURFACE="$(echo "$CLASSIFY_JSON" | jq -r '.surface')"
CONFIDENCE="$(echo "$CLASSIFY_JSON" | jq -r '.confidence')"
KIND="$(echo "$CLASSIFY_JSON" | jq -r '.kind // empty')"
```

### Routing prompt — shown when surface != "roadmap" OR confidence == "low"

Present exactly this text — do not paraphrase:

```
This description could go to one of three places. Which captures your intent best?
  (a) /kiln:kiln-roadmap       — product intent (build / investigate / steer)
  (b) /kiln:kiln-report-issue  — bug or friction with something that exists
  (c) /kiln:kiln-feedback      — strategic note about direction or scope

Pick (a) / (b) / (c):
```

On the user's choice:

- `(a)` → continue here (Step 3 onward).
- `(b)` → **invoke the `Skill` tool** with `{skill: "kiln:kiln-report-issue", args: "<the original description verbatim>"}` and EXIT. Do NOT write a roadmap item. Do NOT print "go run X instead".
- `(c)` → **invoke the `Skill` tool** with `{skill: "kiln:kiln-feedback", args: "<the original description verbatim>"}` and EXIT.

This is the FR-014b invariant — the test (T033) asserts the Skill tool was invoked, not that text appeared.

Skip the prompt entirely when `surface == "roadmap"` AND `confidence == "high"` — the classifier is confident enough to stay.

In `QUICK_MODE`, skip the routing prompt too — `--quick` trusts the user's framing.

---

## Step 3: Multi-item detection (FR-018a, FR-018b / PRD FR-018a, FR-018b)

<!-- FR-018a / PRD FR-018a: bullets / numbered / "and also" / newline-separated → N items.
     FR-018b / PRD FR-018b: multi splits share ONE phase-assignment interview up front. -->

```bash
MULTI_JSON="$(bash "$H_MULTI" "$DESC")"
IS_MULTI="$(echo "$MULTI_JSON" | jq -r '.is_multi')"
```

If `IS_MULTI == "true"` AND not `QUICK_MODE` AND not `NON_INTERACTIVE`:

```
Detected N things to capture:
  1. <item-1>
  2. <item-2>
  ...

How should I handle these?
  (a) N separate items   [default]
  (b) one bundled item
  (c) split and review each
```

- On `(a)` / `(c)`: ask the phase-assignment question ONCE up front (FR-018b), then loop the per-item capture (Step 4+) for each entry in `items[]`.
- On `(b)`: treat the whole description as one item.

In `QUICK_MODE` or `NON_INTERACTIVE`: default to `(a)` silently — no prompt.

---

## Step 4: Within-roadmap kind detection (FR-014a / PRD FR-014a)

The classifier already suggested a `kind`. If `confidence == "low"` or user just said "yes" to an ambiguous route, confirm:

> I think this is a `<kind>` item — (a) yes, (b) pick different: feature / goal / research / constraint / non-goal / milestone / critique

Set `KIND` to the confirmed value. If `QUICK_MODE`, keep the suggested kind without asking.

---

## Step 5: Coached interview (FR-015, FR-017 / PRD FR-015, FR-017; coach-driven-capture FR-004, FR-005, FR-007)

<!-- FR-015 / PRD FR-015: ≤5 questions per kind, each individually skippable.
     FR-017 / PRD FR-017: sizing asks ONLY blast_radius / review_cost / context_cost — never human-time / T-shirt.
     FR-011 / PRD FR-011: kind:critique REQUIRES proof_path — re-prompt until answered.
     coach-driven-capture FR-004: every question renders with a proposed answer + one-line rationale + `[accept / tweak / reject]` affordance.
     coach-driven-capture FR-005: user may type `accept-all` at any prompt to finalize using remaining suggestions; `tweak <value> then accept-all` overrides the current question then finalizes.
     coach-driven-capture FR-007: prompt copy is COLLABORATIVE ("Here's what I think, tell me if I'm off") — not interrogative. -->

Skip the entire interview when `QUICK_MODE == 1` OR `NON_INTERACTIVE == 1`. Jump to Step 6 with `phase=unsorted`, body = raw description.

Otherwise: here's what I think about this idea based on the description + project context — tell me where I'm off. I'll walk through ≤5 questions; for each, I'll propose an answer and a one-line rationale, and you accept, tweak, or reject. Type `accept-all` whenever you've heard enough and I'll finalize with my best guesses for the rest.

Each question is individually skippable (type `skip` or empty) UNLESS marked required. If you skip a run of ≥3 in a row I'll stop asking (respect interview fatigue — Risk #1 in the PRD).

### §5.0 Per-question rendering contract (coach-driven-capture FR-004)

Every question in §5.1–§5.7 MUST be rendered in this exact shape — copy the format, don't paraphrase:

```
Q<N>/<total>: <question text>
  Proposed: <best-guess answer derived from $DESC + CTX_JSON>
  Why:      <one-line rationale citing the specific signal>
  [accept / tweak <value> / reject / skip / accept-all]
  >
```

Rules (load-bearing):

- **`Proposed:` MUST be derived from evidence** — the initial description and the `CTX_JSON` snapshot. Never invent. If no evidence supports a guess, render:
  ```
  Proposed: —
  Why:      no evidence in repo
  ```
  This is the explicit edge-case placeholder (see spec Edge Cases: "Roadmap item with unknown/ambiguous fields"). Do not hallucinate — the user will tweak.
- **`Why:` is one line.** Cite one concrete signal (e.g., "addresses open critique `2026-04-12-item-two`" or "similar to shipped PRD `2026-04-10-alpha`") — not prose.
- **Affordance is always presented verbatim** (`[accept / tweak <value> / reject / skip / accept-all]`) so users memorize it across sessions.
- **First-person framing is collaborative.** Use "I think", "Here's what I see", "Tell me if I'm off". Never "You must", "Required", "Please provide". This is the FR-007 / PRD FR-006 tone guarantee — manual-review gate during PRD audit.

### §5.0a Response parser (coach-driven-capture FR-005)

Parse the user's input for each question in this priority order:

1. `accept-all` → record the `Proposed:` value for THIS question, then for EVERY remaining question substitute its `Proposed:` value, skip to Step 6. Required-field validation (e.g., `proof_path` for `kind:critique`) still runs — if `Proposed:` for a required field is empty, re-prompt for that one question, then resume finalization.
2. `tweak <value> then accept-all` (or `tweak: <value>, accept-all`) → record `<value>` for THIS question, then apply accept-all semantics to the rest.
3. `tweak <value>` (or `tweak: <value>`) → record `<value>` for THIS question, move to the next question.
4. `accept` → record the `Proposed:` value, move to the next question.
5. `reject` → drop the `Proposed:` value, re-ask the question once with an empty suggestion (`Proposed: —`); a second reject records empty and moves on.
6. `skip` or empty → move on without recording anything (counts toward the 3-in-a-row fatigue threshold).

Any other response → treat as free-text answer (equivalent to `tweak <that-text>`). This keeps the interview ergonomic for users who don't want to type the affordance keywords.

Ask the question bank for the confirmed `KIND`.

### §6.1 `kind: feature`

1. What's the hardest part?
2. What are you assuming will be true?
3. What does this depend on (other items, infra, decisions)?
4. Is there a cheaper version that delivers 80% of the value?
5. What breaks if a dependency isn't ready when you start?

### §6.2 `kind: critique` — REQUIRED `proof_path`

1. **REQUIRED** — `proof_path`: What would need to ship or be measured to make this critique false? Re-prompt until non-empty OR the user explicitly says `--no-proof-path` (record warning in body, continue).
2. Who would make this claim?
3. What items already address this critique (so we can link `addresses:`)?
4. Is this a hard (architectural) or a soft (UX) critique?
5. What's the deadline — when must we have started disproving this?

### §6.3 `kind: research`

1. What's the decision this unblocks?
2. What's the time-box (how long before deciding "concluded")?
3. What does "done" look like — a doc, a prototype, a number?
4. Who's the audience for the conclusion?
5. What's the cheapest way to get a directional answer first?

### §6.4 `kind: goal`

1. How will you measure this — what's the target metric and number?
2. Which features should ladder up to this goal?
3. What's the timeframe?
4. Who benefits if this is met?
5. What would convince you the goal is wrong and should be dropped?

### §6.5 `kind: constraint` / `kind: non-goal`

1. **REQUIRED** — Why this constraint / non-goal? (Recorded as rationale in body.)
2. What would need to change for this to be revisited?
3. What items would violate this if we built them naively?

### §6.6 `kind: milestone`

1. What signals "reached"?
2. Which items must complete before this milestone fires?
3. What's the natural date if all goes well?

### §6.7 Sizing questions — ALL kinds except constraint / non-goal / milestone (FR-017 / PRD FR-017)

Ask exactly these three. Do NOT ask human-time, story-points, T-shirt sizes, pomodoros, hours, days, or any other human-time proxy. The validator rejects those fields schema-side (§1.5) — asking them creates a trap for the user.

1. `blast_radius` — `isolated | feature | cross-cutting | infra` (how much surface area will change)?
2. `review_cost` — `trivial | moderate | careful | expert` (how much scrutiny does this PR need)?
3. `context_cost` — rough free-text estimate (e.g., "1 session", "3 sessions", "one-shot"). Free-form — no units enforced beyond "don't use hours/days".

### §6.8 Research-block question (FR-015 / FR-016 of research-first-completion)

<!-- T010 / FR-015 / FR-016 / NFR-006 / Decision 9 / contracts §8 of
     research-first-completion. Conditional question stanza — fires ONLY
     when classify-description.sh emitted a `research_inference` key in
     its output. Absent → silently skipped (false-negative recovery is
     structural per NFR-006). -->

After the sizing questions, conditionally render the research-block proposal
when the classifier inferred one. **Skip silently when `research_inference`
is absent from `CLASSIFICATION_JSON`** — false-negative recovery is
structural absence per NFR-006.

```bash
HAS_RESEARCH_INFERENCE=$(printf '%s' "$CLASSIFICATION_JSON" | jq -r 'has("research_inference")' 2>/dev/null)
if [ "$HAS_RESEARCH_INFERENCE" = "true" ]; then
  RB_PROPOSAL=$(printf '%s' "$CLASSIFICATION_JSON" | jq -c .research_inference)
  RB_RATIONALE=$(printf '%s' "$RB_PROPOSAL" | jq -r .rationale)
  # Render the proposed YAML block (compact, multi-line readable).
  RB_YAML=$(printf '%s' "$RB_PROPOSAL" | jq -r '
    "needs_research: true\nempirical_quality:" +
    (
      [.proposed_axes[] | "\n  - metric: \(.metric)\n    direction: \(.direction)\n    priority: \(.priority)"]
      | join("")
    )
  ')
fi
```

**Question shape** (per §5.0 template + FR-016 rationale extension):

```
Q: Does this need research?
   Proposed: <RB_YAML — needs_research:true + empirical_quality block>
   Why: <RB_RATIONALE — matched signal word: <word>
        [for output_quality axes, FR-016 verbatim warning on its own line]>
   [accept / tweak <value> / reject / skip / accept-all]
   > _
```

**Response handling** (per §5.0a parser):
- `accept` → record `needs_research: true` + the proposed `empirical_quality:` block on the item; in §6 frontmatter emission, write the research-block keys verbatim after the existing schema keys.
- `tweak <value>` → maintainer edits any field (axes, direction, priority, fixture_corpus, etc.); re-prompt with the edited proposal.
- `reject` → write NO research-block keys (NFR-006 structural absence — NOT `needs_research: false`, NOT empty `empirical_quality: []`).
- `skip` → equivalent to `reject` for this question.
- `accept-all` → accept this proposal AND auto-accept all subsequent questions in the interview.

**False-positive recovery** (NFR-006): rejection results in the captured
artifact having NO research-block frontmatter (structural absence, not
`needs_research: false` and not empty values). The §6 frontmatter writer
inspects the recorded answer state and emits research-block keys only when
`accept` was the recorded response.

### Phase-assignment question (FR-016 / PRD FR-016)

Ask once (or once per batch for multi-item):

> Which phase — `<list of phases from PHASES_DIR with their status>`? Default: `unsorted`.

Show the phases via:

```bash
ls "$PHASES_DIR"/*.md 2>/dev/null | while read -r f; do
  s=$(awk '/^status:[[:space:]]/ { sub(/^status:[[:space:]]*/,""); print; exit }' "$f")
  printf '  %s (status: %s)\n' "$(basename "$f" .md)" "$s"
done
```

---

## Step 6: Write item file (FR-007, FR-030, FR-037 / PRD FR-007, FR-030)

<!-- FR-007 / PRD FR-007: item frontmatter required keys.
     FR-030 / PRD FR-030: dispatch shelf:shelf-write-roadmap-note for Obsidian mirror.
     FR-037 / spec FR-037: re-running with identical inputs → byte-identical file. -->

Compute the id, slug, and path:

```bash
TODAY="$(date -u +%Y-%m-%d)"
# Slug: lowercase + alnum+dash, max 40 chars
SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40 | sed -E 's/-+$//')"
[ -z "$SLUG" ] && SLUG="item"
ITEM_ID="${TODAY}-${SLUG}"
ITEM_PATH="$ITEMS_DIR/${ITEM_ID}.md"

# Uniqueness: append counter if collision
i=2
while [ -f "$ITEM_PATH" ]; do
  ITEM_ID="${TODAY}-${SLUG}-${i}"
  ITEM_PATH="$ITEMS_DIR/${ITEM_ID}.md"
  i=$((i + 1))
done
```

Compose the frontmatter + body. Required fields (FR-007) — DO NOT add any forbidden §1.5 keys (human_time, t_shirt_size, effort_days, etc.):

```
---
id: <ITEM_ID>
title: "<title>"
kind: <KIND>
date: <TODAY>
status: open             # kind-specific default, see §1.4 of contracts
phase: <PHASE_NAME>
state: planned
blast_radius: <answer>
review_cost: <answer>
context_cost: <answer>
# depends_on: [ ... ]    # optional
# addresses: [ ... ]     # optional
# implementation_hints: | ...    # optional
# proof_path: | ...      # REQUIRED for kind: critique (FR-011)
---

# <title>

<body from interview answers — structured markdown headings per kind>
```

### Validate BEFORE write

```bash
TMP="$(mktemp "${ITEM_PATH}.XXXXXX.tmp")"
# … write composed content to $TMP …
V_JSON="$(bash "$H_VALIDATE_ITEM" "$TMP")"
V_OK="$(echo "$V_JSON" | jq -r '.ok')"
if [ "$V_OK" != "true" ]; then
  echo "validation failed — refusing to write item:"
  echo "$V_JSON" | jq -r '.errors[]'
  rm -f "$TMP"
  exit 1
fi
mv "$TMP" "$ITEM_PATH"
```

### Dispatch Obsidian mirror (FR-030 / PRD FR-030)

If `SHELF_MIRROR_ENABLED=1`, point the shelf workflow at the file we just wrote. The simplest handoff is the `ROADMAP_INPUT_FILE` env var — `plugin-shelf/scripts/parse-roadmap-input.sh` checks it first (direct path), then `ROADMAP_INPUT_BLOCK`, then stdin:

```bash
export ROADMAP_INPUT_FILE="$ITEM_PATH"     # workflow will read this verbatim
```

Then invoke `shelf:shelf-write-roadmap-note` — this workflow reads `.shelf-config` (no vault discovery per FR-004) and writes one Obsidian note at `<base_path>/<slug>/roadmap/items/<basename>`. The result JSON lands at `.wheel/outputs/shelf-write-roadmap-note-result.json` with `{ source_file, obsidian_path, action, path_source, errors }`.

If the Obsidian mirror fails (action: "failed" or non-empty errors), log the diagnostic and continue — `.kiln/` writes are the source of truth and the capture is considered successful. FR-040 covers the `.shelf-config`-missing case separately (warning at Step 0; mirror-skipped flag suppresses this step).

---

## Step 7: Update phase file (FR-006 / PRD FR-006)

<!-- FR-006 / PRD FR-006: phase body carries auto-maintained item list. -->

```bash
bash "$H_UPDATE_PHASE" "$PHASE_NAME" register "$ITEM_ID"
```

This rewrites the `## Items` section of the phase file from `list-items.sh --phase <name>` output — do NOT hand-edit that section.

Also dispatch the phase file to shelf-write-roadmap-note (with `source_file = $PHASES_DIR/$PHASE_NAME.md`) so Obsidian stays in sync.

---

## Step 8: Follow-up loop (FR-018c, FR-039 / PRD FR-018c)

<!-- FR-018c / PRD FR-018c: after each item is written, ask "anything else on your mind?" and loop back through Step 2 routing.
     FR-039 / spec FR-039: graceful exit on explicit "no", empty input, or non-interactive session — no infinite loop path. -->

Skip the follow-up loop entirely when `QUICK_MODE == 1` OR `NON_INTERACTIVE == 1`.

Otherwise:

```
Anything else on your mind? (yes / no / or type the next idea)
```

- `yes` → prompt: "What's the next idea?"; feed the answer back into Step 2 routing.
- `no` / empty / any negative (`n`, `nope`, `exit`) → break out and print the session summary.
- Anything else → treat as the next description; feed directly into Step 2.

Track per-surface counts across the session:

```
session_captures_roadmap=0
session_captures_issue=0
session_captures_feedback=0
```

Increment on each completed capture. When the loop exits, print:

```
captured <N> roadmap items, <M> issues, <K> feedback this session.
  - roadmap: .kiln/roadmap/items/<path>, ...
  - issue:   .kiln/issues/<path>, ...       (if any)
  - feedback: .kiln/feedback/<path>, ...    (if any)
```

---

## §V-A: Vision simple-params CLI (`--vision --add-* / --update-*` — vision-tooling FR-001/FR-002/FR-005/FR-014)

<!-- vision-tooling Theme A. Cheap, deterministic, ≤3-second updates that
     SKIP the heavyweight coached interview entirely (FR-001 last sentence;
     FR-014 invariant). Atomic temp+mv writer with .kiln/.vision.lock; flag
     conflicts refused before any I/O. NFR-005 back-compat: when no simple-
     params flag is present this section is bypassed and §V handles the
     coached interview byte-identically to the pre-PRD path. -->

This section is reached ONLY when `--vision` is invoked together with at
least one supported simple-params flag from the `vision-section-flag-map.sh`
table (FR-021): `--add-constraint`, `--add-non-goal`, `--add-signal`,
`--update-what`, `--update-not`, `--update-signals`, `--update-constraints`.

```bash
# §V-A.1 Validate. NO file I/O — refuses unknown / empty / mutually
# exclusive flags before touching .kiln/vision.md (FR-005, SC-002).
VALIDATOR_OUT=$(bash plugin-kiln/scripts/roadmap/vision-flag-validator.sh -- "$@")
VALIDATOR_RC=$?
if [ "$VALIDATOR_RC" -ne 0 ]; then
  # Validator already wrote `vision: <reason>` to stderr in the kiln-roadmap
  # warning shape. Exit non-zero immediately; do not fall through to §V.
  exit "$VALIDATOR_RC"
fi

# Validator emits "<flag>\t<text>" on stdout when a single supported flag is
# present. Empty stdout means "no simple-params flag, fall through" — this
# branch should not have been reached, but defensively re-route to §V.
if [ -z "$VALIDATOR_OUT" ]; then
  : "fall through to §V coached interview"
else
  FLAG=$(printf '%s' "$VALIDATOR_OUT" | cut -f1)
  TEXT=$(printf '%s' "$VALIDATOR_OUT" | cut -f2-)

  # §V-A.2 Atomic temp+mv write with last_updated: bump (FR-001/FR-002/FR-003).
  bash plugin-kiln/scripts/roadmap/vision-write-section.sh "$FLAG" "$TEXT"
  WRITE_RC=$?
  if [ "$WRITE_RC" -ne 0 ]; then
    # Vision file is byte-identical to pre-invocation on any non-zero exit
    # (FR-003). Surface the writer's exit code verbatim.
    exit "$WRITE_RC"
  fi

  # §V-A.3 Shelf mirror dispatch — fire-and-warn (FR-004). Never fails out
  # of kiln-roadmap; missing .shelf-config emits the canonical warning shape
  # and continues.
  bash plugin-kiln/scripts/roadmap/vision-shelf-dispatch.sh

  # §V-A.4 EXIT — MUST NOT invoke the coached interview (FR-001 last
  # sentence) AND MUST NOT invoke the Theme C forward-pass (FR-014 / SC-010).
  exit 0
fi
```

The dispatch surface is intentionally thin — every mutation goes through
`vision-write-section.sh` (atomic temp+mv, frontmatter bump, FR-021 section
table) and every shelf mirror through `vision-shelf-dispatch.sh`
(warn-and-continue on missing `.shelf-config`). Adding a new flag means
extending the table in `vision-section-flag-map.sh`; no edits here are
required.

---

## §V: Vision update (`--vision` — FR-019 / PRD FR-019, coach-driven-capture FR-008..FR-012)

<!-- FR-019 / PRD FR-019: short vision-update interview; patch_file on Obsidian (NOT update_file) per FR-031.
     coach-driven-capture FR-008: first-run draft from project-context evidence.
     coach-driven-capture FR-009: re-run → per-section diffs (Clarification #2: grouped by section, not flat).
     coach-driven-capture FR-010: last_updated bumped on accepted edit, NOT bumped on reject-all.
     coach-driven-capture FR-011: fully-empty snapshot → one-line banner + blank-slate fallback.
     coach-driven-capture FR-012: partial snapshot → partial draft + per-section evidence annotations (no banner). -->

Refuse to run `--vision` in `NON_INTERACTIVE` mode — print a clear error and exit non-zero. Vision updates require human judgement.

### §V.1: Load the project-context snapshot (coach-driven-capture FR-008)

Consume the shared reader from `specs/coach-driven-capture-ergonomics/contracts/interfaces.md`:

```bash
# FR-008: consume the ProjectContextSnapshot. Falls back gracefully to an empty
# snapshot object if the reader isn't installed yet (pre-Phase-1 consumer repos).
READER="plugin-kiln/scripts/context/read-project-context.sh"
if [ -x "$READER" ] || [ -f "$READER" ]; then
  CTX_JSON=$(bash "$READER" 2>/dev/null) || CTX_JSON=""
fi
if [ -z "${CTX_JSON:-}" ]; then
  CTX_JSON='{"schema_version":"1","prds":[],"roadmap_items":[],"roadmap_phases":[],"vision":null,"claude_md":null,"readme":null,"plugins":[]}'
  echo "warn: project-context reader unavailable; --vision will treat repo as empty" >&2
fi

# FR-011 classification: fully empty vs partial vs populated
EMPTY_SNAPSHOT=$(echo "$CTX_JSON" | jq -r '
  if (.prds | length == 0)
    and (.roadmap_items | length == 0)
    and (.readme == null)
    and (.claude_md == null)
  then "yes" else "no" end
')

HAS_VISION=$(echo "$CTX_JSON" | jq -r 'if .vision == null or ((.vision.body // "") | length) == 0 then "no" else "yes" end')

# Partial = not empty, but at least one evidence source missing.
PARTIAL_SNAPSHOT=$(echo "$CTX_JSON" | jq -r '
  if (.prds | length == 0) or (.roadmap_items | length == 0) or (.readme == null) or (.claude_md == null)
  then (if (.prds | length > 0) or (.roadmap_items | length > 0) or (.readme != null) or (.claude_md != null) then "yes" else "no" end)
  else "no" end
')
```

### §V.2: Fully-empty fallback (coach-driven-capture FR-011)

If `EMPTY_SNAPSHOT == "yes"`, emit the one-line banner verbatim and drop through to the legacy blank-slate interview:

```
ℹ  blank-slate fallback: the project-context snapshot is empty — no PRDs, items, README, or CLAUDE.md to draw from. Running the legacy open-ended interview. (FR-011)
```

Then ask the three legacy questions, compose the file, and jump to §V.5 (write + mirror). Do NOT draft from evidence — there is none.

- "What's changed about the vision?" (or "What are we building?" on truly-first-run)
- "What's still true?" (or "What's out-of-scope?")
- "What constraints do we need to live within?"

### §V.3: First-run draft from evidence (coach-driven-capture FR-008)

If `HAS_VISION == "no"` AND `EMPTY_SNAPSHOT == "no"`, draft all four vision sections from `CTX_JSON`. This is the FR-008 path.

For each of the four canonical sections (matching `plugin-kiln/templates/vision-template.md`):

1. **What we are building** — derive bullets from PRD titles and their frontmatter `theme:` values. Cite evidence per bullet.
2. **What it is not** — derive from `kind: non-goal` roadmap items if any exist; otherwise leave a `(no explicit non-goals in repo yet)` annotation.
3. **How we'll know we're winning** — derive from PRD success criteria (scan for `Success Criteria` section body) and `kind: goal` roadmap items.
4. **Guiding constraints** — derive from `kind: constraint` roadmap items and any `load-bearing` phrases in `CLAUDE.md` (if `.claude_md.body` is non-null).

Every drafted bullet MUST carry an inline evidence citation using one of these shapes — pick the one that matches the source:

- `_derived from: docs/features/<slug>/PRD.md_`
- `_from roadmap item <id>_`
- `_from README.md_`
- `_from CLAUDE.md §<section>_`

Render the full draft to the user with the banner:

```
Here's a first-draft vision drawn from your repo. Each bullet cites its evidence. Accept / edit / reject the whole draft, or say `step-through` to go section-by-section.
```

Collect user response:
- `accept` / `accept-all` — write the file to `$VISION_FILE` with `last_updated:` stamped to today, proceed to §V.5.
- `reject` / `reject-all` — discard the draft, fall back to the three legacy questions (§V.2 body).
- `step-through` — render one section at a time with `[accept-section / reject-section / edit]`.
- Freeform text (a pasted alternative) — treat as the user's own body; stamp frontmatter and write.

### §V.4: Re-run per-section diff (coach-driven-capture FR-009, FR-010, Clarification #2)

If `HAS_VISION == "yes"` AND `EMPTY_SNAPSHOT == "no"`:

1. Read the current vision body from `.vision.body` in `CTX_JSON` (or re-read `$VISION_FILE`).
2. For each of the four sections, compute the delta against repo state:
   - Any PRD shipped since `last_updated:` whose theme isn't yet cited in "What we are building"?
   - Any new `kind: non-goal` item missing from "What it is not"?
   - Any new `kind: goal` or shipped `kind: feature` whose success metric isn't cited in "How we'll know"?
   - Any new `kind: constraint` item missing from "Guiding constraints"?
3. **Group the proposed edits BY SECTION** (Clarification #2 — per-section grouping, not flat line-by-line). For each section with ≥1 proposed edit, render one prompt block:

   ```
   ## <section name>
   Current:   <current line / bullet>
   Proposed:  <proposed line / bullet>
   Evidence:  <citation>

   [accept-section / reject-section / step-through / global accept-all / global reject-all]
   ```

4. Accumulate accepted edits into `ACCEPTED_EDITS` (a working list).
5. If `global reject-all` OR the user declines every section → print `no drift detected (FR-010 negative path)` and EXIT WITHOUT modifying `$VISION_FILE` or bumping `last_updated:`. This is the no-drift edge case.
6. If `ACCEPTED_EDITS` is non-empty → rewrite the affected sections in-place, atomically, AND bump `last_updated:` to today's ISO date (FR-010 positive path):

```bash
TODAY=$(date -u +%Y-%m-%d)
TMP="$(mktemp "${VISION_FILE}.XXXXXX.tmp")"
# … compose updated body into $TMP with bumped frontmatter …
# Idempotent last_updated: bump (only rewrites the one line)
sed -i.bak -E "s|^last_updated:.*|last_updated: ${TODAY}|" "$TMP" && rm -f "${TMP}.bak"
mv "$TMP" "$VISION_FILE"
```

### §V.5: Partial snapshot — partial draft with evidence annotations (coach-driven-capture FR-012, Clarification #4)

This path activates when `EMPTY_SNAPSHOT == "no"` AND `PARTIAL_SNAPSHOT == "yes"` AND `HAS_VISION == "no"`.

Draft the sections the available evidence supports, and for each section explicitly annotate which sources were (and were not) available. Example:

```markdown
## What we are building

- <bullet drafted from PRD> _derived from: docs/features/<slug>/PRD.md_
- <bullet drafted from PRD> _derived from: docs/features/<slug2>/PRD.md_

_Sources used: docs/features/*, README.md. (no roadmap items yet — some bullets will be approximate.)_
```

**Explicit rule (Clarification #4)**: the partial-snapshot path MUST NOT emit the blank-slate banner. The banner in §V.2 is reserved for fully-empty snapshots only. The partial path's signal is the per-section `_Sources used: …_` annotation.

Then proceed through the same accept / reject / step-through affordance as §V.3 and write via §V.6.

### §V.6: Write + mirror

After any path that produces a new or updated vision body:

1. Write to `$VISION_FILE` atomically (temp-write + mv).
2. Ensure `last_updated:` matches today's ISO date — or, if this was the §V.4 no-drift exit, leave the original date alone.
3. Dispatch `shelf:shelf-write-roadmap-note` with `source_file = .kiln/vision.md`. The workflow picks `patch_file` on update (FR-031 / PRD FR-031) to preserve frontmatter.

### Rules (FR-008..FR-012 test harness relies on these)

- The only line that may contain the string `blank-slate` is the §V.2 banner. The §V.5 partial-snapshot path MUST NOT include that string anywhere in the drafted body.
- Re-running `--vision` on unchanged repo state MUST print `no drift detected` and MUST NOT modify `$VISION_FILE`.
- Every drafted bullet in §V.3 and §V.5 MUST carry an inline evidence citation — unannotated bullets are a regression.

---

## §P: Phase management (`--phase` — FR-020 / PRD FR-020)

<!-- FR-020 / PRD FR-020: only one phase may be in-progress at a time.
     FR-021 / PRD FR-021: phase start --cascade-items → flip planned items to in-phase. -->

Refuse `--phase` in `NON_INTERACTIVE` mode unless invoked by CI with an explicit `--yes`.

Sub-commands:

- `--phase start <name>`:
  ```bash
  bash "$H_UPDATE_PHASE" "$name" in-progress --cascade-items
  ```
  Exit code 5 from the helper = another phase is in-progress; print the helper's JSON error verbatim (names the conflicting phase) and exit non-zero.

- `--phase complete <name>`:
  ```bash
  bash "$H_UPDATE_PHASE" "$name" complete
  ```
  Items under the completed phase are NOT auto-deleted (FR-012 / PRD FR-012) — status stays open, only the phase transitions.

- `--phase create <name> --order <N>`:
  Creates `$PHASES_DIR/$name.md` from `$T_PHASE` with `order: N`, `status: planned`. Then dispatch shelf mirror.

After any `--phase` action that mutates the file, dispatch `shelf:shelf-write-roadmap-note` for the phase file.

---

## §C: Consistency check (`--check` — FR-022 / PRD FR-022)

<!-- FR-022 / PRD FR-022: report items whose state is inconsistent with phase / spec / PR reality. -->
<!-- FR-005 (escalation-audit): Check 5 adds a merged-PR cross-reference for distilled/specced items with populated `prd:`.
     Spec: specs/escalation-audit/spec.md US2. Contract: specs/escalation-audit/contracts/interfaces.md §A.3. -->

Walk every item via `list-items.sh` and cross-reference:

```bash
bash "$H_LIST_ITEMS" | while IFS= read -r item; do
  FM="$(bash "$H_PARSE_ITEM" "$item")"
  id="$(echo "$FM" | jq -r '.id')"
  state="$(echo "$FM" | jq -r '.state')"
  phase="$(echo "$FM" | jq -r '.phase')"
  spec="$(echo "$FM" | jq -r '.spec // empty')"
  prd="$(echo "$FM" | jq -r '.prd // empty')"
  # Check 1: state:in-phase but its phase is not in-progress → inconsistent
  # Check 2: state:specced but spec: not set or spec.md missing → inconsistent
  # Check 3: state:distilled but prd: not set or PRD.md missing → inconsistent
  # Check 4: addresses: references a missing critique id → dangling reference

  # Check 5: Merged-PR drift (FR-005, escalation-audit) — items still distilled/specced
  # whose PRD has shipped via a merged build PR. Catches pre-existing drift the
  # auto-flip (build-prd Step 4b.5) does NOT cover.
  #
  # NFR-004 backward compat: only fires when state ∈ {distilled, specced} AND `prd:` is
  # populated AND the file exists. Items without `prd:` are untouched (Checks 1–4 still emit).
  if { [ "$state" = "distilled" ] || [ "$state" = "specced" ]; } && [ -n "$prd" ] && [ -f "$prd" ]; then
    # Resolve the PRD's expected build branch — prefer ref-walk (R-2 mitigation).
    BRANCH=""
    RESOLUTION="ref-walk"
    MERGE_SHA="$(git log --diff-filter=A --pretty=format:%H -- "$prd" 2>/dev/null | tail -n1)"
    if [ -n "$MERGE_SHA" ]; then
      BRANCH="$(git for-each-ref --points-at "$MERGE_SHA" --format='%(refname:short)' 2>/dev/null \
        | grep -E '^build/' | head -n1)"
    fi
    if [ -z "$BRANCH" ]; then
      # Fallback heuristic: build/<theme>-<YYYYMMDD> derived from PRD path.
      RESOLUTION="heuristic"
      THEME="$(echo "$prd" | sed -E 's|^docs/features/[0-9]{4}-[0-9]{2}-[0-9]{2}-([^/]+)/PRD\.md$|\1|')"
      DATE_PART="$(echo "$prd" | sed -E 's|^docs/features/([0-9]{4})-([0-9]{2})-([0-9]{2})-.*|\1\2\3|')"
      BRANCH="build/${THEME}-${DATE_PART}"
    fi

    PR_NUM="$(gh pr list --state merged --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)"
    if [ -n "$PR_NUM" ]; then
      # FR-005 — drift row: one block per flagged item (stdout). Format pinned by §A.3.
      echo "[drift] ${id} state=${state} prd=${prd} branch=${BRANCH} pr=#${PR_NUM} resolution=${RESOLUTION}"
      echo "  fix: bash plugin-kiln/scripts/roadmap/update-item-state.sh ${item} shipped --status shipped"
      # R-2 documentation requirement: heuristic-resolved findings get a Notes-section row.
      if [ "$RESOLUTION" = "heuristic" ]; then
        printf '%s\n' "note: ${id} resolved via heuristic build-branch fallback (R-2)." \
          >> "${NOTES_FILE:-/dev/stderr}"
      fi
    fi
  fi
done
```

**Check 5 output shape** (one block per flagged item — pinned by §A.3):

```
[drift] <item-id> state=<distilled|specced> prd=<path> branch=<branch> pr=#<N> resolution=<ref-walk|heuristic>
  fix: bash plugin-kiln/scripts/roadmap/update-item-state.sh <item-path> shipped --status shipped
```

**Notes section addendum** (FR-005, R-2): every drift entry whose `resolution=heuristic` MUST also append the line `note: <id> resolved via heuristic build-branch fallback (R-2).` to the report's `## Notes` section. The `NOTES_FILE` env var (default `/dev/stderr`) controls the destination — production sets it to the real notes-file path inside the report.

**NFR-004 invariant**: items WITHOUT a populated `prd:` field skip Check 5 entirely. The pre-existing Checks 1–4 emit unchanged, byte-identical to behavior before FR-005 landed.

Print a tidy report with actionable suggestions per finding. Exit 0 if consistent, non-zero if any inconsistency is found (so CI can gate on it).

---

## §C-fix: Confirm-never-silent drift fixer (`--check --fix` — FR-010, FR-011, NFR-004)

<!-- Spec: specs/merge-pr-and-sc-grep-guidance/spec.md FR-010, FR-011, NFR-004.
     Contract: specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md §C. -->

Activated ONLY when both `--check` AND `--fix` are passed. Without `--fix`, `--check` behavior is byte-identical to the pre-FR-010 version (NFR-004 backward-compat).

Catches drift that escapes `/kiln:kiln-merge-pr` — items merged via the GitHub web UI or `gh pr merge` directly, before this fixer existed. Same shared helper (`auto-flip-on-merge.sh`) every other call site uses, so the post-fix frontmatter is byte-identical to what auto-flip-on-merge would have produced at merge time.

```bash
# §C-fix runs AFTER Check 5's report assembly. The report's [drift] lines are the
# input to this stage — captured into DRIFT_LINES below.
if [ "${FIX_MODE:-false}" != "true" ]; then
  # NFR-004 backward-compat: --check alone never enters this block. Exit unchanged.
  return 0 2>/dev/null || true
fi

# Parse the [drift] rows from the Check 5 report (one row per drifted item).
# Each row has the canonical form pinned in §A.3:
#   [drift] <item-id> state=<state> prd=<path> branch=<branch> pr=#<N> resolution=<ref-walk|heuristic>
DRIFT_COUNT="$(printf '%s\n' "$DRIFT_LINES" | grep -c '^\[drift\]' || true)"

if [ "$DRIFT_COUNT" -eq 0 ]; then
  echo "No drift detected."
  return 0 2>/dev/null || exit 0
fi

# Confirm-never-silent prompt (NFR-004): empty input is treated as `skip`, never auto-fix.
printf '\nDrift detected: %s items. Choose action: [fix all / pick / skip] ' "$DRIFT_COUNT"
read -r CHOICE
case "${CHOICE:-skip}" in
  "fix all"|"fix-all"|"all"|"a") ACTION="fix-all" ;;
  "pick"|"p")                    ACTION="pick"    ;;
  "skip"|"s"|"")                 ACTION="skip"    ;;
  *)                             ACTION="skip"    ;;  # unknown → skip (NFR-004)
esac

if [ "$ACTION" = "skip" ]; then
  echo "fix=skipped items=0 patched=0 already_shipped=0 ambiguous=0"
  return 0 2>/dev/null || exit 0
fi

PATCHED=0
ALREADY_SHIPPED=0
AMBIGUOUS=0
ACCEPTED=0

# Iterate the drift rows; per-row PR resolution + helper invocation.
H_AUTO_FLIP="plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh"

while IFS= read -r ROW; do
  case "$ROW" in
    \[drift\]\ *) ;;
    *) continue ;;
  esac

  # Extract id, prd, branch from the row.
  DRIFT_ID="$(echo "$ROW" | awk '{print $2}')"
  DRIFT_PRD="$(echo "$ROW" | sed -E 's/.* prd=([^ ]+) .*/\1/')"
  DRIFT_BRANCH="$(echo "$ROW" | sed -E 's/.* branch=([^ ]+) .*/\1/')"

  # FR-011 — re-resolve PR by branch via gh; require unambiguous match.
  PR_MATCHES_JSON="$(gh pr list --state merged --head "$DRIFT_BRANCH" --json number 2>/dev/null || echo '[]')"
  PR_COUNT="$(echo "$PR_MATCHES_JSON" | jq 'length // 0')"

  if [ "$PR_COUNT" != "1" ]; then
    # FR-011 — zero or multiple matches: surface ambiguity, skip THIS item, never guess.
    AMBIGUOUS=$((AMBIGUOUS + 1))
    echo "[ambiguous] ${DRIFT_ID} branch=${DRIFT_BRANCH} pr-matches=${PR_COUNT} (skipped — implementer must NOT guess per FR-011)"
    continue
  fi
  PR_NUM="$(echo "$PR_MATCHES_JSON" | jq -r '.[0].number')"

  # `pick` mode: per-item confirm.
  if [ "$ACTION" = "pick" ]; then
    printf 'Fix %s (PR #%s)? [accept / skip] ' "$DRIFT_ID" "$PR_NUM"
    read -r PER_ITEM
    case "${PER_ITEM:-skip}" in
      "accept"|"a"|"y"|"yes") ;;
      *) continue ;;
    esac
  fi

  ACCEPTED=$((ACCEPTED + 1))
  # Per-entry helper output is emitted by the helper itself (Module A.2 line).
  HELPER_OUT="$(bash "$H_AUTO_FLIP" "$PR_NUM" "$DRIFT_PRD" 2>&1)"
  echo "$HELPER_OUT"

  # Aggregate counters from the helper's diagnostic line.
  case "$HELPER_OUT" in
    *"already_shipped=0"*"patched=1"*) PATCHED=$((PATCHED + 1)) ;;
    *"already_shipped=1"*"patched=0"*) ALREADY_SHIPPED=$((ALREADY_SHIPPED + 1)) ;;
  esac
done <<< "$DRIFT_LINES"

# §C.3 — final summary line (one line, one summary).
echo "fix=success items=${ACCEPTED} patched=${PATCHED} already_shipped=${ALREADY_SHIPPED} ambiguous=${AMBIGUOUS}"
```

**Why same-helper matters (FR-010)**: drift caught here flips through the SAME `auto-flip-on-merge.sh` helper that Step 4b.5 and `/kiln:kiln-merge-pr` call — three call sites, one implementation, byte-identical output.

**FR-011 ambiguity rule**: if `gh pr list --state merged --head <branch>` returns zero or multiple PRs, the entry is surfaced as `[ambiguous]` and skipped. The skill MUST NOT guess via heuristics for the actual flip — the maintainer resolves ambiguity manually. (Check 5's heuristic resolution is allowed for *reporting*; auto-fixing requires unambiguous evidence.)

**NFR-004 confirm-never-silent**: empty input → `skip`. Unknown input → `skip`. Auto-fix only on explicit `fix all` or per-item `accept`.

---

## §R: Reclassify (`--reclassify` — FR-028 follow-up)

<!-- FR-028 / PRD FR-028: after migration, user runs --reclassify to walk unsorted items. -->

List every item with `phase: unsorted` via `list-items.sh --phase unsorted`. For each:

1. Show the current file (title + body).
2. Run the adversarial interview scoped to kind-confirmation + phase-assignment + sizing.
3. Overwrite the file's frontmatter atomically via temp-write + mv.
4. Dispatch `shelf:shelf-write-roadmap-note` for the updated item.
5. Update the source phase file (remove from `unsorted` registration) AND the target phase file (add registration).

Offer an `--only-next N` cap so long legacy migrations can be processed in small batches.

---

## §M: Promote source (`--promote <source>` — workflow-governance FR-006)

<!-- FR-006 of workflow-governance / spec Clarifications 3 + 5:
       - Resolve the argument to a source path (literal path or GitHub issue
         number via `gh issue view <N>` + local match on
         `github_issue: <N>`).
       - Refuse sources with `status: promoted` (idempotency — exit 5).
       - If source body ≥ 200 chars, run the coached interview with
         per-question pre-fill drawn from the source body; user may type
         `accept-all` at any point.
       - If source body < 200 chars, run the standard adversarial interview
         without pre-fill.
       - Call `promote-source.sh` (contract §2). Body bytes MUST be
         byte-preserved (NFR-003).
       - After success, dispatch `shelf:shelf-write-roadmap-note` for the
         new item file so Obsidian mirrors the roadmap entry. -->

This section activates when the user invokes `/kiln:kiln-roadmap --promote <source>`. It reuses most of the capture pipeline (§1b context load, §5 interview, §7 phase update, §8 follow-up loop) but short-circuits Step 6 into `promote-source.sh` rather than the normal item write path, and it drives the source-file back-reference as a single atomic operation.

### §M.1 — Resolve the source path

```bash
# PROMOTE_ARG is whatever followed --promote.
PROMOTE_ARG="$1"

case "$PROMOTE_ARG" in
  .kiln/issues/*.md|.kiln/feedback/*.md)
    PROMOTE_SOURCE="$PROMOTE_ARG"
    ;;
  *)
    # Try GitHub issue number resolution — look for .kiln/issues/*.md whose
    # frontmatter `github_issue:` equals the supplied number.
    if [[ "$PROMOTE_ARG" =~ ^[0-9]+$ ]]; then
      PROMOTE_SOURCE="$(grep -lE "^github_issue:[[:space:]]*${PROMOTE_ARG}\b" .kiln/issues/*.md 2>/dev/null | head -n1)"
      if [[ -z "$PROMOTE_SOURCE" ]]; then
        echo "no local file for issue $PROMOTE_ARG — run /kiln:kiln-report-issue first" >&2
        exit 1
      fi
    else
      echo "unrecognised --promote argument: $PROMOTE_ARG" >&2
      echo "usage: /kiln:kiln-roadmap --promote <.kiln/issues/...md | .kiln/feedback/...md | <issue-number>>" >&2
      exit 1
    fi
    ;;
esac

if [[ ! -f "$PROMOTE_SOURCE" ]]; then
  echo "source not found: $PROMOTE_SOURCE" >&2
  exit 1
fi
```

### §M.2 — Idempotency pre-check

Read the source's frontmatter `status:` — if already `promoted`, print the existing `roadmap_item:` back-link and exit without interviewing. This mirrors `promote-source.sh`'s exit-5 guard and avoids running the interview only to fail at the script layer.

### §M.3 — Coached vs. standard interview (Clarification 5)

Measure the body length (bytes after the closing `---`):

- **≥ 200 chars** — run the coached-interview layer from §5 with per-question pre-fill drawn from the source body. The coached suggestion block cites the source file path. User may type `accept-all` at any question to fast-forward through the remaining questions, accepting all coached suggestions. This is the same "coach-driven-capture" pattern that `/kiln:kiln-roadmap` uses for normal capture.
- **< 200 chars** — run the full adversarial interview from §5 with no pre-fill.

In both branches, the interview captures: `KIND`, `BLAST_RADIUS`, `REVIEW_COST`, `CONTEXT_COST`, `PHASE`, `SLUG`, and (optional) `TITLE`. Use today's UTC date for the item unless the source file's basename already encodes a `YYYY-MM-DD` prefix — `promote-source.sh` handles the date-prefix heuristic; the skill need only supply the `--slug`.

### §M.4 — Call `promote-source.sh` (contract §2)

```bash
PROMOTE_OUT="$(bash "$SCRIPTS/promote-source.sh" \
  --source "$PROMOTE_SOURCE" \
  --kind "$KIND" \
  --blast-radius "$BLAST_RADIUS" \
  --review-cost "$REVIEW_COST" \
  --context-cost "$CONTEXT_COST" \
  --phase "$PHASE_NAME" \
  --slug "$SLUG")"

# Exit codes (contract §2):
#   0 success
#   3 source path does not exist
#   4 source has no frontmatter
#   5 source already status: promoted (idempotency)
#   6 target item file already exists
```

On non-zero exit, surface the stderr to the user verbatim and stop — do NOT retry, do NOT silently pick a different slug.

### §M.5 — Mirror to Obsidian + register on the phase

On exit 0, extract `new_item_path` from the stdout JSON envelope:

```bash
NEW_ITEM="$(printf '%s' "$PROMOTE_OUT" | jq -r .new_item_path)"
export ROADMAP_INPUT_FILE="$NEW_ITEM"
# Invoke shelf:shelf-write-roadmap-note via the Skill tool — matches
# Step 6's Obsidian mirror handoff (FR-030).
```

Then register the new item with its phase file (matches Step 7):

```bash
bash "$H_UPDATE_PHASE" "$PHASE_NAME" register "$(basename "$NEW_ITEM" .md)"
```

### §M.6 — User-visible confirmation

Print a two-line summary:

```
Promoted .kiln/issues/2026-04-24-foo.md
      → .kiln/roadmap/items/2026-04-24-foo.md  (kind: feature, phase: workflow-governance)
```

If the skill was invoked from `/kiln:kiln-distill`'s gate hand-off (FR-005), the caller reads the stdout envelope and re-bundles the new item into the distill run. Otherwise, fall through to the Step 8 follow-up loop so the user can chain more captures.

---

## Rules (load-bearing — the tests enforce these)

- **FR-008 / PRD FR-008: AI-native sizing only.** NEVER write `human_time`, `human_days`, `effort_days`, `effort_hours`, `t_shirt_size`, `tshirt`, `size: S/M/L/XL/XXL`, `estimate_days`, `estimate_hours`, or `pomodoros` to any item file. The validator rejects these fields schema-side — writing them bounces at Step 6.
- **FR-014b / PRD FR-014b: Confirm-never-silent hand-off.** On `(b)` or `(c)` at the routing prompt, invoke the target skill via the `Skill` tool. Do NOT print "go run X instead" and exit. The test (T033) asserts skill invocation, not printed text.
- **FR-011 / PRD FR-011: `kind: critique` requires non-empty `proof_path`.** Re-prompt until the user supplies one or explicitly opts out with `--no-proof-path` (warning recorded in body).
- **FR-012 / PRD FR-012: Items are never auto-deleted.** Phase completion updates status; the file persists.
- **FR-020 / PRD FR-020: One phase in-progress at a time.** Reject `--phase start` if any other phase has `status: in-progress`.
- **FR-018c / PRD FR-018c + FR-039 / spec FR-039: Follow-up loop has no infinite path.** Three graceful-exit signals: `no` / empty / non-interactive.
- **FR-037 / spec FR-037: Idempotent writes.** Frontmatter key order in item files is deterministic: `id, title, kind, date, status, phase, state, blast_radius, review_cost, context_cost, [optional keys alpha-sorted]`. Re-running with identical inputs MUST produce a byte-identical file.

## Discovery

For teammates (e.g., `/kiln:kiln-distill`, `/kiln:kiln-next`, `/specify`) that consume roadmap items: the helpers under `plugin-kiln/scripts/roadmap/` are the canonical API. Parse via `parse-item-frontmatter.sh`, validate via `validate-item-frontmatter.sh`, filter via `list-items.sh`, transition state via `update-item-state.sh`. Do not duplicate parsing logic in consumer skills.
