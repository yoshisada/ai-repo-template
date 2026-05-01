import { NextRequest, NextResponse } from 'next/server'
import { listProjects, registerProject, unregisterProject, getProject } from '@/lib/projects'

export async function GET() {
  return NextResponse.json(listProjects())
}

export async function POST(request: NextRequest) {
  const body = await request.json()
  if (!body.path || typeof body.path !== 'string') {
    return NextResponse.json({ error: 'missing path field' }, { status: 400 })
  }
  const project = registerProject(body.path)
  return NextResponse.json(project, { status: 201 })
}

export async function DELETE(request: NextRequest) {
  const url = new URL(request.url)
  const id = url.searchParams.get('id')
  if (!id) {
    return NextResponse.json({ error: 'missing id' }, { status: 400 })
  }
  const found = getProject(id)
  if (!found) {
    return NextResponse.json({ error: 'unknown project ID' }, { status: 404 })
  }
  unregisterProject(id)
  return new NextResponse(null, { status: 204 })
}
