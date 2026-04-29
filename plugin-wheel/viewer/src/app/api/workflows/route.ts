import { NextRequest, NextResponse } from 'next/server'
import { firstProject, getProject } from '@/lib/projects'
import { discoverLocalWorkflows, discoverPluginWorkflows, getLocalWorkflow } from '@/lib/discover'

let pluginWorkflowCache: ReturnType<typeof discoverPluginWorkflows> | null = null

function getPluginWorkflows() {
  if (!pluginWorkflowCache) {
    pluginWorkflowCache = discoverPluginWorkflows()
  }
  return pluginWorkflowCache
}

export async function GET(request: NextRequest) {
  const url = new URL(request.url)
  const projectId = url.searchParams.get('projectId')
  const name = url.searchParams.get('name')

  let project = projectId ? getProject(projectId) : firstProject()

  if (!project) {
    return NextResponse.json({ error: 'no project registered' }, { status: 404 })
  }

  // GET /api/workflows?name=...&projectId= (for single workflow lookup)
  if (name) {
    // Try local first
    const localWf = getLocalWorkflow(name, project.path)
    if (localWf) return NextResponse.json(localWf)

    // Try plugin workflows (look up by full name like "shelf:shelf-propose-manifest-improvement")
    const pluginWfs = getPluginWorkflows()
    const pluginWf = pluginWfs.find(wf => wf.name === name || wf.name === name.split(':')[1])
    if (pluginWf) return NextResponse.json(pluginWf)

    return NextResponse.json({ error: 'workflow not found' }, { status: 404 })
  }

  // GET /api/workflows?projectId=
  const local = discoverLocalWorkflows(project.path)
  const plugin = getPluginWorkflows()
  return NextResponse.json({ local, plugin })
}