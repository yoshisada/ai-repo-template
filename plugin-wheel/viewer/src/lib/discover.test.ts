// Discover module — coverage for source-checkout discovery (FR-6.1, FR-6.2).
//
// Strategy: build small fixture trees under os.tmpdir() so we don't depend on
// the real ~/.claude/plugins/installed_plugins.json or this repo's checked-in
// plugin-*/ siblings. Each test cleans up its own dir.
//
// Backwards compatibility check: when `projectPath` is omitted, behavior is
// unchanged from the prior release — only the installed_plugins.json scan
// runs. Asserted by mocking the home dir via the discoverSourcePluginWorkflows
// helper (which doesn't read the home dir at all).

import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'
import { afterEach, describe, it, expect } from 'vitest'
import {
  discoverSourcePluginWorkflows,
  discoverPluginWorkflows,
  type DiscoveredWorkflow,
} from './discover'

// --- helper: build a transient fixture project tree ---

function makeProjectTree(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wheel-discover-test-'))
  return root
}

function writePluginCheckout(
  projectPath: string,
  pluginShortName: string,
  workflowFiles: Record<string, unknown>,
): void {
  const dir = path.join(projectPath, `plugin-${pluginShortName}`)
  fs.mkdirSync(path.join(dir, '.claude-plugin'), { recursive: true })
  fs.mkdirSync(path.join(dir, 'workflows'), { recursive: true })
  fs.writeFileSync(
    path.join(dir, '.claude-plugin', 'plugin.json'),
    JSON.stringify({ name: pluginShortName, version: '1.0' }),
  )
  for (const [filename, contents] of Object.entries(workflowFiles)) {
    fs.writeFileSync(path.join(dir, 'workflows', filename), JSON.stringify(contents))
  }
}

const cleanupQueue: string[] = []
function trackCleanup(p: string): string {
  cleanupQueue.push(p)
  return p
}
afterEach(() => {
  while (cleanupQueue.length > 0) {
    const p = cleanupQueue.pop()!
    try { fs.rmSync(p, { recursive: true, force: true }) } catch {}
  }
})

// --- discoverSourcePluginWorkflows ---

describe('discoverSourcePluginWorkflows — FR-6.2', () => {
  it('returns workflows tagged discoveryMode=source from each plugin-*/ sibling', () => {
    const root = trackCleanup(makeProjectTree())
    writePluginCheckout(root, 'foo', {
      'wf-a.json': { name: 'wf-a', steps: [{ id: 's1', type: 'command' }] },
      'wf-b.json': { name: 'wf-b', steps: [] },
    })
    writePluginCheckout(root, 'bar', {
      'wf-c.json': { name: 'wf-c', steps: [{ id: 's1', type: 'agent' }] },
    })

    const wfs = discoverSourcePluginWorkflows(root)
    const names = wfs.map(w => w.name).sort()
    expect(names).toEqual(['wf-a', 'wf-b', 'wf-c'])
    for (const wf of wfs) {
      expect(wf.discoveryMode).toBe('source')
    }
    // Plugin tag preserved
    const fooWfs = wfs.filter(w => w.plugin === 'foo')
    expect(fooWfs).toHaveLength(2)
  })

  it('skips plugin-*/ siblings without .claude-plugin/plugin.json', () => {
    const root = trackCleanup(makeProjectTree())
    // Real plugin install (has manifest)
    writePluginCheckout(root, 'good', {
      'wf.json': { name: 'wf', steps: [] },
    })
    // Bare directory matching plugin-* but missing manifest — should be skipped
    const bareDir = path.join(root, 'plugin-bogus')
    fs.mkdirSync(path.join(bareDir, 'workflows'), { recursive: true })
    fs.writeFileSync(
      path.join(bareDir, 'workflows', 'wf-x.json'),
      JSON.stringify({ name: 'wf-x', steps: [] }),
    )

    const wfs = discoverSourcePluginWorkflows(root)
    expect(wfs.map(w => w.name)).toEqual(['wf'])
    // No 'plugin-bogus' workflows surface
    expect(wfs.find(w => w.plugin === 'bogus')).toBeUndefined()
  })

  it('skips plugin-*/ siblings without a workflows/ directory', () => {
    const root = trackCleanup(makeProjectTree())
    const dir = path.join(root, 'plugin-empty')
    fs.mkdirSync(path.join(dir, '.claude-plugin'), { recursive: true })
    fs.writeFileSync(
      path.join(dir, '.claude-plugin', 'plugin.json'),
      JSON.stringify({ name: 'empty' }),
    )
    // Note: no workflows/ dir created.
    const wfs = discoverSourcePluginWorkflows(root)
    expect(wfs).toEqual([])
  })

  it('returns [] when projectPath does not exist', () => {
    const fakePath = path.join(os.tmpdir(), 'wheel-discover-nonexistent-' + Date.now())
    const wfs = discoverSourcePluginWorkflows(fakePath)
    expect(wfs).toEqual([])
  })

  it('does not include directories that are not plugin-*-prefixed', () => {
    const root = trackCleanup(makeProjectTree())
    // A non-plugin sibling that should be skipped entirely
    fs.mkdirSync(path.join(root, 'docs'), { recursive: true })
    fs.writeFileSync(path.join(root, 'docs', 'wf.json'), JSON.stringify({ name: 'doc-wf', steps: [] }))
    // A real plugin checkout
    writePluginCheckout(root, 'real', {
      'wf.json': { name: 'real-wf', steps: [] },
    })

    const wfs = discoverSourcePluginWorkflows(root)
    expect(wfs.map(w => w.name)).toEqual(['real-wf'])
  })
})

// --- discoverPluginWorkflows back-compat ---

describe('discoverPluginWorkflows — FR-6.1 backwards compatibility', () => {
  it('legacy callers without projectPath get a typed array (no source scan)', () => {
    // We can't easily spoof ~/.claude/plugins/installed_plugins.json in this
    // unit test without monkey-patching os.homedir, so this is a smoke test
    // confirming the call signature still works and returns a typed array.
    const result = discoverPluginWorkflows()
    expect(Array.isArray(result)).toBe(true)
    // No source-discovered entries should appear when projectPath is omitted.
    const sourceTagged = (result as DiscoveredWorkflow[]).filter(w => w.discoveryMode === 'source')
    expect(sourceTagged).toEqual([])
  })

  it('with projectPath provided, source workflows are included alongside installed', () => {
    // FR-6.4 — both 'installed' AND 'source' versions of the same workflow may
    // be present. We can't deterministically force an 'installed' entry in a
    // unit test, so we assert the source slice is present.
    const root = trackCleanup(makeProjectTree())
    writePluginCheckout(root, 'sourceonly', {
      'unique-source-wf.json': { name: 'unique-source-wf', steps: [{ id: 's1', type: 'command' }] },
    })
    const result = discoverPluginWorkflows(root)
    const sourceTagged = result.filter(w => w.discoveryMode === 'source')
    expect(sourceTagged.map(w => w.name)).toContain('unique-source-wf')
    const sourceMatch = sourceTagged.find(w => w.name === 'unique-source-wf')!
    expect(sourceMatch.plugin).toBe('sourceonly')
  })
})
