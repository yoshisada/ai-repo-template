---
name: create-prd
description: Create PRDs from product ideas or feature requests. Asks clarifying questions, then generates structured PRD artifacts. Supports two modes — new product (full PRD set) and feature addition (scoped feature PRD). Use when the user says "create a PRD", "PRD this", "add a feature", or similar.
---

# Create PRD

Transform a product idea or feature request into a clear, narrowly-scoped PRD — without drifting into architecture specs or engineering tickets.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Step 1: Detect Mode

Determine which mode to operate in:

### Mode A: New Product PRD
Use when:
- `docs/PRD.md` does not exist, or is still the empty template (contains placeholder text like `[Describe what this product does]`)
- The user explicitly says "create a PRD", "PRD this", "new product", or similar
- There is no existing product context to build on

**Output**: 3 files in `docs/`
- `docs/PRD.md`
- `docs/PRD-MVP.md`
- `docs/PRD-Phases.md`

### Mode B: Feature PRD
Use when:
- `docs/PRD.md` already contains real product content (not placeholders)
- The user says "add a feature", "new feature", "extend the product", or describes functionality to add to an existing product
- There is existing product context (tech stack, users, constraints) to inherit

**Output**: 1 file in `docs/features/<YYYY-MM-DD>-<feature-slug>/`
- `docs/features/<YYYY-MM-DD>-<feature-slug>/PRD.md`

If the mode is ambiguous, ask the user: "Is this a new product or a feature addition to the existing product?"

## Step 2: Read Context (Mode B only)

If operating in Mode B (Feature PRD):
1. Read `docs/PRD.md` — extract the product overview, tech stack, target users, and constraints
2. Read `docs/PRD-MVP.md` if it exists — understand current scope and excluded features
3. Read `docs/PRD-Phases.md` if it exists — understand the roadmap and which phase this feature belongs to
4. Read `.specify/memory/constitution.md` if it exists — note any governing constraints

This context shapes the clarifying questions and ensures the feature PRD stays consistent with the product.

## Step 3: Ask Clarifying Questions

Ask a concise set of questions in **one message**. Do not ask questions the user has already answered in their input. If the user provided enough detail, skip directly to generation (Step 5) after confirming.

### Mode A Questions (New Product) — up to 10 questions

Required coverage:
- **Product**: 1-sentence pitch — what the product is and is not
- **Users**: Primary persona, context (B2B/B2C), who pays (if relevant)
- **Problem**: Top pain point, why now
- **Use cases**: Top 3 workflows/journeys
- **MVP**: Single core problem the MVP must solve, expected time-to-ship constraint
- **Scope control**: 3-5 "definitely not in MVP" items
- **Success**: 3 measurable success criteria (with a time window)
- **Constraints**: Platforms, integrations, compliance/security constraints
- **Tech stack** (required): Preferences/constraints — offer to pick defaults if unknown
- **Risks/unknowns**: Biggest unknowns to validate
- **Absolute musts**: Ask at the end for the top priorities (tech stack is always #1)

### Mode B Questions (Feature Addition) — up to 7 questions

Required coverage:
- **Feature**: 1-sentence description — what this feature does and does not do
- **Motivation**: What problem does this solve? Why now? Which users asked for it?
- **Use cases**: Top 2-3 user journeys for this feature
- **Scope control**: What is explicitly NOT part of this feature
- **Impact**: How does this interact with existing features? Any breaking changes?
- **Tech stack additions**: Any new dependencies or infrastructure needed beyond what the product already uses?
- **Success**: 2-3 measurable success criteria for this feature specifically

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
> PRD is ready. To build this product, run `/build-prd` which will execute the full speckit pipeline (specify → plan → tasks → implement → audit → PR).

**Mode B**:
> Feature PRD is ready. To build this feature, run `/build-prd <feature-slug>` which will execute the full speckit pipeline against this feature PRD.

## Do Not Overwrite

If the target folder already exists and contains files, do NOT overwrite. Choose a different slug or ask the user how to proceed.
