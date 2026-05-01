import { NextRequest, NextResponse } from 'next/server'
import { firstProject, getProject } from '@/lib/projects'
import { discoverFeedbackLoops } from '@/lib/discover'

export async function GET(request: NextRequest) {
  const url = new URL(request.url)
  const projectId = url.searchParams.get('projectId')

  const project = projectId ? getProject(projectId) : firstProject()
  if (!project) {
    return NextResponse.json({ error: 'no project registered' }, { status: 404 })
  }

  const result = discoverFeedbackLoops(project.path)
  return NextResponse.json(result)
}
