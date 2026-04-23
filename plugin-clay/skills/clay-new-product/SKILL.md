---
name: clay-new-product
description: Create PRDs for a new product or feature addition. Asks clarifying questions, then generates structured PRD artifacts. Supports three modes — multi-product repo (products/<slug>/), new product, and feature addition. Default output is products/<slug>/. Use when the user says "new product", "create a PRD", "PRD this", "add a feature", or similar.
---

# New Product — Create a PRD

Transform a product idea or feature request into a clear, narrowly-scoped PRD — without drifting into architecture specs or engineering tickets.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

<!-- FR-012: Parse --parent=<slug> flag for programmatic sub-idea creation. -->
<!-- Contracts §8: flag parsing idiom, validation rule, error text. -->
## Step 0a: Parse `--parent=<slug>` Flag

Before mode detection, parse `$ARGUMENTS` for a `--parent=<slug>` flag. This is a programmatic callpath distinct from `/clay:clay-idea`'s intent prompt — the two flows are independent.

```bash
PARENT_SLUG=""
REMAINING_ARGS=""
for arg in $ARGUMENTS; do
  case "$arg" in
    --parent=*) PARENT_SLUG="${arg#--parent=}" ;;
    *) REMAINING_ARGS="$REMAINING_ARGS $arg" ;;
  esac
done
REMAINING_ARGS="${REMAINING_ARGS# }"  # trim leading space

# Validate parent if --parent was provided
if [ -n "$PARENT_SLUG" ]; then
  if [ ! -f "products/$PARENT_SLUG/about.md" ]; then
    echo "--parent=$PARENT_SLUG provided but products/$PARENT_SLUG/about.md does not exist."
    exit 1
  fi
  # Output base for every artifact this skill writes: nest under the parent
  # The <sub-slug> is derived later in the normal slug derivation step, then used as:
  #   OUTPUT_BASE="products/$PARENT_SLUG/$SUB_SLUG"
  # Mode A artifacts land in $OUTPUT_BASE/; Mode C features land in $OUTPUT_BASE/features/<dated>/.
  IS_SUB_IDEA=true
else
  IS_SUB_IDEA=false
fi

# Remaining args replace $ARGUMENTS for the rest of the skill
ARGUMENTS="$REMAINING_ARGS"
```

When `IS_SUB_IDEA=true`, every generated PRD file (Mode A or Mode C) must also inject `parent: $PARENT_SLUG` into its frontmatter (see Step 4 below).

## Step 0: Detect Mode

Determine how to organize the output by inspecting the workspace.

### Mode A: Product Collection (Default)

Use when:
- A `products/` directory exists (or this is a PRD-focused repo)
- No `docs/PRD.md` exists with real product content
- The user explicitly says "new product", "create a PRD", "PRD this", or similar
- Multiple products may coexist in this repo

**Output**: 3 files in `products/<product-slug>/`
- `products/<product-slug>/PRD.md`
- `products/<product-slug>/PRD-MVP.md`
- `products/<product-slug>/PRD-Phases.md`

### Mode B: Single-Product Repo

Use when:
- `docs/PRD.md` does not exist (or contains only placeholders like `[Describe what this product does]`)
- A `src/` directory exists, indicating this is an implementation repo for a single product
- The user's intent is clearly a single product (not a collection)

**Output**: 3 files in `docs/`
- `docs/PRD.md`
- `docs/PRD-MVP.md`
- `docs/PRD-Phases.md`

### Mode C: Feature Addition

Use when:
- A product PRD already exists (`docs/PRD.md` or `products/<slug>/PRD.md`) with real content
- The user says "add a feature", "new feature", "extend the product", or describes functionality to add

**Output**: 1 file
- Single-product repo: `docs/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`
- Product collection: `products/<product-slug>/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`

### Mode resolution

If ambiguous, ask: "Is this a new product or a feature addition to an existing product?"

When a `products/` directory exists with multiple products and Mode C applies, list existing products and ask which one the feature belongs to.

## Step 1: Read Context

<!-- FR-003: Read intent: from products/<slug>/idea.md to detect simplified PRD mode. -->
<!-- Decision 2: Missing intent is treated as `marketable` (default full pipeline). -->

### Step 1.0: Detect intent (simplified-PRD mode for `internal`)

If `products/$SLUG/idea.md` exists, read the `intent:` frontmatter field. If missing or unknown, treat as `marketable`.

```bash
read_frontmatter_field() {
  local file="$1"
  local key="$2"
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
    in_fm && $1 == k":" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
  ' "$file"
}

INTENT=""
if [ -n "$SLUG" ] && [ -f "products/$SLUG/idea.md" ]; then
  INTENT=$(read_frontmatter_field "products/$SLUG/idea.md" intent)
fi
case "$INTENT" in
  internal|marketable|pmf-exploration) ;;
  *) INTENT="marketable" ;;
esac
```

