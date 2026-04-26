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

## Step 4a: Offer Skip / Run Interview

After classification resolves, run a short interview by default. The interview is 3 default questions + up to 2 area-specific add-ons (5 max; `other` area gets 0 add-ons → 3 total).

**Skip option** (Decision 5 / FR-010): at EVERY interview prompt, the LAST option is verbatim:

```
skip interview — just capture the one-liner
```

Picking skip at any prompt (first or mid-interview) immediately ends the interview. Any partial answers already given are DROPPED — skip is all-or-nothing. The skill proceeds directly to Step 5 with no `## Interview` section. There is NO CLI flag equivalent; the in-prompt opt-out is the only skip surface (matches `clay-ideation-polish` precedent — interactive skills don't get flags).

## Step 4b: Interview

Ask the 3 default questions, in order, verbatim. For each question, present two options: "type your answer" and the skip option as described in Step 4a.

**Default questions** (asked for every area, including `other`):

1. `What does "done" look like for this feedback? Describe the observable outcome.`
2. `Who triggers the change, and when? (ad-hoc skill, hook, background agent, part of an existing skill, human maintainer decision…)`
3. `What's the scope? Just this repo, consumer repos too, or other plugins as well?`

**Area-specific add-ons** (asked AFTER the 3 defaults, based on `area` classified in Step 4):

| area | Qa | Qb |
|---|---|---|
| `mission` | `Which part of the stated mission does this change, extend, or contradict?` | `Who does this change the product FOR — and does that change the target user?` |
| `scope` | `What's newly in scope after this change, and what (if anything) moves out of scope?` | `Is there an existing feature or plugin this supersedes or narrows?` |
| `ergonomics` | `Which existing friction point does this resolve, and how will you know it's gone?` | `Is there a paired tactical backlog entry in .kiln/issues/ that this feedback pairs with? (path, or "none")` |
| `architecture` | `What structural boundary or plugin shape does this change?` | `What does the rollout look like — one PR, staged, or a migration?` |
| `other` | *(no add-on — skip Qa)* | *(no add-on — skip Qb)* |

For `area == other`, the interview is exactly 3 questions total. For every other area, it is exactly 5 questions total.

**Blank answer handling**: if the user types nothing (empty string or whitespace only), re-prompt ONCE with the same question text. If the second answer is also blank, record the literal string `(no answer)` for that question and continue to the next one. A blank answer is NOT a skip — only the explicit last-option choice ends the interview.

**Collecting answers**: maintain an ordered list of `(question-text, answer-text)` tuples. Order is Q1, Q2, Q3, then Qa, Qb for the classified area (omit Qa/Qb entirely for `other`). This ordering is the invariant written to the body in Step 5.

**Skip mid-interview**: if skip is selected at any question (including Q1), discard any answers already collected and jump to Step 5 with an empty answer list (signals no `## Interview` section).

## Step 4c: Research-Block Inference (FR-015 / FR-016 of research-first-completion)

<!-- T012 / FR-015 / FR-016 / NFR-006 / Decision 9 / contracts §8 of
     research-first-completion. Conditional question stanza — fires ONLY
     when classify-description.sh emitted a research_inference key.
     Inserted as a coached-capture step BEFORE the Step 5 file-write,
     conditional on research_inference being present. Absent → silently
     skipped (false-negative recovery is structural per NFR-006). -->

Run the classifier against the feedback description. If `research_inference`
is present, render the FR-015 single accept/tweak/reject question; record
the response and pass the resolved research-block fields (or absence) to
Step 5's frontmatter writer.

```bash
CLASSIFICATION_JSON=$(bash plugin-kiln/scripts/roadmap/classify-description.sh "$ARGUMENTS" 2>/dev/null)
HAS_RESEARCH_INFERENCE=$(printf '%s' "$CLASSIFICATION_JSON" | jq -r 'has("research_inference")' 2>/dev/null)
if [ "$HAS_RESEARCH_INFERENCE" = "true" ]; then
  RB_PROPOSAL=$(printf '%s' "$CLASSIFICATION_JSON" | jq -c .research_inference)
  # Render the question per coach-driven-capture §5.0; for output_quality
  # axes the rationale carries the FR-016 verbatim warning on its own line.
fi
```

**Question shape**:

```
Q: Does this need research?
   Proposed: needs_research: true
             empirical_quality:
               - metric: <metric>
                 direction: <direction>
                 priority: primary
   Why: matched signal word: <word>
        [for output_quality axes, FR-016 verbatim warning on its own line]
   [accept / tweak <value> / reject / skip / accept-all]
   > _
```

**Response handling**:
- `accept` → record the proposed research-block fields; Step 5 emits them in the feedback frontmatter after the existing keys.
- `tweak <value>` → maintainer edits any field; re-prompt with edited proposal.
- `reject` / `skip` → write NO research-block keys (NFR-006 structural absence).
- `accept-all` → accept this proposal.

**Validator surface**: `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` validates the resulting feedback file's research-block frontmatter (callable post-write for cross-check).

## Step 5: Write the File

Write the file to `.kiln/feedback/${today}-${slug}.md` with frontmatter matching Contract 1 exactly. Frontmatter is byte-identical to today's shape (NFR-003 Contract 1) — the interview changes ONLY the body, not the frontmatter.

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

<$ARGUMENTS verbatim>

## Interview                 # ONLY when Step 4b completed (not skipped)

### <Q1 text verbatim>

<Q1 answer, or literal `(no answer)` if re-prompt also blank>

### <Q2 text verbatim>

<Q2 answer>

### <Q3 text verbatim>

<Q3 answer>

### <Qa text verbatim>       # omit Qa + Qb heading+body for area == other

<Qa answer>

### <Qb text verbatim>

<Qb answer>
```

**Body shape rules**:

- If the interview was SKIPPED (at any prompt), the body equals `$ARGUMENTS` verbatim with NO `## Interview` section. Shape identical to today's skill output.
- If the interview COMPLETED, append a blank line after `$ARGUMENTS`, then the `## Interview` heading, then one `### <question-text>` sub-heading per collected answer, in the order Q1, Q2, Q3, Qa, Qb (Qa/Qb omitted for `other`). Each question text is the exact verbatim wording from Step 4b — no paraphrasing.
- The `## Interview` heading appears EXACTLY ONCE when present (SC-006 invariant).
- Blank answers that re-prompted and stayed blank are written as the literal string `(no answer)` under that question's sub-heading.

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

- No MCP writes, no wheel workflow, no Obsidian sync — just write the local file and exit. Interview runs inline in main chat; it does NOT break this rule.
- Classification is a hard gate: if `severity` or `area` is ambiguous from the description, ASK before writing. Classification gate fires BEFORE the interview (Step 4 before Step 4b).
- Interview runs by default — skip is the escape hatch, not the default. The skip option is a single in-prompt opt-out (verbatim `skip interview — just capture the one-liner`), always the last option at every prompt. No CLI flag.
- Interview answers go in the BODY (NFR-003 Contract 2 / FR-009), never in the frontmatter. Frontmatter shape is byte-identical to today.
- `type:` is always the literal `feedback` — never let the user override.
- The `.kiln/feedback/` directory is committed (not gitignored), matching `.kiln/issues/` policy.
- `/kiln:kiln-distill` picks up open feedback files on its next run and leads PRD narratives with them (FR-012).
- If the user reports multiple pieces of feedback at once, run the skill once per item — one file per piece.
- If `$ARGUMENTS` is empty, ask before writing — don't write an empty file.
