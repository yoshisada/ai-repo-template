'use client'

import { memo } from 'react'
import type { Step } from '@/lib/types'

interface SubDAGGroupNodeData {
  subWorkflowName?: string
  step?: Step
}

// FR-1.6 — Bounding-box renderer for expanded sub-workflows. The box's
// width/height come from the layout pass (lib/layout.ts emits the group
// node with computed dimensions). Children render INSIDE this box via
// React Flow's parent-child semantics (parentId + extent: 'parent').
//
// Dragging the group moves all children together. Children remain
// individually draggable within the box (extent='parent' clips them).
//
// Auto-resize on child drag is handled in FlowDiagram's onNodeDrag
// callback — when a child moves, we recompute the parent's width/height
// from the children's bounding box + padding.
function SubDAGGroupNodeComponent({ data }: { data: SubDAGGroupNodeData }) {
  const name = data.subWorkflowName ?? 'sub-workflow'
  return (
    <div className="sub-dag-group">
      <div className="sub-dag-group-title">
        <span className="sub-dag-group-title-icon">▼</span>
        <span className="sub-dag-group-title-text">{name}</span>
      </div>
    </div>
  )
}

export default memo(SubDAGGroupNodeComponent)
