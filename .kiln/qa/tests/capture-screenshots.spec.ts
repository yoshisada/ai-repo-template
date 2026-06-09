/**
 * Acceptance-screenshot presence gate for wheel-viewer-definition-quality.
 *
 * The PRD's load-bearing acceptance gate is "all 12 screenshots committed,"
 * not "automated screenshot tests pass." Capture is performed by
 * `.kiln/qa/tests/capture.mjs` (Node ESM, drives Playwright directly via
 * the `playwright` runtime dep already in `viewer/package.json`). That
 * script runs out-of-band against a live dev server, produces the canonical
 * deliverable PNGs under `specs/wheel-viewer-definition-quality/screenshots/`,
 * and exits non-zero if any AC fails.
 *
 * This @playwright/test spec is the green/red gate that `/kiln:kiln-qa-final`
 * invokes — it asserts the 12 PNGs exist and are non-empty. It does NOT
 * re-capture (that would race the live dev server); it verifies the
 * out-of-band artifact landed.
 *
 * For end-to-end re-capture: `node .kiln/qa/tests/capture.mjs all`.
 */
import { test, expect } from '@playwright/test'
import * as fs from 'fs'
import * as path from 'path'

const REPO_ROOT = path.resolve(__dirname, '../../..')
const SHOT_DIR = path.join(REPO_ROOT, 'specs/wheel-viewer-definition-quality/screenshots')

const REQUIRED_SHOTS: ReadonlyArray<readonly [string, string]> = [
  ['AC-1', '01-auto-layout-team-static.png'],
  ['AC-2', '02-auto-layout-team-static-expanded.png'],
  ['AC-3', '03-auto-layout-branch.png'],
  ['AC-4', '04-team-step-rendering.png'],
  ['AC-5', '05-search.png'],
  ['AC-6', '06-filter.png'],
  ['AC-7', '07-lint-clean.png'],
  ['AC-8', '08-lint-errors.png'],
  ['AC-9', '09-diff.png'],
  ['AC-10', '10-source-discovery.png'],
  ['AC-11', '11-empty-no-projects.png'],
  ['AC-12', '12-empty-no-workflows.png'],
]

for (const [ac, file] of REQUIRED_SHOTS) {
  test(`${ac} screenshot present at ${file}`, () => {
    const p = path.join(SHOT_DIR, file)
    expect(fs.existsSync(p), `Missing acceptance screenshot: ${p}. Run: node .kiln/qa/tests/capture.mjs ${ac.replace('AC-', '')}`).toBe(true)
    const stat = fs.statSync(p)
    expect(stat.size, `Screenshot ${file} is empty`).toBeGreaterThan(1024)
    // PNG magic-byte sanity check
    const fd = fs.openSync(p, 'r')
    const buf = Buffer.alloc(8)
    fs.readSync(fd, buf, 0, 8, 0)
    fs.closeSync(fd)
    expect(buf[0]).toBe(0x89)
    expect(buf[1]).toBe(0x50) // P
    expect(buf[2]).toBe(0x4e) // N
    expect(buf[3]).toBe(0x47) // G
  })
}
