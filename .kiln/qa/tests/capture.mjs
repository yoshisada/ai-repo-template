/**
 * Lightweight Playwright capture script for wheel-viewer-definition-quality
 * acceptance screenshots. Uses the `playwright` runtime dep already in
 * viewer/package.json — no @playwright/test needed.
 *
 * Usage:
 *   PROJECT_PATH=/path/to/repo node .kiln/qa/tests/capture.mjs <ac> [<ac>...]
 *   PROJECT_PATH=...           node .kiln/qa/tests/capture.mjs all
 *
 * Each `<ac>` is one of: 1..12. Reads/registers project once, then drives the
 * UI per AC. Exits non-zero if any requested AC's PNG isn't produced.
 *
 * Path A: assumes Next.js dev server already running on http://localhost:3000.
 */
// Resolve playwright from the viewer's node_modules (Node ESM doesn't walk NODE_PATH).
import { createRequire } from 'node:module'
const requireFromViewer = createRequire(
  new URL('../../../plugin-wheel/viewer/package.json', import.meta.url),
)
const { chromium } = requireFromViewer('playwright')
import * as fs from 'node:fs'
import * as path from 'node:path'
import * as os from 'node:os'

const REPO_ROOT = path.resolve(new URL('../../..', import.meta.url).pathname)
const SHOT_DIR = path.join(REPO_ROOT, 'specs/wheel-viewer-definition-quality/screenshots')
const PROJECT_PATH = process.env.PROJECT_PATH || REPO_ROOT
const BASE_URL = process.env.DEV_URL || 'http://localhost:3000'

const ALL_ACS = ['1','2','3','4','5','6','7','8','9','10','11','12']
const args = process.argv.slice(2)
const targets = args.length === 0 || args.includes('all') ? ALL_ACS : args

async function ensureProject() {
  // Try to register; ignore conflict by re-listing.
  const res = await fetch(`${BASE_URL}/api/projects`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: PROJECT_PATH }),
  })
  if (res.ok) {
    const p = await res.json()
    return p.id
  }
  const list = await fetch(`${BASE_URL}/api/projects`).then(r => r.json())
  const found = list.find(p => p.path === PROJECT_PATH)
  if (!found) throw new Error(`Could not register or find project at ${PROJECT_PATH}`)
  return found.id
}

async function clearProjects() {
  // Best-effort wipe — for AC-11 (no projects).
  // NOTE: the route handler reads `id` from query string (`?id=...`); api.ts client
  // uses path-param style which 404s. Defect logged for escalation; we use the
  // working query-string style here so the capture doesn't hang on stale state.
  const list = await fetch(`${BASE_URL}/api/projects`).then(r => r.json())
  for (const p of list) {
    await fetch(`${BASE_URL}/api/projects?id=${encodeURIComponent(p.id)}`, { method: 'DELETE' }).catch(() => {})
  }
}

async function shoot(page, file) {
  fs.mkdirSync(SHOT_DIR, { recursive: true })
  const out = path.join(SHOT_DIR, file)
  await page.screenshot({ path: out, fullPage: true })
  if (!fs.existsSync(out)) throw new Error(`Screenshot not written: ${out}`)
  console.log(`✓ ${file}`)
}

async function withPage(fn) {
  const browser = await chromium.launch({ headless: true })
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } })
  const page = await ctx.newPage()
  try {
    await fn(page)
  } finally {
    await ctx.close()
    await browser.close()
  }
}

