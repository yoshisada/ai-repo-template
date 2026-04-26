## When to use

Reach for trim when the user wants design and code to stay aligned across a Penpot file and a code repo — pulling a design into framework-appropriate code, pushing code components back into Penpot, detecting drift between the two, or running a fresh redesign that preserves information architecture. It's the right tool any time the answer to *"is the design what's shipped?"* needs to be verifiable, not assumed.

## Key feedback loop

Trim's loop is bidirectional drift detection: pull and push keep the two surfaces converging, diff and verify surface where they've drifted, and a tracked component library plus user flows make the convergence checkable rather than vibes-based. The visual-verification step closes the loop — rendered code is compared against the design via screenshots, so "looks right to me" stops being the standard.

## Non-obvious behavior

- The tracked component library is the source of identity for cross-surface mapping; once a component is registered, both pull and push update it in place rather than creating a duplicate. Manually creating parallel components in either surface produces drift the diff can detect but not auto-resolve.
- User flows are first-class artifacts, not just QA scaffolding — they drive verification, exported tests, and redesign scope. Skipping flow definition makes verify-and-redesign degrade to ad-hoc screenshotting.
- Trim depends on the Penpot MCP being reachable; if it isn't, design-side skills degrade rather than failing the calling pipeline. Code-side state stays consistent regardless.
