import { useCanvasStore } from '../canvasStore'
import { POInspector } from './POInspector'
import { ToolCallInspector } from './ToolCallInspector'

export function InspectorPanel() {
  const selectedNode = useCanvasStore((s) => s.selectedNode)

  if (!selectedNode) return null

  return (
    <aside className="w-80 border-l border-po-border bg-po-surface overflow-hidden flex flex-col">
      <div className="h-8 bg-po-surface-2 border-b border-po-border flex items-center px-3">
        <span className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider flex-1">Inspector</span>
        <button
          onClick={() => useCanvasStore.getState().selectNode(null)}
          className="text-2xs text-po-text-ghost hover:text-po-text-secondary transition-colors duration-150"
          title="Close inspector"
        >
          {'\u2715'}
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
