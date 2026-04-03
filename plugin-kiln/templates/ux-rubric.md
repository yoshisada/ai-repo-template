# UX Visual Design Rubric

10-dimension scoring system for evaluating visual design quality from screenshots. Used by the ux-evaluator agent in Layer 3 (Visual Analysis).

## Scoring Tiers

Dimensions are grouped by LLM evaluation reliability. Tier weights compensate for accuracy differences.

| Tier | Dimensions | Weight | Accuracy |
|------|-----------|--------|----------|
| **A — High confidence** | D1-D5 | ×1.5 | Concrete, measurable attributes |
| **B — Medium confidence** | D6-D8 | ×1.0 | Structured judgment required |
| **C — Lower confidence** | D9-D10 | ×0.75 | Flag for human review |

## Overall Score Formula

```
Tier A avg = (D1 + D2 + D3 + D4 + D5) / 5
Tier B avg = (D6 + D7 + D8) / 3
Tier C avg = (D9 + D10) / 2

Overall = (Tier A avg × 1.5 + Tier B avg × 1.0 + Tier C avg × 0.75) / (1.5 + 1.0 + 0.75) × 10 / 10
```

Result is a score from 1-10.

## Letter Grade Mapping

| Score | Grade |
|-------|-------|
| 9.0-10.0 | A+ |
| 8.0-8.9 | A |
| 7.0-7.9 | B |
| 6.0-6.9 | C |
| 5.0-5.9 | D |
| Below 5.0 | F |

## Tier A — High Confidence Dimensions

### D1: Spacing Consistency

| Score | Description |
|-------|-------------|
| 1 | No consistent padding or margins. Elements crammed together or randomly spread with no rhythm. |
| 3 | Some attempt at spacing but inconsistent. Mix of tight and loose areas on the same page. |
| 5 | Mostly consistent spacing with 1-2 visible inconsistencies per page. Adequate breathing room. |
| 7 | Consistent spacing scale used throughout. Minor deviations only in edge cases. |
| 10 | Pixel-perfect rhythm. Consistent spacing scale (e.g., 4/8/16/24px). Breathing room everywhere. Whitespace used intentionally to create focus. |

### D2: Typography Hierarchy

| Score | Description |
|-------|-------------|
| 1 | Single font size throughout. No heading differentiation. Body text hard to read. |
| 3 | Some size variation but no clear hierarchy. Inconsistent line-heights or font weights. |
| 5 | Clear h1/h2/h3 differentiation. Body text readable. Minor line-height or weight inconsistencies. |
| 7 | Well-defined type scale. Good line-height (1.4-1.6 body). Consistent weight usage across pages. |
| 10 | Distinct type scale with clear purpose for each level. Proper line-height. Consistent weight usage. Max 2-3 font families. Type creates clear information hierarchy. |

### D3: Color Consistency

| Score | Description |
|-------|-------------|
| 1 | Random colors with no coherent palette. Clashing hues. No semantic meaning to color choices. |
| 3 | Loosely related colors but no clear system. Some functional use (red for errors) but inconsistent. |
| 5 | Recognizable palette with 1-2 off-brand or inconsistent colors. Functional color use present. |
| 7 | Cohesive palette. Semantic color usage (success/error/warning). Minor shade inconsistencies. |
| 10 | Cohesive palette of 3-5 colors plus neutrals. Semantic color usage throughout. Consistent opacity and shade variants. Color reinforces hierarchy and meaning. |

### D4: Alignment & Grid

| Score | Description |
|-------|-------------|
| 1 | Elements visually scattered. No apparent grid or alignment system. |
| 3 | Some alignment but frequent breaks. Elements drift from grid on multiple pages. |
| 5 | Most elements follow a grid. 1-2 alignment breaks per page. Gutters mostly consistent. |
| 7 | Strong grid adherence. Rare alignment breaks, only in complex layouts. |
| 10 | Everything sits on a clear grid. Consistent gutters. No orphaned elements. Baseline alignment where applicable. |

### D5: Responsive Adaptation

