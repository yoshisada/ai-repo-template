# Data Model: Kiln Polish

## QA Directory Manifest

The canonical `.kiln/qa/` structure for all kiln-managed projects:

```text
.kiln/qa/
├── README.md              # Documents the directory layout (FR-008)
├── tests/                 # Playwright test stubs and specs
│   └── *.spec.ts
├── results/               # All QA output: reports, test results, traces
│   ├── QA-REPORT.md
│   ├── QA-PASS-REPORT.md
│   ├── UX-REPORT.md
│   ├── test-results.json
│   └── traces/
├── screenshots/           # Screenshots from QA agents and UX evaluator
│   ├── desktop/
│   └── reference/
├── videos/                # Playwright video recordings
├── config/                # QA configuration files
│   ├── playwright.config.ts
│   ├── test-matrix.md
│   ├── .env.test.example
│   └── .env.test          # (gitignored — user credentials)
├── .env.test              # Legacy location (gitignored)
└── playwright.config.ts   # Legacy location (kept for backwards compat)
```

### Directory Purposes

| Directory | Contents | Written by |
|-----------|----------|------------|
| `tests/` | Playwright test stubs (`.spec.ts`) | `/qa-setup` |
| `results/` | Reports, JSON results, traces | `/qa-pass`, `/qa-pipeline`, qa-reporter agent |
| `screenshots/` | PNG screenshots at various viewports | qa-engineer agent, ux-evaluator agent |
| `videos/` | WebM video recordings of test runs | Playwright (automatic) |
| `config/` | Playwright config, test matrix, env templates | `/qa-setup` |

## Suggested Next Command

Not a persistent entity — derived at runtime from the priority-sorted recommendation list produced by `/next` Step 4. The first item in the sorted list becomes the suggested command.

Format: `Suggested next: /command — reason`
