---
title: malformed — prd field missing
type: bug
status: prd-created
date: 2026-04-11
---

Fixture with no `prd:` field. FR-008 says: emit `needs-review` with detail "prd: field empty or points at missing file". Must NOT appear in the bundled archive block.
