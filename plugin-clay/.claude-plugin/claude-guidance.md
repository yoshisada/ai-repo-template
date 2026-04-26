## When to use

Reach for clay when the user has a raw idea or a feature ask and needs to walk it from concept to live repo — market research to confirm it's worth building, distinctive naming with availability checks, structured PRD authoring, and finally GitHub repo scaffolding seeded with the PRD artifacts. It sits at the front of the pipeline, before kiln's spec-first workflow takes over.

## Key feedback loop

Clay's output is kiln's input: a clay-created repo arrives pre-seeded with `products/<slug>/` PRD artifacts that kiln's spec/plan/tasks workflow consumes directly — no manual hand-off. Use clay when the goal is "turn this idea into a buildable thing"; switch to kiln once the repo exists and the work is feature-by-feature spec-driven implementation.

## Non-obvious behavior

- A multi-product repo (PRDs only, no code) is a first-class mode, not a degraded one — `products/<slug>/` lives alongside other product directories, and a repo can hold many PRDs before any of them get scaffolded into their own GitHub repo.
- Idea research is a go/no-go gate, not just informational — a "close competitor" or "exact match" finding is meant to redirect or kill the idea, not just be archived for completeness.
- Repo scaffolding respects existing product context: if a PRD already exists under `products/<slug>/`, the new repo is seeded from it automatically rather than starting from a blank template.
