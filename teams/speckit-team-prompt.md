# Speckit Pipeline — Agent Team Prompt

Paste this into a fresh `claude` session from the `ai-repo-template/` directory.

---

## Prompt

```
Create an agent team to run a spec-first development pipeline for this repo. The pipeline has 4 phases, each with an implementer and auditor. Here's the team:

Spawn 4 teammates:

1. **spec-planner** — Responsible for the front half of the pipeline:
   - Read docs/PRD.md and .specify/memory/constitution.md
   - Create a git branch for the feature
   - Generate specs/<feature>/spec.md with user stories, FRs (FR-001, FR-002...), acceptance criteria using .specify/templates/spec-template.md
   - Then generate specs/<feature>/plan.md, research.md, data-model.md, contracts/interfaces.md, quickstart.md using .specify/templates/plan-template.md and .specify/templates/interfaces-template.md
   - Then resolve any external dependencies referenced in the PRD (clone starters to vendor/)
   - Then generate specs/<feature>/tasks.md with phased task breakdown using .specify/templates/tasks-template.md
   - Finally, git commit all spec artifacts
   - Message the phase-1-2-implementer when done with the feature name and branch

2. **phase-1-2-implementer** — Waits for spec-planner, then:
   - Read specs/<feature>/tasks.md and contracts/interfaces.md
   - Implement Phase 1 (Setup) tasks: write code matching contract signatures exactly, add // FR-NNN comments, write tests, mark tasks [X], commit
   - Then implement Phase 2 (Foundational) tasks with same rules, commit
   - Message the auditor after each phase is committed

3. **phase-3-4-implementer** — Waits for auditor to approve phases 1-2, then:
   - Implement Phase 3 (User Stories) tasks, commit
   - Implement Phase 4 (Polish & cross-cutting) tasks, commit
   - Run the full test suite
   - Message the auditor when done

4. **auditor** — Reviews and verifies after each implementation phase:
   - After phases 1-2: verify FR comments exist in code, signatures match contracts/interfaces.md, tests reference acceptance scenarios, tests aren't stubs. Fix gaps or document in specs/<feature>/blockers.md. Message phase-3-4-implementer to proceed.
   - After phases 3-4: do the same audit, then run a FULL PRD compliance audit (bidirectional: PRD->Spec and Spec->Code->Test). Then do a smoke test: build the project, run it in a temp dir, verify it works. Report PASS/FAIL.
   - Finally: push the branch and create a PR with gh pr create

Require plan approval for spec-planner before they start writing specs — I want to review the approach.

Important rules for ALL teammates:
- Read .specify/memory/constitution.md before any code changes — its principles are NON-NEGOTIABLE
- Every exported function MUST match specs/<feature>/contracts/interfaces.md exactly
- Mark tasks [X] in tasks.md IMMEDIATELY after completing each one
- Commit after each phase, not in one big batch
- No async unless the contract says async. No any types. Concrete types only.
- Coverage gate: >=80%
```
