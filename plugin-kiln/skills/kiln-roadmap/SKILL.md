---
name: kiln-roadmap
description: Capture a product-direction idea (feature / goal / research / constraint / non-goal / milestone / critique) as a structured item under `.kiln/roadmap/items/`. Runs an adversarial interview, classifies kind, routes cross-surface (issue / feedback / roadmap) with confirm-never-silent hand-off, migrates legacy `.kiln/roadmap.md` on first run, and mirrors to Obsidian via `shelf:shelf-write-roadmap-note`. Flags — `--quick` (no interview), `--vision` (vision update), `--phase start|complete|create <name>`, `--check` (lifecycle audit), `--reclassify` (promote unsorted). Use as `/kiln:kiln-roadmap <description>`.
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
- `--vision` — update `.kiln/vision.md` instead of capturing an item (FR-019 / PRD FR-019).
- `--phase start <name>` / `--phase complete <name>` / `--phase create <name> --order <N>` — phase management (FR-020 / PRD FR-020).
- `--check` — report items whose `state` is inconsistent with phase/spec/PR reality (FR-022 / PRD FR-022).
- `--reclassify` — walk all `phase: unsorted` items through the interview to promote them (FR-028 follow-up).

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

- `--vision` → jump to **§V: Vision update**.
- `--phase` → jump to **§P: Phase management**.
- `--check` → jump to **§C: Consistency check**.
- `--reclassify` → jump to **§R: Reclassify unsorted**.
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

## Step 5: Adversarial interview (FR-015, FR-017 / PRD FR-015, FR-017)

<!-- FR-015 / PRD FR-015: ≤5 questions per kind, each individually skippable.
     FR-017 / PRD FR-017: sizing asks ONLY blast_radius / review_cost / context_cost — never human-time / T-shirt.
     FR-011 / PRD FR-011: kind:critique REQUIRES proof_path — re-prompt until answered. -->

Skip the entire interview when `QUICK_MODE == 1` OR `NON_INTERACTIVE == 1`. Jump to Step 6 with `phase=unsorted`, body = raw description.

Otherwise, ask the question bank for the confirmed `KIND`. Each question is skippable (user types `skip` or empty) UNLESS marked required. Stop asking early if the user skips a run of ≥3 in a row (respect interview fatigue — Risk #1 in the PRD).

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

If `SHELF_MIRROR_ENABLED=1`, emit the context block so the shelf workflow's parser can locate the source file:

```bash
export ROADMAP_INPUT_BLOCK="$(cat <<EOF
## ROADMAP_WRITE_INPUT
source_file = $ITEM_PATH
## END_ROADMAP_WRITE_INPUT
EOF
)"
```

Then invoke `shelf:shelf-write-roadmap-note` — this workflow reads `.shelf-config` (no vault discovery per FR-004) and writes one Obsidian note at `<base_path>/<slug>/roadmap/items/<basename>`.

If the Obsidian mirror fails, log the error and continue — `.kiln/` writes are the source of truth and the capture is considered successful.

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

## §V: Vision update (`--vision` — FR-019 / PRD FR-019)

<!-- FR-019 / PRD FR-019: short vision-update interview; patch_file on Obsidian (NOT update_file) per FR-031. -->

Refuse to run `--vision` in `NON_INTERACTIVE` mode — print a clear error and exit non-zero. Vision updates require human judgement.

1. Show the current `.kiln/vision.md` body.
2. Ask:
   - "What's changed about the vision?"
   - "What's still true?"
   - "What's newly out-of-scope?"
3. Compose the updated vision (keep frontmatter's `last_updated:` in sync with today's date).
4. Write `.kiln/vision.md` atomically (temp-write + mv).
5. Dispatch `shelf:shelf-write-roadmap-note` with `source_file = .kiln/vision.md`. The workflow picks `patch_file` on update (FR-031 / PRD FR-031) to preserve frontmatter.

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
done
```

Print a tidy report with actionable suggestions per finding. Exit 0 if consistent, non-zero if any inconsistency is found (so CI can gate on it).

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
