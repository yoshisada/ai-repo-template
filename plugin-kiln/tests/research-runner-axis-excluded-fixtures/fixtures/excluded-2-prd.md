---
title: Excluded fixtures PRD (2 excluded)
blast_radius: isolated
empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}]
excluded_fixtures: [{path: 002-flaky, reason: "noisy"}, {path: 003-active, reason: "noisy too"}]
---

PRD with 2 excluded fixtures. With 4 declared - 2 excluded = 2 active, but
isolated blast requires min_fixtures=3 → fail-fast.