| Score | Description |
|-------|-------------|
| 1 | Layout breaks at tablet or mobile. Horizontal overflow. Hidden or inaccessible content. |
| 3 | Basic adaptation but major issues — awkward stacking, lost content, broken navigation. |
| 5 | Layout adapts at breakpoints. Minor spacing or stacking order issues at some viewports. |
| 7 | Graceful adaptation. Touch targets appropriate. Content reflows logically. Minor polish issues. |
| 10 | Graceful breakpoints. Touch targets scale properly. Content reflows logically. No horizontal scroll. Navigation adapts (e.g., hamburger menu). |

## Tier B — Medium Confidence Dimensions

### D6: Visual Hierarchy

| Score | Description |
|-------|-------------|
| 1 | All elements have the same visual weight. No focal point. User doesn't know where to look. |
| 3 | Some differentiation but competing focal points. Multiple elements fight for attention. |
| 5 | Primary CTA distinguishable. General flow exists but some competing elements. |
| 7 | Clear primary and secondary hierarchy. Good scanning path. Minimal competing elements. |
| 10 | Clear scanning path (F or Z pattern). Progressive disclosure. Single focal point per section. Most important element draws the eye first. |

### D7: Component Consistency

| Score | Description |
|-------|-------------|
| 1 | Same function rendered differently across pages. Mixed button styles, card styles, input styles. |
| 3 | Some consistency within pages but drift across pages. 2-3 variants of the same component. |
| 5 | Mostly consistent components with minor variations (e.g., slightly different padding on similar cards). |
| 7 | Uniform components throughout. Rare inconsistencies only in specialized contexts. |
| 10 | Uniform components everywhere. Buttons, cards, inputs, navigation all follow one design language. Feels like a design system. |

### D8: Information Density

| Score | Description |
|-------|-------------|
| 1 | Walls of text or completely empty pages. No content structure or grouping. |
| 3 | Content exists but poorly organized. Some sections overwhelm, others feel barren. |
| 5 | Reasonable density. Some sections feel slightly cramped or sparse. Adequate grouping. |
| 7 | Well-balanced density. Content grouped into logical sections. Whitespace separates groups. |
| 10 | Content grouped into scannable chunks. Whitespace balances density. No cognitive overload. Progressive disclosure for complex information. |

## Tier C — Lower Confidence Dimensions (flag for human review)

### D9: Visual Polish

| Score | Description |
|-------|-------------|
| 1 | Missing borders, inconsistent border-radii, broken or mismatched shadows, mixed icon styles. |
| 3 | Basic styling present but rough. Inconsistent radii, shadow depths vary without purpose. |
| 5 | Consistent border-radius and shadows. Minor icon style mixing. Acceptable for early-stage product. |
| 7 | Polished details. Consistent radii, shadows, and icon set. Minor refinement opportunities. |
| 10 | Cohesive detail system. Consistent radii, shadow depth, icon set. Micro-interactions feel intentional. Professional finish throughout. |

### D10: Visual Feedback States

| Score | Description |
|-------|-------------|
| 1 | No hover, focus, or active states visible. No loading indicators. No disabled state styling. |
| 3 | Some hover states on primary buttons. No loading feedback. Disabled states indistinguishable. |
| 5 | Hover states on primary interactive elements. Some loading feedback. Basic disabled styling. |
| 7 | Good state coverage. Most interactive elements show hover/focus/active. Loading indicators present. |
| 10 | All interactive elements show hover/focus/active/disabled states. Skeleton loaders or spinners for async. Smooth transitions between states. |

## Scoring Rules

1. **Score relative to project stage.** Read the project's spec or constitution to determine stage. A prototype at 6/10 is acceptable; a production app at 6/10 is a problem.
2. **Tier C dimensions must include `[CONFIDENCE: LOW — verify manually]`** in all findings.
3. **When scoring with a reference**, the app cannot score higher than the reference on a dimension where the reference is objectively better.
4. **When scoring without a reference**, use the rubric anchors as absolute guides.
5. **Pairwise comparison procedure** (when reference available): For each dimension, describe the reference first, then the app, then score the gap.
6. **One sentence justification required** for every score. No unjustified numbers.

## Finding Thresholds

| Score | Action |
|-------|--------|
| 1-4 | Send detailed `VISUAL [dimension]` finding to qa-reporter with severity critical (1-2) or major (3-4) |
| 5-6 | Note in rubric scorecard. No separate finding unless regression from baseline. |
| 7-10 | Note in rubric scorecard only. |
| Baseline delta ≥ -2 | Send `VISUAL REGRESSION` finding regardless of absolute score |
