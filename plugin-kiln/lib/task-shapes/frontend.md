A `frontend` task touches user-facing UI — React/Vue/Svelte components, CSS, layout,
visual interaction. The substrate is Playwright + visual snapshots driven through the
kiln QA agents (`qa-engineer`, `ux-evaluator`). Headless browser by default; live `/chrome`
when reviewing real interaction.

Report: green/red Playwright suite, screenshot diffs at the breakpoints listed in `axes`,
axe-core a11y violations, console errors observed during the flow. Never declare a
frontend task done on "I rendered the page" — declare it done on "the user flow completes
end-to-end with the screenshots matching the design intent and zero unexpected console
errors."
