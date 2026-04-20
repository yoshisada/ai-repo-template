# validate-non-compiled.sh regex missing plugin-shelf/

**Source**: GitHub #115 (manifest-improvement retrospective), auditor friction note
**Priority**: high
**Suggested command**: `/fix validate-non-compiled.sh regex doesn't include plugin-shelf — emits 7 false-positive "file reference not found" errors on every pre-PR run`
**Tags**: [auto:continuance]

## Description

`scripts/validate-non-compiled.sh` knows `plugin-kiln` and `plugin-wheel` in its path regex but was never updated for `plugin-shelf`. Every pre-PR validator run on shelf changes produces 7 false red flags. Not blocking, but desensitizes maintainers to real validator output. Surfaced in the manifest-improvement pipeline audit.