When `$INTENT = internal`, switch to **simplified PRD mode** for the rest of this skill:

- Do NOT read `products/<slug>/research.md` (won't exist; don't rely on it)
- Do NOT read `products/<slug>/naming.md` (won't exist; don't rely on it)
- Drop these sections from the generated PRD: "Competitive Landscape", "Market Research", "Naming / Branding"
- Keep these sections: Problem Statement, Users (single-user: the maintainer), Requirements, Tech Stack, What we are NOT building
- User persona defaults to "the maintainer themselves"; do not ask B2B/B2C questions

When `$INTENT = marketable` or `pmf-exploration` (or empty/unknown): proceed with the full Mode A / Mode B pipeline as before.

### All modes
- Read `.specify/memory/constitution.md` if it exists — note governing constraints

### Mode A / Mode B: Incorporate prior artifacts
If `products/<slug>/research.md` exists, read it and incorporate:
- Market landscape findings (competitors, gaps)
- Go/no-go recommendation context
- Key differentiators identified

If `products/<slug>/naming.md` exists, read it and incorporate:
- Chosen product name (use as the product name in the PRD)
- Branding context and rationale

These findings should flow into the PRD automatically — the user should NOT need to re-state information already captured in research or naming reports.

### Mode C: Feature additions
1. Read the parent product PRD — extract overview, tech stack, target users, constraints
   - Single-product repo: `docs/PRD.md`
   - Product collection: `products/<product-slug>/PRD.md`
2. Read MVP doc if it exists — understand current scope and excluded features
3. Read Phases doc if it exists — understand the roadmap

This context shapes clarifying questions and ensures the feature PRD stays consistent.

## Step 2: Ask Clarifying Questions

**Ask questions ONE AT A TIME.** Do not dump all questions in one message. After each answer, move to the next question.

### Conversation flow rules

1. **Skip questions the user already answered** in their initial input. Extract everything you can from what they gave you.
2. **Offer multiple-choice when you can infer likely answers.** Present 2-4 choices (labeled a/b/c/d) with a brief explanation. Always include a final option: "Other — describe your own."
3. **One question per message.** Keep each question short (1-3 sentences max).
4. **Acknowledge the answer briefly** before asking the next question (e.g., "Got it — B2B SaaS for dev teams.").
5. **Stop early if you have enough.** If the user provided a rich description and you can fill in the remaining answers with high confidence, present your assumptions as a summary and ask: "I'm going to proceed with these assumptions — anything you'd change?" Then skip to generation.

### Mode A / Mode B Questions (New Product) — ask in this order

1. **Product pitch**: What is this product in one sentence?
2. **Users**: Who is the primary user?
   - _Offer multiple-choice if inferable, e.g.:_ `a) B2B — dev teams  b) B2B — enterprise ops  c) B2C — consumers  d) Other`
3. **Problem**: What's the #1 pain point this solves? Why now?
4. **Use cases**: What are the top 3 things a user does with this product?
5. **MVP scope**: What single core problem must the MVP solve? How fast do you want to ship?
   - _Offer multiple-choice for timeline, e.g.:_ `a) 1-2 weeks  b) 1 month  c) 2-3 months  d) No constraint`
6. **Scope control**: Name 3-5 things that are definitely NOT in the MVP.
   - _Offer suggestions based on what you've heard so far_
7. **Tech stack**: Any preferences or constraints?
   - _Offer a recommended stack based on the product type_
8. **Constraints**: Platforms, integrations, compliance, or security requirements?
9. **Success metrics**: How do you measure success? (3 measurable criteria with a time window)
   - _Offer suggestions, e.g.:_ `a) X users in 30 days  b) Y% retention at 2 weeks  c) Z conversion rate  d) Custom`
10. **Absolute musts**: What are the non-negotiable priorities (top 3-7)? Tech stack is always #1.
11. **Risks & unknowns**: Biggest unknowns to validate?

### Mode C Questions (Feature Addition) — ask in this order

1. **Feature**: What does this feature do in one sentence?
2. **Motivation**: What problem does this solve? Why now?
   - _Offer multiple-choice if inferable, e.g.:_ `a) User-requested  b) Competitive pressure  c) Internal need  d) Growth opportunity`
3. **Use cases**: Top 2-3 user journeys for this feature
4. **Scope control**: What is explicitly NOT part of this feature?
   - _Suggest likely exclusions based on feature description_
5. **Impact**: How does this interact with existing features? Any breaking changes?
   - _Offer:_ `a) Standalone — no impact  b) Extends existing feature  c) Replaces existing feature  d) Breaking changes expected`
6. **Tech stack additions**: Anything new needed beyond the current stack?
   - _Offer:_ `a) No — current stack is fine  b) Need a new dependency (specify)  c) New infrastructure needed`
