// Canvas-specific type definitions

export interface CanvasNodeSelection {
  type: 'po' | 'toolcall'
  id: string
}

export interface ActiveToolCall {
  id: string
  toolName: string
  callerPO: string
  params: Record<string, unknown>
  status: 'active' | 'completed' | 'error'
  result?: string
  startedAt: number
  completedAt?: number
}

export interface ActiveMessageArc {
  id: string
  from: string
  to: string
  timestamp: number
}
