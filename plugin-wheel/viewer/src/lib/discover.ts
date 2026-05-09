import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

export interface DiscoveredWorkflow {
  name: string
  description: string
  path: string
  source: 'local' | 'plugin'
  plugin?: string
  stepCount: number
  steps: unknown[]
  localOverride: boolean
  // FR-6.3 — discovery origin tag mirrors `Workflow.discoveryMode`.
  // Omitted on legacy callers; set to 'installed' / 'source' by the
  // discoverPluginWorkflows path that produces the entry. See FR-6.1, FR-6.2.
  discoveryMode?: 'installed' | 'source' | 'local'
}

function homeDir(): string {
  return os.homedir()
}

function validateWorkflow(json: unknown): json is { name: string; steps: unknown[]; description?: string } {
  if (typeof json !== 'object' || json === null) return false
  return 'name' in json && 'steps' in json
}

function readWorkflowFile(filePath: string): DiscoveredWorkflow | null {
  try {
    const content = fs.readFileSync(filePath, 'utf8')
    const parsed = JSON.parse(content)
    if (!validateWorkflow(parsed)) return null
    return {
      name: parsed.name,
      description: parsed.description || '',
      path: filePath,
      source: 'local',
      stepCount: Array.isArray(parsed.steps) ? parsed.steps.length : 0,
      steps: parsed.steps,
      localOverride: false,
    }
  } catch {
    return null
  }
}

function isSubdirectory(parent: string, child: string): boolean {
  const relative = path.relative(parent, child)
  return !relative.startsWith('..') && !path.isAbsolute(relative)
}

export function discoverLocalWorkflows(projectPath: string): DiscoveredWorkflow[] {
  const workflowsDir = path.join(projectPath, 'workflows')
  if (!fs.existsSync(workflowsDir)) return []

  const workflows: DiscoveredWorkflow[] = []
  const seenNames = new Set<string>()

  // Recursively find all .json files under workflows/
  function scanDir(dir: string) {
    const entries = fs.readdirSync(dir, { withFileTypes: true })
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        if (isSubdirectory(workflowsDir, fullPath)) {
          scanDir(fullPath)
        }
      } else if (entry.name.endsWith('.json')) {
        // Compute relative path from workflows/ to get subfolder name
        const relPath = path.relative(workflowsDir, fullPath)
        const parts = relPath.split(path.sep)
        const baseName = entry.name.replace(/\.json$/, '')

        // If in a subdirectory, prepend subfolder to name
        let wfName = baseName
        if (parts.length > 1) {
          wfName = `${parts[0]}/${baseName}`
        }

        if (seenNames.has(wfName)) continue
        seenNames.add(wfName)

        const wf = readWorkflowFile(fullPath)
        if (!wf) continue
        wf.name = wfName
        workflows.push(wf)
      }
    }
  }

  scanDir(workflowsDir)
  return workflows
}

function discoverPluginWorkflowsFromDir(
  installPath: string,
  pluginName: string,
): DiscoveredWorkflow[] {
  const workflows: DiscoveredWorkflow[] = []
  const manifestPath = path.join(installPath, '.claude-plugin', 'plugin.json')
  const wfDir = path.join(installPath, 'workflows')
  const seenNames = new Set<string>()

  // Source 1: explicit manifest entries
  if (fs.existsSync(manifestPath)) {
    try {
      const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
      if (Array.isArray(manifest.workflows)) {
        for (const wfRelPath of manifest.workflows) {
          const wfAbsPath = path.join(installPath, wfRelPath)
          const wf = readWorkflowFile(wfAbsPath)
          if (wf) {
            wf.plugin = pluginName
            workflows.push(wf)
            seenNames.add(wf.name)
          }
        }
      }
    } catch {
      // skip invalid manifest
    }
  }

  // Source 2: auto-scan workflows/ directory
  if (fs.existsSync(wfDir)) {
    const files = fs.readdirSync(wfDir, { withFileTypes: true })
    for (const entry of files) {
      const filePath = path.join(wfDir, entry.name)

      if (entry.isDirectory()) {
        // Scan subdirectory workflows
        const subFiles = fs.readdirSync(filePath).filter(f => f.endsWith('.json'))
        for (const file of subFiles) {
          const subFilePath = path.join(filePath, file)
          const wfName = `${entry.name}/${file.replace(/\.json$/, '')}`
          if (seenNames.has(wfName)) continue
          const wf = readWorkflowFile(subFilePath)
          if (wf) {
            wf.name = wfName
            wf.plugin = pluginName
            workflows.push(wf)
            seenNames.add(wfName)
          }
        }
      } else if (entry.name.endsWith('.json')) {
        const wfName = entry.name.replace(/\.json$/, '')
        if (seenNames.has(wfName)) continue
        const wf = readWorkflowFile(filePath)
        if (wf) {
          wf.plugin = pluginName
          workflows.push(wf)
          seenNames.add(wfName)
        }
      }
    }
  }

  return workflows
}

export function discoverPluginWorkflows(): DiscoveredWorkflow[] {
  const installedPluginsPath = path.join(homeDir(), '.claude', 'plugins', 'installed_plugins.json')
  if (!fs.existsSync(installedPluginsPath)) return []

  try {
    const installed = JSON.parse(fs.readFileSync(installedPluginsPath, 'utf8'))
    const plugins = installed.plugins as Record<string, Array<{ installPath: string }>>
    const allWorkflows: DiscoveredWorkflow[] = []

    for (const [pluginFullName, entries] of Object.entries(plugins)) {
      const pluginShort = pluginFullName.split('@')[0]
      for (const entry of entries) {
        const workflows = discoverPluginWorkflowsFromDir(entry.installPath, pluginShort)
        allWorkflows.push(...workflows)
      }
    }

    return allWorkflows
  } catch {
    return []
  }
}

export function discoverFeedbackLoops(projectPath: string): {
  kilnInstalled: boolean
  loops: unknown[]
} {
  const loopsDir = path.join(projectPath, 'docs', 'feedback-loop')
  if (!fs.existsSync(loopsDir)) {
    return { kilnInstalled: false, loops: [] }
  }

  const files = fs.readdirSync(loopsDir).filter(f => f.endsWith('.json'))
  const loops = []

  for (const file of files) {
    try {
      const content = fs.readFileSync(path.join(loopsDir, file), 'utf8')
      loops.push(JSON.parse(content))
    } catch {
      // skip invalid loop files
    }
  }

  return { kilnInstalled: true, loops }
}

export function getLocalWorkflow(
  name: string,
  projectPath: string,
): DiscoveredWorkflow | null {
  // Try direct match first
  const directPath = path.join(projectPath, 'workflows', `${name}.json`)
  if (fs.existsSync(directPath)) {
    const wf = readWorkflowFile(directPath)
    if (wf) wf.name = name
    return wf
  }

  // Try subdirectory match (e.g. "subdir/workflow-name")
  const parts = name.split('/')
  if (parts.length === 2) {
    const subPath = path.join(projectPath, 'workflows', parts[0], `${parts[1]}.json`)
    if (fs.existsSync(subPath)) {
      const wf = readWorkflowFile(subPath)
      if (wf) wf.name = name
      return wf
    }
  }

  // Try with "workflows/" prefix stripped (for nested paths)
  if (name.startsWith('workflows/')) {
    const rest = name.slice('workflows/'.length)
    return getLocalWorkflow(rest, projectPath)
  }

  return null
}