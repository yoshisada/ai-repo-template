## Coding Standards

These standards are injected into `plan` and `implement` agent prompts (via
`compose-context.sh --standards`) and enforced by the spec-enforcer + quality-judge
during audit. Edit them to match this project — they are the contract every generated
line of code is held to.

### Naming
- names are pronounceable and searchable — no abbreviations, no encodings
- one word per concept (fetch not retrieve/get/pull mixed across the codebase)
- functions named as verbs, booleans as predicates (isActive, hasPermission)
- classes/modules named as nouns describing what they ARE, not what they DO

### Functions
- do one thing at one level of abstraction
- <= 20 lines, <= 2 parameters — extract an object or split if more are needed
- no flag arguments — split into two named functions instead
- no side effects — a function that says it reads should only read

### Comments
- do not comment WHAT the code does — rename or restructure instead
- only write a comment to explain WHY: a hidden constraint, a non-obvious invariant,
  a workaround for a specific bug

### Error handling
- throw exceptions, never return null or error codes from internal functions
- never pass null — guard at system boundaries, trust contracts internally
- fail loudly at boundaries (user input, external APIs), fail silently nowhere

### Structure
- single responsibility — one reason to change per module
- small and cohesive — if you're listing unrelated methods, split it
- tell don't ask — don't reach into an object's state to make decisions for it
- no circular dependencies across layers

### Tests
- one concept per test, assertion names describe the failure
- every test references its spec FR in a comment
- no stubs on integration paths
