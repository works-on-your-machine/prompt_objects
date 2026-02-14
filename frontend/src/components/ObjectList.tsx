import { usePromptObjects, useStore, usePONotifications } from '../store'
import type { PromptObject } from '../types'

export function ObjectList() {
  const promptObjects = usePromptObjects()

  return (
    <aside className="h-full bg-po-surface border-r border-po-border flex flex-col overflow-hidden">
      {/* Header */}
      <div className="px-3 py-2 border-b border-po-border">
        <span className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider">
          Objects ({promptObjects.length})
        </span>
      </div>

      {/* List */}
      <div className="flex-1 overflow-auto py-1">
        {promptObjects.length === 0 ? (
          <div className="px-3 py-4 text-2xs text-po-text-ghost text-center">
            Waiting for connection...
          </div>
        ) : (
          promptObjects.map((po) => (
            <ObjectItem key={po.name} po={po} />
          ))
        )}
      </div>
    </aside>
  )
}

function ObjectItem({ po }: { po: PromptObject }) {
  const { selectPO, selectedPO } = useStore()
  const notifications = usePONotifications(po.name)
  const isSelected = selectedPO === po.name

  const isActive = po.status !== 'idle'

  const statusDot = {
    idle: 'bg-po-status-idle',
    thinking: 'bg-po-status-active',
    calling_tool: 'bg-po-status-calling',
  }[po.status] || 'bg-po-status-idle'

  const statusGlow = {
    idle: '',
    thinking: 'shadow-[0_0_5px_rgba(212,149,42,0.6)]',
    calling_tool: 'shadow-[0_0_5px_rgba(59,154,110,0.6)]',
  }[po.status] || ''

  return (
    <button
      onClick={() => selectPO(po.name)}
      className={`w-full text-left h-7 px-3 flex items-center gap-2 transition-colors duration-150 ${
        isSelected
          ? 'bg-po-accent-wash border-l-2 border-po-accent'
          : 'border-l-2 border-transparent hover:bg-po-surface-2'
      }`}
    >
      <div className={`w-2 h-2 rounded-full flex-shrink-0 ${statusDot} ${statusGlow} ${isActive ? 'animate-pulse' : ''}`} />
      <span className={`flex-1 truncate font-mono text-xs ${
        isSelected ? 'text-po-text-primary' : 'text-po-text-secondary'
      }`}>
        {po.name}
      </span>
      {po.delegated_by && (
        <span className="text-2xs text-po-status-delegated truncate max-w-[60px]">
          {po.delegated_by}
        </span>
      )}
      {notifications.length > 0 && (
        <span className="text-2xs font-mono bg-po-warning text-po-bg px-1 rounded font-bold flex-shrink-0">
          {notifications.length}
        </span>
      )}
    </button>
  )
}
