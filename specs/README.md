# Feature Specifications

Every feature requires three artifacts before implementation can begin.

## Workflow

1. **Specify**: Create `specs/<feature>/spec.md` — user stories, FRs, success criteria
2. **Plan**: Create `specs/<feature>/plan.md` — technical approach, phases, file list
3. **Tasks**: Create `specs/<feature>/tasks.md` — ordered task breakdown referencing FRs
4. Commit all three artifacts
5. **Implement**: Write code referencing FRs in comments
6. **Test**: Write tests referencing acceptance scenarios
7. **Verify**: Tests pass, >=80% coverage, build succeeds

## Enforcement

Claude Code hooks block `src/` edits until **all three artifacts** exist:
- `spec.md` — run `/speckit.specify`
- `plan.md` — run `/speckit.plan`
- `tasks.md` — run `/speckit.tasks`

This is intentional. Complete the workflow before writing code.

## Templates

- Spec: `.specify/templates/spec-template.md`
- Plan: `.specify/templates/plan-template.md`
- Tasks: `.specify/templates/tasks-template.md`
