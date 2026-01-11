import { usePromptObjects, useStore, usePONotifications } from '../store'
import { POCard } from './POCard'
import type { PromptObject } from '../types'

interface DashboardProps {
  compact?: boolean
}

export function Dashboard({ compact = false }: DashboardProps) {
  const promptObjects = usePromptObjects()

  if (promptObjects.length === 0) {
    return (
      <div className="h-full flex items-center justify-center text-gray-500">
        <div className="text-center">
          <div className="text-4xl mb-4">🔮</div>
          <div className="text-lg">No Prompt Objects loaded</div>
          <div className="text-sm mt-2">
            Waiting for environment to connect...
          </div>
        </div>
      </div>
    )
  }

  // Compact mode: simple list for sidebar
  if (compact) {
    return (
      <div className="p-2 space-y-1">
        {promptObjects.map((po) => (
          <CompactPOItem key={po.name} po={po} />
        ))}
      </div>
    )
  }

  // Full dashboard view
  return (
    <div className="h-full overflow-auto p-6">
      <h1 className="text-2xl font-semibold text-white mb-6">
        Prompt Objects
      </h1>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {promptObjects.map((po) => (
          <POCard key={po.name} po={po} />
        ))}
      </div>
    </div>
  )
}

function CompactPOItem({ po }: { po: PromptObject }) {
  const { selectPO, selectedPO } = useStore()
  const notifications = usePONotifications(po.name)
  const isSelected = selectedPO === po.name

  const statusColors = {
    idle: 'bg-gray-500',
    thinking: 'bg-po-accent animate-pulse',
    calling_tool: 'bg-po-warning animate-pulse',
  }

  return (
    <button
      onClick={() => selectPO(po.name)}
      className={`w-full text-left px-3 py-2 rounded transition-colors flex items-center gap-2 ${
        isSelected
          ? 'bg-po-accent/20 border border-po-accent'
          : 'hover:bg-po-bg border border-transparent'
      }`}
    >
      <div className={`w-2 h-2 rounded-full flex-shrink-0 ${statusColors[po.status]}`} />
      <span className={`flex-1 truncate text-sm ${isSelected ? 'text-white' : 'text-gray-300'}`}>
        {po.name}
      </span>
      {notifications.length > 0 && (
        <span className="bg-po-warning text-black text-xs font-bold px-1.5 py-0.5 rounded-full">
          {notifications.length}
        </span>
      )}
    </button>
  )
}
