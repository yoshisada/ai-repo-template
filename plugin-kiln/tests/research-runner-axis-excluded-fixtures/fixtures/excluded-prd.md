---
title: Excluded fixtures PRD
blast_radius: isolated
empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}]
excluded_fixtures: [{path: 002-flaky, reason: "intermittent stream-json shape drift"}]
---

PRD with one excluded fixture. Isolated blast → min_fixtures=3, with 1 of 4
fixtures excluded → 3 active fixtures meets the floor exactly.
