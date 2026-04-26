## When to use

Reach for kiln when the user is doing real product work — turning ideas, feedback, captured friction, or roadmap items into spec'd, tested, audited features. It's the spec-first harness that gates implementation behind PRD → spec → plan → tasks, and it's also where loose project signal (bugs, friction, AI mistakes, product-direction ideas) gets captured for later distillation into the next PRD.

## Key feedback loop

Kiln's thesis is a closed capture-to-PRD loop: friction logged today becomes structured input that `/kiln:kiln-distill` later bundles into a feature PRD, which `/kiln:kiln-build-prd` ships. Treat capture as the canonical way to keep the system improving — items left in chat are lost; items captured land. Audit and hygiene skills run the inverse loop, surfacing drift in CLAUDE.md, the manifest, and unfiled artifacts so the system stays honest about its own state.

## Non-obvious behavior

- Implementation edits are gated by hooks, not warnings — writing `src/` without spec + plan + tasks + an `[X]`-marked task is blocked at tool-use time. The spec-less escape hatch for bug-fixing an already-specced feature is `/kiln:kiln-fix`, which uses the existing spec to satisfy the gates.
- The capture surfaces are intentionally separate (tactical issues, strategic feedback, structured roadmap, AI mistakes) — each routes differently into the loop. Don't collapse them into a single bucket.
- Audit-style skills propose diffs but never apply them; reports land in `.kiln/logs/` for human review. The propose-don't-apply discipline is load-bearing — automating "apply" would defeat the whole audit-trail design.
- A roadmap phase has exactly one in-progress slot at a time; items move `unsorted → planned → in-phase → distilled` as they become real work, not as ad-hoc tags.
