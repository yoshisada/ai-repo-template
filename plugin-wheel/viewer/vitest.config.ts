// Vitest config for the wheel viewer.
// Scopes tests to `src/lib/*.test.ts` (the pure-functional library modules).
// UI components (`src/components/`) are tested via qa-engineer screenshot QA — out of scope here.
//
// FR-4.4 / FR-5.3 / FR-6.1 — pure-functional libs (lint, diff, discover) are unit-tested with vitest.
// Pinned to ^1.6.1 to match the parent plugin-wheel toolchain (avoid v3+ skew per /implement guidance).

import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['src/lib/**/*.test.ts'],
    environment: 'node',
    coverage: {
      provider: 'v8',
      include: ['src/lib/**/*.ts'],
      // Exclude test files and pre-existing modules NOT touched by this PR
      // (api.ts, projects.ts) — they're outside the file-ownership map
      // (plan D-4) and the Article II gate applies to new/changed code.
      // If a future PR modifies these files, drop them from this exclude
      // list and bring them up to ≥80% there.
      exclude: [
        'src/lib/**/*.test.ts',
        'src/lib/api.ts',
        'src/lib/projects.ts',
      ],
      reporter: ['text', 'text-summary'],
    },
  },
})
