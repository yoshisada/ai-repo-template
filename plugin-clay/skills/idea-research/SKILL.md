---
name: idea-research
description: Research a product idea — find similar projects, classify by similarity (exact match, close competitor, adjacent, slightly similar), and recommend go/no-go. Use when a user wants market research, competitor discovery, or "has this already been built?"
---

# Idea Research

Research a product idea before building so the user understands what already exists, what overlaps, and whether the idea is differentiated enough to pursue.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## When to Use

Use when the user asks to:

- research an idea, product, or startup concept
- find similar products, apps, startups, or open-source projects
- check whether something has already been built
- compare an idea against the existing market
- identify direct competitors, substitutes, or adjacent tools

Do **not** use for deep technical due diligence, financial modeling, patent searches, or generic literature reviews.

## Step 1: Understand the Idea

If `$ARGUMENTS` is empty or too vague, ask targeted follow-up questions:

- What does the product do in 1-3 sentences?
- Who is the target user?
- What is the core workflow or use case?

If `$ARGUMENTS` provides a clear 1-5 sentence idea description (FR-004), proceed directly.

Restate the idea in concrete terms before searching. Extract these comparison dimensions:

- **Primary user**: Who uses this?
- **Main problem**: What does it solve?
- **Core workflow**: What does the user actually do?
- **Business/product model**: SaaS, open source, CLI, API, etc.
- **Notable constraints or differentiators**: What makes this version distinct?

## Step 2: Derive Product Slug

If the user has not specified a product slug, derive one from the idea description:

```bash
# Convert idea to kebab-case slug (first 3-5 meaningful words)
SLUG=$(echo "$IDEA_SUMMARY" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr -s ' ' '-' | cut -d'-' -f1-5)
```

Check if `products/$SLUG/` already exists. If so, reuse it. If not, create it:

```bash
mkdir -p "products/$SLUG"
```

## Step 3: Search for Similar Projects

Use `WebSearch` to find comparable projects across these categories:

1. **Startups and commercial products** — search for the core problem + "tool", "app", "platform", "SaaS"
2. **Open-source projects** — search GitHub, Product Hunt, and package registries (npm, PyPI, crates.io as relevant)
3. **Research or prototype projects** — search for academic papers or demos if the idea is novel

Prefer current, primary sources:
- Official websites and product docs
- GitHub repositories (star count, last commit date)
- App store listings
- Reputable directories (Product Hunt, AlternativeTo, G2)

Run **at least 3 searches** with varied queries to ensure breadth. Aim for **at least 5 candidate projects** when the market appears active.

## Step 4: Classify Findings

Use exactly one label per project (FR-006):

| Label | Criteria |
|-------|----------|
| `EXACT MATCH` | Same core user, same main workflow, same value proposition. A reasonable user would see them as effectively the same product idea. |
| `CLOSE COMPETITOR` | Very similar problem and user, but differs in scope, market, platform, pricing, or execution. |
| `ADJACENT` | Solves a nearby problem, serves a related user, or overlaps in one major workflow only. |
| `SLIGHTLY SIMILAR` | Shares a keyword, feature, or market theme, but the core product is meaningfully different. |

### Exact-Match Test

Before claiming `EXACT MATCH`, verify **all four** are true:

1. The target user is materially the same
2. The main job-to-be-done is materially the same
3. The primary workflow or use case is materially the same
4. The project's positioning or promise is materially the same

If any are unclear, downgrade to `CLOSE COMPETITOR` and explain why.

**Never** call a project an `EXACT MATCH` based on name similarity, one shared feature, or shallow marketing copy alone. Explain the evidence behind the label.

## Step 5: Write the Research Report

Write the report to `products/<slug>/research.md` (FR-007).

For each finding, include (FR-008):

- **Product name** and URL
- **Description** (1-2 sentences)
- **Similarity classification** with reasoning
- **Key differentiators** from the researched idea
- **Pricing model** (free, freemium, paid, open-source) when available
- **Status** (active, stale, dead) based on last update date

Use this report structure:

```markdown
# Idea Research: <Idea Title>

**Date**: <today>
**Slug**: <slug>

## Idea Summary

<1-3 sentence restatement of the idea being researched>

## Comparison Dimensions

- **Primary user**: ...
- **Main problem**: ...
- **Core workflow**: ...
- **Product model**: ...
- **Differentiators**: ...

## Findings

### Exact Matches

<list or "None found">

### Close Competitors

<list>

### Adjacent Alternatives

<list>

### Slightly Similar

<list>

## Gap Analysis

<What seems differentiated, crowded, or still unclear>

## Recommendation

<Go/no-go recommendation based on market density and competitive landscape>

- **Market density**: Low / Medium / High
- **Differentiation opportunity**: Strong / Moderate / Weak
- **Recommendation**: GO / PROCEED WITH CAUTION / NO-GO
- **Reasoning**: <1-3 sentences>
```

## Step 6: Quality Checks

Before finishing, verify:

- [ ] At least 5 candidate projects were considered (when the market is active)
- [ ] Exact-match claims are backed by explicit reasoning against all 4 criteria
- [ ] Slightly similar projects are not overstated
- [ ] Dead or stale projects are labeled as such
- [ ] Links are included for every named project when available
- [ ] The recommendation clearly answers "Has this already been built?"
- [ ] The report is written to `products/<slug>/research.md`

## Step 7: Present Summary

After writing the file, present a concise summary to the user:

1. Restate the idea
2. How many projects were found in each category
3. Whether any exact matches exist
4. The go/no-go recommendation
5. The file path where the full report was saved

## Stop Conditions

Pause and ask for clarification if:

- The idea is too vague to determine the core product
- The user has not specified what kinds of projects count as relevant and that choice changes the search materially
- The request needs legal, investment, or patent advice rather than product research
