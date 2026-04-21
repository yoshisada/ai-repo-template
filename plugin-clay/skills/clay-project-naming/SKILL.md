---
name: clay-project-naming
description: Research and propose distinctive project names with availability checks for npm, GitHub, and domains. Use when a user wants help naming a product, app, startup, tool, or repository.
---

# Project Naming

Name the current project in a way that is relevant, memorable, and likely distinct enough to brand.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## When to Use

Use when the user asks to:

- name a project, product, startup, app, tool, or repository
- brainstorm brandable names tied to a product concept
- check whether proposed names are too generic or too close to existing products
- suggest domains, handles, or lightweight brand messaging

Do **not** use for legal trademark clearance, full brand identity design, or generic brainstorming that is intentionally detached from the actual product.

## Step 1: Understand the Product

### Gather Context (FR-010)

Collect product context from one or more of these sources (in priority order):

1. **`$ARGUMENTS`** — user-provided product context or slug
2. **`products/<slug>/research.md`** — if a product slug is provided or inferrable, read the research report for market context
3. **Repository inspection** — README, specs, docs, metadata, package.json
4. **Conversation context** — what the user has described so far

If the product is too unclear to name responsibly, ask a targeted follow-up:

- What does the product do?
- Who is the primary user?
- What category does it fall into (CLI tool, SaaS, library, app)?

### Determine the Product Slug

If a product slug was provided or exists from prior research, reuse it. Otherwise, derive one:

```bash
SLUG=$(echo "$PRODUCT_SUMMARY" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr -s ' ' '-' | cut -d'-' -f1-5)
mkdir -p "products/$SLUG"
```

### Summarize Before Ideating

Write a plain-language summary covering:

- **Category**: What type of product is this?
- **Audience**: Who uses it?
- **Core workflow**: What do they do with it?
- **Differentiators**: What makes it distinct from alternatives?
- **Tone**: Technical, playful, professional, minimal?

## Step 2: Build Naming Directions

Generate several naming themes. Include at least 3 of these styles:

- **Descriptive**: Names that directly describe the function (e.g., "PageSpeed", "Terraform")
- **Metaphorical**: Names drawn from analogy or imagery (e.g., "Lighthouse", "Anchor")
- **Compound**: Two words combined meaningfully (e.g., "GitHub", "Postman")
- **Technical**: Names from the domain's vocabulary (e.g., "Webpack", "Redux")
- **Invented**: Coined words that sound good and are highly brandable (e.g., "Vercel", "Supabase")
- **Short/Punchy**: One-syllable or very short names (e.g., "Deno", "Bun", "Vite")

Keep all directions aligned with the actual product and audience. Avoid trademark-heavy phrasing and buzzword piles.

## Step 3: Generate Candidate Names (FR-011)

1. Generate a broad initial set (15-20 names across the directions)
2. Narrow to the strongest 5-10 based on:
   - Clarity — does the name hint at what the product does?
   - Memorability — is it easy to recall and spell?
   - Tone — does it match the product's personality?
   - Fit — does it work for the target audience?
3. Each finalist must have a rationale tied to the product, not just "sounds cool"

## Step 4: Check Availability (FR-012)

For each of the top 5-10 candidates, check:

### npm Package

Use WebSearch to check `https://www.npmjs.com/package/<name>`:

- `available` — no package found
- `likely available` — package exists but is unmaintained/empty
- `unavailable` — active package exists

### GitHub Organization/Repository

Use WebSearch to check `https://github.com/<name>`:

- `available` — no org or notable repo with that name
- `likely available` — org exists but inactive
- `unavailable` — active org or popular repo exists

### Domain Availability

Check `.com`, `.dev`, and `.io` domains. Use WebSearch to check Namecheap pricing for the strongest candidates:

- `available` — standard registration price found
- `premium` — available but at premium/resale pricing
- `unavailable` — domain is active with content
- `unclear` — could not determine status

If live Namecheap pricing cannot be retrieved, say so clearly instead of implying the check was completed.

### Distinctiveness

For each name, flag:

- Obvious collisions with existing tools, companies, or well-known products
- Names that are too generic or crowded in search results
- Names too similar to established brands

Never present a name as safe if it looks ambiguous or contested.

## Step 5: Write the Naming Report (FR-013)

Write the report to `products/<slug>/naming.md`.

Use this structure:

```markdown
# Project Naming: <Product Summary>

**Date**: <today>
**Slug**: <slug>

## Product Summary

<What the product is and who it is for>

## Naming Directions

| Direction | Theme | Examples |
|-----------|-------|----------|
| Descriptive | ... | ... |
| Metaphorical | ... | ... |
| ... | ... | ... |

## Candidate Names

### 1. <Name> (RECOMMENDED)

- **Rationale**: Why this name fits the product
- **npm**: available / unavailable
- **GitHub**: available / unavailable
- **Domains**: .com (available / $XX premium / unavailable), .dev (...), .io (...)
- **Distinctiveness**: Low / Medium / High risk
- **Notes**: Any caveats

### 2. <Name>

...

### 3-5. ...

## Recommendation

**Top pick**: <Name>
**Why it wins**: <1-2 sentences — not just "sounds good" but why it fits this specific product>
**Tradeoffs**: <What you give up with this choice>
**Suggested domain**: <best available domain option>
**Suggested handle**: @<handle> on X/GitHub

## Optional: Brand Messaging

_Include only when requested or clearly helpful._

- **Positioning line**: One sentence describing what the product is
- **Tagline options**: 2-3 short taglines
- **Value proposition**: A short homepage-style paragraph
```

## Step 6: Present Results

After writing the file, present a concise summary to the user:

1. The product context that informed naming
2. Top 3 recommendations with key availability data
3. The recommended pick and why
4. The file path where the full report was saved

## Step 7: Iterative Refinement (FR-014)

If the user responds with feedback like:

- "more like X" — generate more names in that direction
- "avoid Y patterns" — exclude that style and regenerate
- "I like Z but want something shorter" — refine around that seed
- "check availability for W" — run availability checks on specific names

Update `products/<slug>/naming.md` with the refined results, appending a "## Refinement Round N" section rather than overwriting the original analysis.

## Quality Checks

Before finishing, verify:

- [ ] Names are tied to the actual product, not generic brainstorming
- [ ] The final set includes varied naming styles (not minor variants of one idea)
- [ ] Crowded or risky names are clearly flagged
- [ ] Availability claims are labeled with honest uncertainty
- [ ] Namecheap pricing is included for strongest candidates or explicitly noted as unavailable
- [ ] The recommendation explains why it wins, not just that it sounds good
- [ ] The report is written to `products/<slug>/naming.md`

## Stop Conditions

Pause and ask for clarification if:

- The product is too vague to identify the user, problem, or category
- The user has strict naming constraints that were not provided
- The request materially depends on legal trademark advice rather than naming research
