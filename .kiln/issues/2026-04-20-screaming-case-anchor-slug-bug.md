# Contract anchor-slug auto-slug bug in docs mode

**Source**: GitHub #116 (kiln-setup-documentation retrospective)
**Priority**: medium
**Suggested command**: `/build-prd` — update `.specify/templates/interfaces-template.md` docs mode to require explicit `<a id="slug"></a>` tags for every Anchor Inventory entry
**Tags**: [auto:continuance]

## Description

`contracts/interfaces.md` in docs mode promises slugs like `tailscale.md#public-url`; GitHub auto-slugs SCREAMING_CASE headings to `#public_url` and multi-word ones unpredictably. 12 broken internal links shipped in PR yoshisada/obsidian-mcp#44; fixed in audit via explicit `<a id>` tags. Every implementer flagged it; none could fix it without auditor intervention. Template-level fix: require explicit anchor tags in the contract instead of relying on auto-slug.
