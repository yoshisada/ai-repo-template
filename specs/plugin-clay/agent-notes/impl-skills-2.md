# Implementer Friction Notes: create-prd + create-repo (impl-skills-2)

## What went well
- Reference implementations (kiln's create-prd, founder-prd, github-repo-prd, kiln's create-repo) were comprehensive and well-structured. The merge was straightforward.
- The contracts/interfaces.md clearly defined the skill frontmatter convention and product status derivation logic, making it easy to align create-repo's .repo-url marker with clay-list/clay-sync expectations.
- Templates between kiln and founder-prd were identical — no conflict resolution needed.

## Friction points
- **Spec wasn't ready when assigned**: Task #4 was assigned before task #1 completed. The spec directory existed but was empty. I pre-read all reference implementations while waiting, which let me start quickly once specs appeared.
- **Mode label ambiguity**: The spec (FR-016) defines modes as "Mode A (new product PRD), Mode B (feature addition), Mode C (PRD-only repo)" but the plan says "Mode A (no existing product), Mode B (existing product mentioned), Mode C (explicit PRD-only workspace request)". These are slightly inconsistent. I chose pragmatic labels: Mode A = Product Collection (default, outputs to products/), Mode B = Single-Product Repo (outputs to docs/), Mode C = Feature Addition. The behaviors are functionally equivalent to the spec's intent.
- **FR-020 (incorporate research/naming)**: This FR was easy to miss since it's about reading upstream artifacts, not generating output. Had to add it after initial implementation.

## Decisions made
- Made Mode A (product collection) the default mode, since clay's convention is products/<slug>/. Mode B (single-product repo outputting to docs/) is the exception for repos with src/ directories.
- Added one-at-a-time question flow to create-repo (matching create-prd's pattern) rather than kiln's original "ask all in one message" approach. This is a UX improvement.
- Included submodule/monorepo mode in create-repo (carried over from kiln) since it's a useful capability for multi-project setups.
- create-repo writes a .repo-url marker file back to the source products/<slug>/ directory, enabling clay-list and clay-sync to detect "repo-created" status.

## Time: ~10 minutes active implementation
