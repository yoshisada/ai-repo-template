---
name: "version"
description: "Show the current version and optionally bump a segment. Usage: /version (show), /version release, /version feature, /version pr"
---

# Version

```text
$ARGUMENTS
```

## If no arguments: show current version

```bash
VERSION=$(cat VERSION 2>/dev/null || echo "not found")
echo "$VERSION"
```

Report:

```
Version: [version]
Format: release.feature.pr.edit
```

## If argument is `release`, `feature`, or `pr`: bump that segment

```bash
./scripts/version-bump.sh [argument]
```

Report the before → after and remind to commit:

```
[old] → [new] ([segment] bump)
Remember to commit the VERSION file with your next change.
```
