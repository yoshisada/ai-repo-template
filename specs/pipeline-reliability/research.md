# Research: Pipeline Reliability & Health

## R1: Branch Name Parsing for Feature Scoping

**Decision**: Parse the git branch name using two patterns: `build/<feature-name>-<date>` and `<number>-<feature-name>`. Extract the feature name and look for `specs/<feature-name>/`. Fall back to `.kiln/current-feature` marker file if branch name doesn't match either pattern.

**Rationale**: Branch naming is already standardized by kiln's `/specify` and `/build-prd` skills. The two-pattern approach covers both the build-prd style (`build/pipeline-reliability-20260401`) and the sequential style (`003-my-feature`). The fallback file handles edge cases like `main`, `hotfix-*`, or custom branch names.

**Alternatives considered**:
- Only use branch name parsing (no fallback) — rejected because non-standard branch names would break gate enforcement
- Only use `.kiln/current-feature` file — rejected because it requires an extra write step and can get stale
- Use git config to store current feature — rejected as too invasive and non-standard

## R2: Implementing Lock Mechanism

**Decision**: Use a `.kiln/implementing.lock` file containing a JSON payload with `timestamp`, `feature`, and `pid`. The lock is created by the `/implement` skill on start and removed on completion (success or failure via trap). Hooks treat locks older than 30 minutes as stale and ignore them.

**Rationale**: File-based locks are simple, portable, and visible. The timestamp allows stale lock detection without external tooling. The 30-minute timeout matches the upper bound of typical implementation phases while still recovering from crashes reasonably quickly.

**Alternatives considered**:
- Environment variable — rejected because hooks run as separate shell processes and can't read parent env
- PID-based lock checking — rejected as unreliable across different systems and shell sessions
- No lock, just check if `/implement` skill is running — rejected because there's no reliable way for a hook to detect active skill execution

## R3: Hook Allowlist vs Blocklist Strategy

**Decision**: Restructure the hook to use a blocklist approach. Define a list of "implementation directories" (`src/`, `cli/`, `lib/`, `modules/`, `app/`, `components/`, `templates/`) that require gate checks. Everything else is always allowed. This inverts the current logic from "allow only known-safe paths" to "check gates only for implementation paths."

**Rationale**: The blocklist approach is more maintainable and less likely to accidentally block legitimate files. New project directories that aren't implementation code (e.g., `scripts/`, `docs/`) are allowed by default. The list of implementation directories is well-defined and rarely changes.

**Alternatives considered**:
- Keep the current allowlist and add more entries — rejected because the list grows unboundedly and misses edge cases
- Let users configure the list — rejected as too complex for initial implementation; can be added later
- Only check `src/` — rejected because many real projects use other directory names

## R4: Stall Detection Approach

**Decision**: Add stall detection instructions to the build-prd orchestrator skill prompt. The team lead monitors agent activity via task updates and messages. If an agent's task stays `in_progress` for longer than 10 minutes without any activity, the team lead sends a check-in message.

**Rationale**: Since kiln operates through Claude Code agent teams, the "orchestrator" is the team lead agent following skill instructions. Stall detection is best implemented as clear behavioral instructions rather than code, because the team lead already has visibility into task status and message flow.

**Alternatives considered**:
- Automated background polling script — rejected because there's no persistent daemon to run it; the team lead is the orchestrator
- Watchdog hook — rejected because hooks run on tool use, not on inactivity
- External monitoring service — rejected as too complex for the kiln plugin context

## R5: Docker Freshness Detection

**Decision**: For container freshness checks, compare the latest git commit SHA against the image's build label or the last recorded build SHA in `.kiln/qa/last-build-sha`. If they differ, trigger a rebuild. Detection of containerized projects uses presence of `Dockerfile` or `docker-compose.yml` in the project root.

**Rationale**: Git commit SHA is the most reliable indicator of code freshness. Storing the last build SHA in a file provides a simple comparison mechanism that doesn't require Docker image inspection.

**Alternatives considered**:
- Compare file timestamps — rejected as unreliable across different filesystems and CI environments
- Docker image metadata inspection — rejected as it requires Docker to be running and adds complexity
- Always rebuild — rejected as wasteful for projects where code hasn't changed
