---
type: project
status: idea
repo: "{repo_url}"
tags:
{tags_yaml}
next_step: ""
blockers: []
last_updated: "{date}"
---

# {title}

{description}

## Feedback
<!-- leave notes here — agents read and act on next session -->

## Human Needed
- [ ] Review PRD and confirm scope

## Docs
```dataview
TABLE
FROM "{base_path}/{slug}/docs"
SORT file.name ASC
```

## Releases
```dataview
TABLE version AS "Version", date AS "Date", summary AS "Summary"
FROM "{base_path}/{slug}/releases"
SORT date DESC
```

## Progress
```dataview
LIST
FROM "{base_path}/{slug}/progress"
SORT file.name DESC
LIMIT 5
```

## Open Issues
```dataview
TABLE severity AS "Severity", source AS "Source"
FROM "{base_path}/{slug}/issues"
WHERE status = "open"
SORT severity ASC
```

## Decisions
```dataview
LIST
FROM "{base_path}/{slug}/decisions"
SORT date DESC
```

## Feedback Log
<!-- processed feedback moves here with timestamps -->
