import { defineConfig } from '@playwright/test';

// QA config for wheel-viewer-definition-quality.
// baseURL points at Path A (Next.js dev server, port 3000) by default.
// For Path B (Docker on port 3847), override via DEV_URL env var.
export default defineConfig({
  testDir: '../tests',
  outputDir: '../results/test-results',
  fullyParallel: true,
  timeout: 30000,
  retries: 1,
  reporter: [
    ['html', { outputFolder: '../results/reports', open: 'never' }],
    ['json', { outputFile: '../results/results.json' }],
    ['list'],
  ],
  use: {
    baseURL: process.env.DEV_URL || 'http://localhost:3000',
    video: 'retain-on-failure',
    trace: 'retain-on-failure',
    screenshot: 'on',
    headless: true,
    viewport: { width: 1440, height: 900 },
  },
  projects: [
    {
      name: 'desktop-chrome',
      use: { browserName: 'chromium' },
    },
  ],
});
