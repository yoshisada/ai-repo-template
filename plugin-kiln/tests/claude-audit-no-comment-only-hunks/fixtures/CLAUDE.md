# CLAUDE.md (fixture — claude-audit-no-comment-only-hunks)

This fixture is a CLAUDE.md known to fire the `external/length-density` rule:
verbose, low-density, and full of mechanics that don't teach the project's
thesis. The audit MUST emit a concrete diff for every fired signal — comment-only
"No diff proposed pending maintainer call" hunks are forbidden per FR-001 / FR-002
of `claude-audit-quality`.

## What This Repo Is

This is a project. It does things. There is code in `src/`. Tests live in
`tests/`. We use TypeScript. We use npm. We use git.

## Build & Development

```bash
npm install
npm test
npm run build
npm run lint
npm run format
npm run dev
npm run start
npm run docs
npm run release
```

## Architecture

```
src/
├── index.ts
├── lib/
│   ├── a.ts
│   ├── b.ts
│   ├── c.ts
│   ├── d.ts
│   ├── e.ts
│   ├── f.ts
│   ├── g.ts
│   ├── h.ts
│   └── i.ts
└── utils/
    ├── one.ts
    ├── two.ts
    └── three.ts
```

## Workflow

1. Read the constitution
2. Write a spec
3. Write a plan
4. Write tasks
5. Implement
6. Test
7. Audit
8. Commit
9. Open a PR
10. Merge
11. Deploy
12. Monitor

## Available Commands

- /one
- /two
- /three
- /four
- /five
- /six
- /seven
- /eight
- /nine
- /ten
- /eleven
- /twelve
- /thirteen
- /fourteen
- /fifteen

## Versioning

Format: `release.feature.pr.edit` — `000.000.000.000`

## Security

- Don't commit secrets.
- Don't commit credentials.
- Don't commit API keys.
- Don't commit .env files.
- Don't commit private keys.

## Active Technologies

- TypeScript 5.x
- npm 10.x
- Node 20.x
- Jest 29.x
- ESLint 8.x
- Prettier 3.x

## Recent Changes

- Updated dependencies.
- Fixed a bug.
- Added a feature.
- Refactored a module.
- Improved documentation.
- Cleaned up tests.
- Bumped version.
