---
id: 2026-04-28-migrate-hooks-node
title: migrate hooks from bash to node for better portability
type: feedback
date: 2026-04-28
status: open
severity: medium
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-wheel/hooks/
---

migrate hooks from bash to node for better portability, need full test for this.

## Interview

### What does "done" look like for this feedback? Describe the observable outcome.

all hooks for wheel have exact node versions with comprehensive testing both smoke tested and unit testing. bash versions are still kept for reference and to compare outputs.

### Who triggers the change, and when? (ad-hoc skill, hook, background agent, part of an existing skill, human maintainer decision…)

its an update of an existing design pattern

### What's the scope? Just this repo, consumer repos too, or other plugins as well?

just the wheel-plugin in this repo

### What structural boundary or plugin shape does this change?

the wheel plugin

### What does the rollout look like — one PR, staged, or a migration?

one pr with the inital impl with addequate tests