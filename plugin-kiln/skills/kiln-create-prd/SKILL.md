---
name: kiln-create-prd
description: Create PRDs from product ideas or feature requests. Asks clarifying questions, then generates structured PRD artifacts. Supports three modes — PRD-only repo (multi-product), new product, and feature addition. Use when the user says "create a PRD", "PRD this", "add a feature", or similar.
---

# Create PRD

Transform a product idea or feature request into a clear, narrowly-scoped PRD — without drifting into architecture specs or engineering tickets.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Step 0: Detect Repo Type

Before choosing a mode, determine if this is a **PRD-only repo** — a repo used exclusively for product design documents, not implementation.

A repo is PRD-only if **any** of these are true:
- No `src/` directory exists (or it only contains `.gitkeep`)
- Multiple product directories already exist under a top-level `products/` or `prds/` folder
- The repo name or README suggests it's a design/PRD collection (e.g., "product-specs", "prds", "design-docs")
- The user explicitly says "this is a PRD repo" or "I just use this for PRDs"

If PRD-only → use **Mode C**.
Otherwise → continue to Step 1 for Mode A or B detection.

## Step 1: Detect Mode

Determine which mode to operate in:

### Mode A: New Product PRD
Use when:
- NOT a PRD-only repo
- `docs/PRD.md` does not exist, or is still the empty template (contains placeholder text like `[Describe what this product does]`)
- The user explicitly says "create a PRD", "PRD this", "new product", or similar
- There is no existing product context to build on

**Output**: 3 files in `docs/`
- `docs/PRD.md`
- `docs/PRD-MVP.md`
- `docs/PRD-Phases.md`

### Mode B: Feature PRD
Use when:
- NOT a PRD-only repo
- `docs/PRD.md` already contains real product content (not placeholders)
- The user says "add a feature", "new feature", "extend the product", or describes functionality to add to an existing product
- There is existing product context (tech stack, users, constraints) to inherit

**Output**: 1 file in `docs/features/<YYYY-MM-DD>-<feature-slug>/`
- `docs/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`

### Mode C: PRD-Only Repo
Use when:
- Repo is detected as PRD-only (see Step 0)
- The user wants to create a new product PRD or add a feature to an existing product in the collection

**Output**: Files organized by product name under a `products/` directory:

```
products/
└── <product-slug>/
    ├── PRD.md
    ├── PRD-MVP.md
    ├── PRD-Phases.md
    └── features/
        └── <YYYY-MM-DD>-<feature-slug>/
            └── PRD.md
```

If Mode C and `products/<product-slug>/PRD.md` already exists, treat it as a feature addition to that product (same as Mode B but under the product directory).

If the mode is ambiguous, ask the user: "Is this a new product, a feature addition, or should I treat this as a PRD-only repo?"

## Step 2: Read Context (Mode B and Mode C feature additions)

If operating in Mode B or adding a feature in Mode C:
1. Read the parent product PRD — extract the product overview, tech stack, target users, and constraints
   - Mode B: `docs/PRD.md`
   - Mode C: `products/<product-slug>/PRD.md`
2. Read the MVP doc if it exists — understand current scope and excluded features
3. Read the Phases doc if it exists — understand the roadmap and which phase this feature belongs to
4. Read `.specify/memory/constitution.md` if it exists — note any governing constraints

This context shapes the clarifying questions and ensures the feature PRD stays consistent with the product.

## Step 3: Ask Clarifying Questions

**Ask questions ONE AT A TIME.** Do not dump all questions in one message. After each answer, move to the next question.

### Conversation flow rules

1. **Skip questions the user already answered** in their initial input. Extract everything you can from what they gave you.
2. **Offer multiple-choice when you can infer likely answers.** If the user's input gives you enough context to propose options, present 2-4 choices (labeled a/b/c/d) with a brief explanation of each. Always include a final option: "Other — describe your own."
3. **One question per message.** Keep each question short (1-3 sentences max). Include the multiple-choice options if applicable.
4. **Acknowledge the answer briefly** before asking the next question (e.g., "Got it — B2B SaaS for dev teams."). Do not repeat back their full answer.
5. **Stop early if you have enough.** If the user provided a rich description and you can fill in the remaining answers with high confidence, present your assumptions as a summary and ask: "I'm going to proceed with these assumptions — anything you'd change?" Then skip to generation.

### Mode A Questions (New Product) — ask in this order

1. **Product pitch**: What is this product in one sentence?
2. **Users**: Who is the primary user?
   - _Offer multiple-choice if inferable, e.g.:_ `a) B2B — dev teams  b) B2B — enterprise ops  c) B2C — consumers  d) Other`
3. **Problem**: What's the #1 pain point this solves? Why now?
4. **Use cases**: What are the top 3 things a user does with this product?
5. **MVP scope**: What single core problem must the MVP solve? How fast do you want to ship?
   - _Offer multiple-choice for timeline, e.g.:_ `a) 1-2 weeks  b) 1 month  c) 2-3 months  d) No constraint`
6. **Scope control**: Name 3-5 things that are definitely NOT in the MVP.
   - _Offer suggestions based on what you've heard so far, e.g.:_ `Based on what you've described, these are probably out of MVP scope: a) Admin dashboard  b) Multi-tenancy  c) Analytics  d) Mobile app — agree, or adjust?`
7. **Tech stack**: Any preferences or constraints?
   - _Offer a recommended stack based on the product type, e.g.:_ `For a web app like this, I'd suggest: a) Next.js + TypeScript + Prisma  b) Vite + React + Drizzle  c) You choose the best fit  d) I have something specific in mind`
