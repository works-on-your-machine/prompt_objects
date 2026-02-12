import { create } from 'zustand'
import type { CanvasNodeSelection, ActiveToolCall } from './types'

interface CanvasStore {
  selectedNode: CanvasNodeSelection | null
  hoveredNode: string | null
  showLabels: boolean
  activeToolCalls: Map<string, ActiveToolCall>

  selectNode: (node: CanvasNodeSelection | null) => void
  setHoveredNode: (id: string | null) => void
  toggleLabels: () => void
  addToolCall: (tc: ActiveToolCall) => void
  updateToolCall: (id: string, update: Partial<ActiveToolCall>) => void
  removeToolCall: (id: string) => void
}

export const useCanvasStore = create<CanvasStore>((set) => ({
  selectedNode: null,
  hoveredNode: null,
  showLabels: true,
  activeToolCalls: new Map(),

  selectNode: (node) => set({ selectedNode: node }),
  setHoveredNode: (id) => set({ hoveredNode: id }),
  toggleLabels: () => set((s) => ({ showLabels: !s.showLabels })),
  addToolCall: (tc) =>
    set((s) => {
      const next = new Map(s.activeToolCalls)
      next.set(tc.id, tc)
      return { activeToolCalls: next }
    }),
  updateToolCall: (id, update) =>
    set((s) => {
      const existing = s.activeToolCalls.get(id)
      if (!existing) return s
      const next = new Map(s.activeToolCalls)
      next.set(id, { ...existing, ...update })
      return { activeToolCalls: next }
    }),
  removeToolCall: (id) =>
    set((s) => {
      const next = new Map(s.activeToolCalls)
      next.delete(id)
      return { activeToolCalls: next }
    }),
}))
