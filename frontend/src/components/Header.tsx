import { useStore, useNotificationCount } from '../store'

export function Header() {
  const { connected, environment, selectedPO, selectPO, toggleBus, busOpen } =
    useStore()
  const notificationCount = useNotificationCount()

  return (
    <header className="h-14 bg-po-surface border-b border-po-border flex items-center px-4 gap-4">
      {/* Logo / Title */}
      <button
        onClick={() => selectPO(null)}
        className="text-lg font-semibold text-white hover:text-po-accent transition-colors"
      >
        PromptObjects
      </button>

      {/* Environment info */}
      {environment && (
        <div className="text-sm text-gray-400">
          <span className="text-gray-500">/</span>
          <span className="ml-2">{environment.name}</span>
          <span className="ml-3 text-gray-500">
            {environment.po_count} POs, {environment.primitive_count} primitives
          </span>
        </div>
      )}

      {/* Breadcrumb for selected PO */}
      {selectedPO && (
        <div className="text-sm text-gray-400">
          <span className="text-gray-500">/</span>
          <span className="ml-2 text-po-accent">{selectedPO}</span>
        </div>
      )}

      <div className="flex-1" />

      {/* Connection status */}
      <div className="flex items-center gap-2 text-sm">
        <div
          className={`w-2 h-2 rounded-full ${
            connected ? 'bg-green-500' : 'bg-red-500'
          }`}
        />
        <span className="text-gray-400">
          {connected ? 'Connected' : 'Disconnected'}
        </span>
      </div>

      {/* Notification badge */}
      {notificationCount > 0 && (
        <div className="bg-po-warning text-black text-xs font-bold px-2 py-1 rounded-full">
          {notificationCount}
        </div>
      )}

      {/* Message Bus toggle */}
      <button
        onClick={toggleBus}
        className={`px-3 py-1.5 text-sm rounded transition-colors ${
          busOpen
            ? 'bg-po-accent text-white'
            : 'bg-po-border text-gray-300 hover:bg-po-accent/50'
        }`}
      >
        Bus
      </button>
    </header>
  )
}