8. **Constraints**: Platforms, integrations, compliance, or security requirements?
9. **Success metrics**: How do you measure success? (3 measurable criteria with a time window)
   - _Offer suggestions, e.g.:_ `a) X users in 30 days  b) Y% retention at 2 weeks  c) Z conversion rate  d) Custom`
10. **Risks & absolute musts**: Biggest unknowns? And what are the non-negotiable priorities? (Tech stack is always #1)

### Mode B Questions (Feature Addition) — ask in this order

1. **Feature**: What does this feature do in one sentence?
2. **Motivation**: What problem does this solve? Why now?
   - _Offer multiple-choice if inferable, e.g.:_ `a) User-requested  b) Competitive pressure  c) Internal need  d) Growth opportunity`
3. **Use cases**: Top 2-3 user journeys for this feature
4. **Scope control**: What is explicitly NOT part of this feature?
   - _Suggest likely exclusions based on feature description_
5. **Impact**: How does this interact with existing features? Any breaking changes?
   - _Offer multiple-choice, e.g.:_ `a) Standalone — no impact  b) Extends existing feature  c) Replaces existing feature  d) Breaking changes expected`
6. **Tech stack additions**: Anything new needed beyond the current stack?
   - _Offer:_ `a) No — current stack is fine  b) Need a new dependency (specify)  c) New infrastructure needed`
7. **Success**: 2-3 measurable success criteria for this feature

### If the user cannot or will not answer

Offer two options:
1. Stop and wait for answers
2. Proceed with "TBD" placeholders (no invented specifics) — only after the user explicitly approves

## Step 4: Tech Stack Requirement (must enforce)

The PRD must include a clearly defined tech stack. This is required for both modes.

Rules:
- Never leave the tech stack undefined in the final PRD artifacts
- If the user does not know, propose a default stack (2-3 options max) and require the user to choose one (or explicitly say "you choose") before writing files
- Mode B inherits the product tech stack from `docs/PRD.md` — only ask about additions or overrides
- In the PRD, always treat the tech stack as the highest priority absolute must

## Step 5: Generate PRD Artifacts

Do NOT create any files until the user has answered the clarifying questions (or explicitly approved TBDs).

### Mode A: Generate 3 files

Use the templates in `assets/` as structure. Fill them with real content — no placeholder prompt text.

1. **`docs/PRD.md`** — Full product requirements using `assets/PRD.template.md`
2. **`docs/PRD-MVP.md`** — MVP scoping using `assets/PRD-MVP.template.md`
3. **`docs/PRD-Phases.md`** — Phased rollout (at least 3 phases) using `assets/PRD-Phases.template.md`

Before writing, restate the product in 2-3 sentences based only on user answers and identify:
- The primary user persona
- The primary "job to be done"
- The top 3 user journeys/use cases

### Mode B: Generate 1 file

Use `assets/Feature-PRD.template.md` as the structure.

1. Create `docs/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`
2. Link back to the parent product PRD
3. Inherit tech stack, target users, and constraints from the product PRD
4. Only list tech stack additions/overrides, not the full inherited stack

Before writing, restate the feature in 1-2 sentences and identify how it fits into the existing product.

### Mode C: PRD-Only Repo

#### New product in the collection

Same templates as Mode A, but output to `products/<product-slug>/`:

1. **`products/<product-slug>/PRD.md`** — using `assets/PRD.template.md`
2. **`products/<product-slug>/PRD-MVP.md`** — using `assets/PRD-MVP.template.md`
3. **`products/<product-slug>/PRD-Phases.md`** — using `assets/PRD-Phases.template.md`

Create `products/` at the repo root if it doesn't exist. The `<product-slug>` should be a short, kebab-case name for the product (e.g., `billing-app`, `mobile-client`).

#### Feature addition to existing product

Same as Mode B, but under the product directory:

1. Create `products/<product-slug>/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`
2. Link back to `products/<product-slug>/PRD.md`

Before writing, list existing products in `products/` so the user can choose which product to add the feature to (or create a new one).

### MVP Rules (both modes)

- Solve **one core user problem**
- Ship **quickly** (bias to smallest coherent scope)
- Avoid unnecessary complexity (no premature scaling, no "platform" work)
- Always include **"What we are NOT building"**

### Style Rules (both modes)

- Clear and concise; no corporate filler
- Understandable to founders and engineers
- Implementation details minimal (no system architecture, no ticket breakdown)
- Use bullet points for scanability

## Step 6: Confirm and Next Steps

After generating the PRD artifacts:

1. Summarize what was created and where
2. Ask the user to review and flag anything that needs changes
3. Suggest the next step based on mode:

**Mode A**:
> PRD is ready. To build this product, run `/kiln:kiln-build-prd` which will execute the full kiln pipeline (specify → plan → tasks → implement → audit → PR).

**Mode B**:
> Feature PRD is ready. To build this feature, run `/kiln:kiln-build-prd <feature-slug>` which will execute the full kiln pipeline against this feature PRD.

**Mode C** (new product):
> PRD is ready at `products/<product-slug>/`. To build this product, run `/clay:clay-create-repo <product-slug>` to scaffold a new repo, then `/kiln:kiln-build-prd` inside that repo.

**Mode C** (feature addition):
> Feature PRD is ready at `products/<product-slug>/features/<feature-slug>/`. To build this feature, open the product's repo and run `/kiln:kiln-build-prd <feature-slug>`.

## Do Not Overwrite

If the target folder already exists and contains files, do NOT overwrite. Choose a different slug or ask the user how to proceed.
