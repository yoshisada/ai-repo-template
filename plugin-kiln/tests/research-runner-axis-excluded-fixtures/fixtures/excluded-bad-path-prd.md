---
title: Excluded path not in corpus
blast_radius: isolated
empirical_quality: [{metric: tokens, direction: equal_or_better, priority: primary}]
excluded_fixtures: [{path: 999-nonexistent, reason: "this fixture isn't in the corpus"}]
---

PRD referencing an excluded path that doesn't exist in the corpus → loud-failure.
