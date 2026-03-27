# Speckit Pipeline — Agent Team Prompt

Paste this into a fresh `claude` session from your project directory (must have `.specify/` and `docs/PRD.md`).

---

## Prompt

```
Create an agent team to run a spec-first development pipeline for this repo. Read docs/PRD.md to understand the scope, then design the team.

Spawn teammates based on what the PRD needs:

1. **specifier** — Responsible for the front half of the pipeline:
   - Read docs/PRD.md and .specify/memory/constitution.md
   - Create a git branch for the feature
   - Run /speckit.specify to generate specs/<feature>/spec.md
   - Run /speckit.plan to generate plan.md, research.md, data-model.md, contracts/interfaces.md, quickstart.md
   - Resolve any external dependencies referenced in the PRD (clone starters to vendor/, verify packages)
   - Run /speckit.tasks to generate tasks.md
   - Git commit all spec artifacts
   - Message the implementers when done with the feature name and branch

2. **implementer(s)** — Wait for specifier, then:
   - Read specs/<feature>/tasks.md and contracts/interfaces.md
   - Run /speckit.implement for their assigned phases/components
   - Write code matching contract signatures exactly, add // FR-NNN comments, write tests
   - Mark tasks [X] in tasks.md immediately after each completion
   - Commit after each phase
   - Message the auditor when done

   For complex PRDs with independent components, spawn multiple implementers — one per component, each owning different files. They can work in parallel.

3. **auditor** — Waits for all implementers to finish, then:
   - Run /speckit.audit for PRD compliance (bidirectional: PRD→Spec and Spec→Code→Test)
   - Verify FR comments exist in code, signatures match contracts, tests reference acceptance scenarios, tests aren't stubs
   - Run the full test suite and verify >=80% coverage
   - Do a smoke test: build and run the project in a temp dir, verify runtime behavior
   - Fix gaps or document in specs/<feature>/blockers.md
   - Push the branch and create a PR with gh pr create
   - Report PASS/FAIL for each check

4. **retrospective** — Runs last, before shutdown:
   - Message all still-running teammates: "What friction did you hit? What would you change?"
   - Review blockers.md, git log, test results, task list for evidence
   - Create a GitHub issue on ai-repo-template with findings and proposed changes

Important rules for ALL teammates:
- Read .specify/memory/constitution.md before any code changes — its principles are NON-NEGOTIABLE
- Run the speckit slash commands (/speckit.specify, /speckit.plan, etc.) — don't reimplement their logic
- Every exported function MUST match specs/<feature>/contracts/interfaces.md exactly
- Mark tasks [X] in tasks.md IMMEDIATELY after completing each one
- Use TaskUpdate to track task progress (in_progress → completed)
- After completing a task, check TaskList for the next available work
- Message teammates by NAME when their work is unblocked
- Commit after each phase, not in one big batch
- No async unless the contract says async. No any types. Concrete types only.
- Coverage gate: >=80%
- No two teammates should edit the same file
```