const captures = {
  async '1'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    await page.getByText('tests/team-static', { exact: false }).first().click()
    await page.waitForTimeout(800) // let layout settle
    await shoot(page, '01-auto-layout-team-static.png')
  },
  async '2'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    await page.getByText('tests/team-static', { exact: false }).first().click()
    await page.waitForTimeout(800)
    // Locate the worker-1 teammate row in the RightPanel step list and click its
    // expand affordance. Per impl-shell ade5184e: each expandable row carries an
    // .expand-btn (button with title "Expand nested workflow" / "Collapse").
    const worker1Row = page.locator('.step-item').filter({ hasText: 'worker-1' }).first()
    const expandBtn = worker1Row.locator('.expand-btn').first()
    if (await expandBtn.count()) {
      await expandBtn.click()
    } else {
      // Fallback — title-based selector if class names change.
      const titled = page.getByTitle(/Expand nested workflow/i).first()
      if (await titled.count()) await titled.click()
    }
    await page.waitForTimeout(1000)
    await shoot(page, '02-auto-layout-team-static-expanded.png')
  },
  async '3'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    await page.getByText('tests/branch-multi', { exact: false }).first().click()
    await page.waitForTimeout(800)
    await shoot(page, '03-auto-layout-branch.png')
  },
  async '4'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    await page.getByText('tests/team-mixed-model', { exact: false }).first().click()
    await page.waitForTimeout(800)
    await shoot(page, '04-team-step-rendering.png')
  },
  async '5'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/?q=team-`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    // ensure search input reflects the URL param
    const search = page.locator('input[type="search"]').first()
    const v = await search.inputValue().catch(() => '')
    if (v !== 'team-') {
      await search.fill('team-')
      await page.waitForTimeout(300)
    }
    await page.waitForTimeout(400)
    await shoot(page, '05-search.png')
  },
  async '6'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/?types=branch`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    await page.waitForTimeout(500)
    await shoot(page, '06-filter.png')
  },
  async '7'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    // pick a clean workflow — tests/agent-chain has only command/agent (no team), should be lint-clean
    await page.getByText('tests/agent-chain', { exact: false }).first().click()
    await page.waitForTimeout(500)
    const lintTab = page.getByRole('tab', { name: /lint/i }).first()
    if (await lintTab.count()) await lintTab.click()
    await page.waitForTimeout(300)
    await shoot(page, '07-lint-clean.png')
  },
  async '8'(page) {
    // Local discovery only scans <projectPath>/workflows/. The lint fixture lives
    // at plugin-wheel/tests/lint-fixture-broken.json — outside any workflows/ tree.
    // Build a temp project that symlinks the fixture into a workflows/ subdir so
    // discovery can surface it. Per impl-shell instructions for AC-8.
    const tmpProject = path.join(os.tmpdir(), `wheel-view-lint-fixture-${Date.now()}`)
    const tmpWorkflows = path.join(tmpProject, 'workflows')
    fs.mkdirSync(tmpWorkflows, { recursive: true })
    const fixture = path.join(REPO_ROOT, 'plugin-wheel/tests/lint-fixture-broken.json')
    const target = path.join(tmpWorkflows, 'lint-fixture-broken.json')
    try { fs.unlinkSync(target) } catch {}
    fs.symlinkSync(fixture, target)
    await fetch(`${BASE_URL}/api/projects`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: tmpProject }),
    })
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    // Switch to the temp project (last in the list)
    const tmpProjectName = path.basename(tmpProject)
    const projItem = page.locator('.project-item').filter({ hasText: tmpProjectName }).first()
    if (await projItem.count()) await projItem.click()
    await page.waitForTimeout(500)
    await page.getByText(/lint-fixture-broken/i).first().click()
    await page.waitForTimeout(500)
    const lintTab = page.getByRole('tab', { name: /lint/i }).first()
    if (await lintTab.count()) await lintTab.click()
    await page.waitForTimeout(400)
    await shoot(page, '08-lint-errors.png')
  },
  async '9'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    const a = page.getByText('tests/team-static', { exact: false }).first()
    const b = page.getByText('tests/team-haiku-fanout', { exact: false }).first()
    await a.click({ modifiers: ['Shift'] })
    await b.click({ modifiers: ['Shift'] })
    await page.waitForTimeout(300)
    const diffBtn = page.getByRole('button', { name: /^diff$/i }).first()
    if (await diffBtn.count()) await diffBtn.click()
    await page.waitForTimeout(500)
    await shoot(page, '09-diff.png')
  },
  async '10'(page) {
    await ensureProject()
    await page.goto(`${BASE_URL}/`)
    await page.waitForSelector('input[type="search"]', { timeout: 10000 })
    await page.waitForTimeout(800)
    await shoot(page, '10-source-discovery.png')
  },
  async '11'(page) {
    await clearProjects()
    await page.goto(`${BASE_URL}/`)
    await page.waitForTimeout(500)
    await shoot(page, '11-empty-no-projects.png')
  },
  async '12'(page) {
    await clearProjects()
    const tmpProject = path.join(os.tmpdir(), `wheel-view-empty-${Date.now()}`)
    fs.mkdirSync(tmpProject, { recursive: true })
    const res = await fetch(`${BASE_URL}/api/projects`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: tmpProject }),
    })
    if (!res.ok) throw new Error(`register tmp project failed: ${res.status}`)
    await page.goto(`${BASE_URL}/`)
    await page.waitForTimeout(500)
    await shoot(page, '12-empty-no-workflows.png')
  },
}

let failed = []
await withPage(async (page) => {
  for (const ac of targets) {
    if (!captures[ac]) {
      console.error(`unknown AC: ${ac}`)
      failed.push(ac)
      continue
    }
    try {
      console.log(`→ AC-${ac}`)
      await captures[ac](page)
    } catch (e) {
      console.error(`✗ AC-${ac} failed: ${e.message}`)
      failed.push(ac)
    }
  }
})
if (failed.length) {
  console.error(`FAILED ACs: ${failed.join(', ')}`)
  process.exit(1)
}
console.log('all targets captured')
