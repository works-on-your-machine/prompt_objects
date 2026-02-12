import { useEffect, useRef, useCallback } from 'react'
import { useStore } from '../store'
import { useCanvasStore } from './canvasStore'
import { SceneManager } from './SceneManager'
import { InspectorPanel } from './inspector/InspectorPanel'

export function CanvasView() {
  const containerRef = useRef<HTMLDivElement>(null)
  const sceneRef = useRef<SceneManager | null>(null)
  const syncScheduled = useRef(false)

  // Schedule a throttled sync via requestAnimationFrame
  const scheduleSync = useCallback(() => {
    if (syncScheduled.current) return
    syncScheduled.current = true
    requestAnimationFrame(() => {
      syncScheduled.current = false
      const scene = sceneRef.current
      if (!scene) return
      const state = useStore.getState()
      scene.syncPromptObjects(state.promptObjects)
      scene.syncBusMessages(state.busMessages)
      scene.syncNotifications(state.notifications)
    })
  }, [])

  // Mount/unmount SceneManager
  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    const scene = new SceneManager(container)
    sceneRef.current = scene

    // Initial sync
    const state = useStore.getState()
    scene.syncPromptObjects(state.promptObjects)
    scene.syncBusMessages(state.busMessages)
    scene.syncNotifications(state.notifications)
    scene.start()

    // Fit all after a short delay to let force layout settle
    const fitTimer = setTimeout(() => scene.fitAll(), 500)

    return () => {
      clearTimeout(fitTimer)
      scene.dispose()
      sceneRef.current = null
    }
  }, [])

  // Subscribe to store changes (non-React API to avoid re-renders)
  useEffect(() => {
    const unsub = useStore.subscribe(scheduleSync)
    return unsub
  }, [scheduleSync])

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'f' && !e.ctrlKey && !e.metaKey) {
        // Don't intercept when typing in an input
        if ((e.target as HTMLElement).tagName === 'INPUT' || (e.target as HTMLElement).tagName === 'TEXTAREA') return
        sceneRef.current?.fitAll()
      }
      if (e.key === 'Escape') {
        useCanvasStore.getState().selectNode(null)
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  const showLabels = useCanvasStore((s) => s.showLabels)
  const toggleLabels = useCanvasStore((s) => s.toggleLabels)

  return (
    <div className="flex-1 flex overflow-hidden relative">
      {/* Three.js container */}
      <div ref={containerRef} className="flex-1 relative" />

      {/* Toolbar overlay */}
      <div className="absolute top-3 left-3 flex gap-2 z-10">
        <button
          onClick={() => sceneRef.current?.fitAll()}
          className="px-3 py-1.5 text-sm bg-po-surface/80 backdrop-blur border border-po-border rounded hover:border-po-accent transition-colors text-gray-300 hover:text-white"
          title="Fit all nodes (F)"
        >
          Fit All
        </button>
        <button
          onClick={toggleLabels}
          className={`px-3 py-1.5 text-sm backdrop-blur border rounded transition-colors ${
            showLabels
              ? 'bg-po-accent/20 border-po-accent text-white'
              : 'bg-po-surface/80 border-po-border text-gray-300 hover:text-white'
          }`}
          title="Toggle labels"
        >
          Labels
        </button>
      </div>

      {/* Help hint */}
      <div className="absolute bottom-3 left-3 text-xs text-gray-500 z-10">
        Scroll to zoom · Shift+drag to pan · F to fit · Click node to inspect
      </div>

      {/* Inspector panel */}
      <InspectorPanel />
    </div>
  )
}
