import { useCanvasStore } from '../canvasStore'
import { POInspector } from './POInspector'
import { ToolCallInspector } from './ToolCallInspector'

export function InspectorPanel() {
  const selectedNode = useCanvasStore((s) => s.selectedNode)

  if (!selectedNode) return null

  return (
    <aside className="w-80 border-l border-po-border bg-po-surface overflow-hidden flex flex-col">
      <div className="p-3 border-b border-po-border flex items-center justify-between">
        <h2 className="text-sm font-medium text-gray-400">Inspector</h2>
        <button
          onClick={() => useCanvasStore.getState().selectNode(null)}
          className="text-xs text-gray-500 hover:text-white"
          title="Close inspector"
        >
          ✕
        </button>
      </div>
      <div className="flex-1 overflow-auto">
        {selectedNode.type === 'po' ? (
          <POInspector poName={selectedNode.id} />
        ) : (
          <ToolCallInspector toolCallId={selectedNode.id} />
        )}
      </div>
    </aside>
  )
}