7. **Success**: 2-3 measurable success criteria for this feature

### If the user cannot or will not answer

Offer two options:
1. Stop and wait for answers
2. Proceed with "TBD" placeholders (no invented specifics) — only after the user explicitly approves

## Step 3: Tech Stack Requirement (must enforce)

The PRD must include a clearly defined tech stack. This is required for all modes.

Rules:
- Never leave the tech stack undefined in the final PRD artifacts
- If the user does not know, propose a default stack (2-3 options max) and require the user to choose one (or explicitly say "you choose") before writing files
- Mode C inherits the product tech stack from the parent PRD — only ask about additions or overrides
- In the PRD, always treat the tech stack as the highest priority absolute must

## Step 4: Generate PRD Artifacts

<!-- FR-008, FR-012: When IS_SUB_IDEA=true (from Step 0a), all generated PRD files must carry `parent: $PARENT_SLUG` frontmatter and land under `products/$PARENT_SLUG/$SUB_SLUG/`. -->
<!-- Contracts §2: parent: value must equal the immediate-parent directory name on disk. -->

**Nested output (sub-idea) path**: When `$IS_SUB_IDEA=true`, override the Mode A / Mode C output paths as follows:

- Mode A nested: write to `products/$PARENT_SLUG/$SUB_SLUG/PRD.md`, `.../PRD-MVP.md`, `.../PRD-Phases.md`
- Mode C nested: write to `products/$PARENT_SLUG/$SUB_SLUG/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`

Inject this frontmatter field into EVERY generated file when `$IS_SUB_IDEA=true`:

```yaml
parent: <PARENT_SLUG>
```

Validation rule (contracts §2): the `parent:` value MUST equal the immediate-parent directory name on disk. If the computed output path is not nested under `products/$PARENT_SLUG/`, stop and report the inconsistency.

Do NOT create any files until the user has answered the clarifying questions (or explicitly approved TBDs).

### Pre-generation summary

Before writing files, restate the product/feature in 2-3 sentences based only on user answers and identify:
- The primary user persona
- The primary "job to be done"
- The top 3 user journeys/use cases

### Mode A: Generate 3 files in `products/<product-slug>/`

Use the templates in `assets/` as structure. Fill them with real content — no placeholder prompt text.

1. **`products/<product-slug>/PRD.md`** — Full product requirements using `assets/PRD.template.md`
2. **`products/<product-slug>/PRD-MVP.md`** — MVP scoping using `assets/PRD-MVP.template.md`
3. **`products/<product-slug>/PRD-Phases.md`** — Phased rollout (at least 3 phases) using `assets/PRD-Phases.template.md`

Create `products/` at the repo root if it doesn't exist. The `<product-slug>` should be a short, kebab-case name (e.g., `billing-app`, `mobile-client`).

### Mode B: Generate 3 files in `docs/`

Same templates as Mode A:

1. **`docs/PRD.md`** — using `assets/PRD.template.md`
2. **`docs/PRD-MVP.md`** — using `assets/PRD-MVP.template.md`
3. **`docs/PRD-Phases.md`** — using `assets/PRD-Phases.template.md`

### Mode C: Generate 1 file

Use `assets/Feature-PRD.template.md` as the structure.

- Single-product repo: `docs/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`
- Product collection: `products/<product-slug>/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`

Link back to the parent product PRD. Inherit tech stack, target users, and constraints — only list additions/overrides.

### MVP Rules (all modes)

- Solve **one core user problem**
- Ship **quickly** (bias to smallest coherent scope)
- Avoid unnecessary complexity (no premature scaling, no "platform" work)
- Always include **"What we are NOT building"**

### Style Rules (all modes)

- Clear and concise; no corporate filler
- Understandable to founders and engineers
- Implementation details minimal (no system architecture, no ticket breakdown)
- Use bullet points for scanability

## Step 5: Confirm and Next Steps

After generating the PRD artifacts:

1. Summarize what was created and where
2. Ask the user to review and flag anything that needs changes
3. Suggest the next step based on mode:

**Mode A** (product collection):
> PRD is ready at `products/<product-slug>/`. To build this product, run `/clay:clay-create-repo <product-slug>` to scaffold a new repo seeded with this PRD, then `/kiln:kiln-build-prd` inside that repo.

**Mode B** (single-product repo):
> PRD is ready. To build this product, run `/kiln:kiln-build-prd` which will execute the full pipeline (specify → plan → tasks → implement → audit → PR).

**Mode C** (feature addition):
> Feature PRD is ready. To build this feature, run `/kiln:kiln-build-prd <feature-slug>` to execute the full pipeline against this feature PRD.

## Do Not Overwrite

If the target folder already exists and contains files, do NOT overwrite. Choose a different slug or ask the user how to proceed.
