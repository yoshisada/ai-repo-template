---
title: Test PRD
blast_radius: isolated
empirical_quality: [{metric: time, direction: lower, priority: primary}, {metric: tokens, direction: equal_or_better, priority: secondary}]
---

# Test PRD

This is a synthetic PRD used by `research-runner-axis-direction-pass/run.sh` to
verify SC-AE-001. The frontmatter declares two axes: `time` (must improve) and
`tokens` (must hold flat). The runner enforces both via per-axis direction.
