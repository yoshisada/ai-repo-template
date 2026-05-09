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
      exclude: ['src/lib/**/*.test.ts'],
      reporter: ['text', 'text-summary'],
    },
  },
})
