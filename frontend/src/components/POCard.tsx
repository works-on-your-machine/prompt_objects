import { useStore, usePONotifications } from '../store'
import type { PromptObject } from '../types'

interface POCardProps {
  po: PromptObject
}

export function POCard({ po }: POCardProps) {
  const { selectPO } = useStore()
  const notifications = usePONotifications(po.name)

  const statusColors = {
    idle: 'bg-gray-500',
    thinking: 'bg-po-accent animate-pulse',
    calling_tool: 'bg-po-warning animate-pulse',
  }

  const statusLabels = {
    idle: 'Idle',
    thinking: 'Thinking...',
    calling_tool: 'Calling tool...',
  }

  return (
    <button
      onClick={() => selectPO(po.name)}
      className="bg-po-surface border border-po-border rounded-lg p-4 text-left hover:border-po-accent transition-colors group"
    >
      <div className="flex items-start justify-between mb-2">
        <h3 className="font-medium text-white group-hover:text-po-accent transition-colors">
          {po.name}
        </h3>
        <div className="flex items-center gap-2">
          {notifications.length > 0 && (
            <span className="bg-po-warning text-black text-xs font-bold px-1.5 py-0.5 rounded-full">
              {notifications.length}
            </span>
          )}
          <div
            className={`w-2 h-2 rounded-full ${statusColors[po.status]}`}
            title={statusLabels[po.status]}
          />
        </div>
      </div>

      <p className="text-sm text-gray-400 line-clamp-2 mb-3">
        {po.description || 'No description'}
      </p>

      <div className="flex items-center justify-between text-xs text-gray-500">
        <span>{po.capabilities?.length || 0} capabilities</span>
        <span>{po.sessions?.length || 0} sessions</span>
      </div>
    </button>
  )
}
