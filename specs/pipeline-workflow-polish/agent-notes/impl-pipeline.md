# Agent Friction Notes: impl-pipeline

## What went well
- Clear task breakdown with no file ownership conflicts between impl-pipeline and impl-tooling
- Sequential phase execution (2 -> 3 -> 4 -> 6) on shared files (build-prd SKILL.md, implement SKILL.md) worked cleanly
- Contracts/interfaces.md provided unambiguous guidance for each FR's placement and content

## Friction points
- The build-prd SKILL.md file is very large (700+ lines). Reading it required multiple offset/limit passes, which slowed initial orientation. Consider splitting into sections or extracting long agent prompt templates into separate files.
- The version-increment hook auto-fires on every Edit/Write, so tasks.md got modified between reads during implementation. This is a known behavior but causes "file modified since read" errors that require re-reading.

## Suggestions
- The build-prd SKILL.md could benefit from a table of contents or section anchors given its size
- FR-005 (spec directory naming) was added to the specifier prompt inside a code block. If the specifier is running /specify which has its own directory-creation logic, there may be a tension between the specifier prompt's instruction and the /specify skill's branch-numbering logic. This should be tested in a real pipeline run.
