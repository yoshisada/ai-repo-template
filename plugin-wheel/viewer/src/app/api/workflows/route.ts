import { NextRequest, NextResponse } from 'next/server'
import { firstProject, getProject } from '@/lib/projects'
import {
  discoverLocalWorkflows,
  discoverPluginWorkflows,
  getLocalWorkflow,
} from '@/lib/discover'

// FR-6.1 / FR-6.2 — discoverPluginWorkflows now accepts an optional projectPath.
// Without it, we only get installed-marketplace workflows. WITH it, the function
// also scans <projectPath>/plugin-*/ for source-checkout sibling plugins and
// tags those entries with discoveryMode='source'. The Sidebar's `(source)` tag
// rendering depends on those tags reaching the client.
//
// The cache must therefore be keyed by projectPath — a `null` cache shared
// across projects would leak the first project's source-discovery results
// into every subsequent project's response (qa-engineer flagged this as
// part of AC-10's fix scope).
const pluginWorkflowCacheByPath = new Map<string, ReturnType<typeof discoverPluginWorkflows>>()

function getPluginWorkflows(projectPath: string) {
  const cached = pluginWorkflowCacheByPath.get(projectPath)
  if (cached) return cached
  const fresh = discoverPluginWorkflows(projectPath)
  pluginWorkflowCacheByPath.set(projectPath, fresh)
  return fresh
}

export async function GET(request: NextRequest) {
  const url = new URL(request.url)
  const projectId = url.searchParams.get('projectId')
  const name = url.searchParams.get('name')

  const project = projectId ? getProject(projectId) : firstProject()

  if (!project) {
    return NextResponse.json({ error: 'no project registered' }, { status: 404 })
  }

  // GET /api/workflows?name=...&projectId= (for single workflow lookup)
  if (name) {
    // Try local first
    const localWf = getLocalWorkflow(name, project.path)
    if (localWf) return NextResponse.json(localWf)

    // Try plugin workflows (look up by full name like "shelf:shelf-propose-manifest-improvement")
    const pluginWfs = getPluginWorkflows(project.path)
    const pluginWf = pluginWfs.find(wf => wf.name === name || wf.name === name.split(':')[1])
    if (pluginWf) return NextResponse.json(pluginWf)

    return NextResponse.json({ error: 'workflow not found' }, { status: 404 })
  }

  // GET /api/workflows?projectId=
  const local = discoverLocalWorkflows(project.path)
  const plugin = getPluginWorkflows(project.path)
  return NextResponse.json({ local, plugin })
}
