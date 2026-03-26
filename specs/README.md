# Feature Specifications

Every feature gets a spec before implementation.

## Workflow

1. Create a directory: `specs/<feature-name>/`
2. Write `spec.md` using the template at `.specify/templates/spec-template.md`
3. Include: user stories, acceptance scenarios, FRs, success criteria
4. Commit the spec before writing any code
5. Implement, referencing FRs in comments
6. Write tests, referencing acceptance scenarios

## Enforcement

Claude Code hooks in `.claude/settings.json` will **block edits to `src/`** if no spec exists in this directory. This is intentional — write the spec first.

## Template

See `.specify/templates/spec-template.md` for the full template.
