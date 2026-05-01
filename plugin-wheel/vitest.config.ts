// FR-007 (wheel-wait-all-redesign) — vitest config.
// Pool 'forks' is required because archive-workflow.test.ts uses
// process.chdir() to scope each test to a unique cwd (archiveWorkflow
// resolves .wheel/history/<bucket> relative to cwd at runtime; the
// production hook surface inherits cwd from the calling user's session).
// Default 'threads' pool refuses chdir with ERR_WORKER_UNSUPPORTED_OPERATION.
// Forks are slower per-test but the wheel suite is small enough that the
// difference is sub-second.
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    pool: 'forks',
  },
});
