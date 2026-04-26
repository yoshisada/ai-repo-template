# Constitution (fixture — claude-audit-editorial-pass-required)

## Article IV — The Four Gates

The hook system enforces four gates on every code edit:

1. **Spec gate**: a feature spec MUST exist at `specs/<feature>/spec.md` before any `src/` edit.
2. **Plan gate**: a plan MUST exist at `specs/<feature>/plan.md` before any `src/` edit.
3. **Tasks gate**: a task list MUST exist at `specs/<feature>/tasks.md` before any `src/` edit.
4. **Progress gate**: at least one task in `tasks.md` MUST be marked `[X]` before any further `src/` edit.

The four-gate enforcement is non-negotiable. Hooks block writes that violate the gates; do not bypass them.

## Article VIII — Incremental Task Completion

Mark each task `[X]` IMMEDIATELY after completing it — not in a batch at the end. Commit after each phase, not in one giant commit at the end.
