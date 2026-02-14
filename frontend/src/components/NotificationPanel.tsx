import { useState } from 'react'
import { useStore } from '../store'

interface NotificationPanelProps {
  respondToNotification: (id: string, response: string) => void
}

export function NotificationPanel({ respondToNotification }: NotificationPanelProps) {
  const { notifications, selectPO } = useStore()

  if (notifications.length === 0) return null

  return (
    <div className="fixed bottom-4 right-4 w-96 max-h-[60vh] overflow-auto bg-po-surface-2 border border-po-warning/30 rounded-lg shadow-2xl z-50">
      {/* Header */}
      <div className="sticky top-0 bg-po-surface-2 border-b border-po-border px-3 py-2 flex items-center gap-2">
        <div className="w-2 h-2 rounded-full bg-po-warning animate-pulse" />
        <span className="text-xs font-medium text-po-text-primary flex-1">
          Pending Requests ({notifications.length})
        </span>
      </div>

      {/* Notifications */}
      <div className="p-2 space-y-2">
        {notifications.map((notification) => (
          <NotificationCard
            key={notification.id}
            notification={notification}
            onRespond={(response) => respondToNotification(notification.id, response)}
            onViewPO={() => selectPO(notification.po_name)}
          />
        ))}
      </div>
    </div>
  )
}

interface NotificationCardProps {
  notification: {
    id: string
    po_name: string
    type: string
    message: string
    options: string[]
  }
  onRespond: (response: string) => void
  onViewPO: () => void
}

function NotificationCard({ notification, onRespond, onViewPO }: NotificationCardProps) {
  const [customInput, setCustomInput] = useState('')
  const [showCustom, setShowCustom] = useState(false)

  const handleCustomSubmit = () => {
    if (customInput.trim()) {
      onRespond(customInput.trim())
      setCustomInput('')
      setShowCustom(false)
    }
  }

  return (
    <div className="bg-po-surface border border-po-border rounded-lg p-3">
      {/* Header: type badge + PO name */}
      <div className="flex items-center gap-2 mb-2">
        <span className="text-2xs font-mono bg-po-warning text-po-bg px-1.5 py-0.5 rounded font-bold">
          {notification.type}
        </span>
        <button
          onClick={onViewPO}
          className="text-xs font-mono text-po-accent hover:underline"
        >
          {notification.po_name}
        </button>
      </div>

      {/* Message */}
      <p className="text-xs text-po-text-primary mb-3">{notification.message}</p>

      {/* Quick response options */}
      {notification.options.length > 0 && (
        <div className="flex flex-wrap gap-1.5 mb-2">
          {notification.options.map((option, index) => (
            <button
              key={index}
              onClick={() => onRespond(option)}
              className="px-2.5 py-1 text-xs bg-po-surface-2 border border-po-border rounded hover:border-po-accent hover:text-po-accent transition-colors duration-150 text-po-text-secondary"
            >
              {option}
            </button>
          ))}
        </div>
      )}

      {/* Custom response */}
      {showCustom ? (
        <div className="flex gap-1.5">
          <input
            type="text"
            value={customInput}
            onChange={(e) => setCustomInput(e.target.value)}
            placeholder="Custom response..."
            className="flex-1 bg-po-surface-2 border border-po-border rounded px-2 py-1 text-xs text-po-text-primary placeholder-po-text-ghost focus:outline-none focus:border-po-accent"
            onKeyDown={(e) => e.key === 'Enter' && handleCustomSubmit()}
            autoFocus
          />
          <button
            onClick={handleCustomSubmit}
            className="px-2 py-1 text-xs bg-po-accent text-po-bg rounded font-medium hover:bg-po-accent-muted transition-colors duration-150"
          >
            Send
          </button>
          <button
            onClick={() => setShowCustom(false)}
            className="text-po-text-ghost hover:text-po-text-secondary transition-colors duration-150"
          >
            {'\u2715'}
          </button>
        </div>
      ) : (
        <button
          onClick={() => setShowCustom(true)}
          className="text-2xs text-po-text-ghost hover:text-po-text-secondary transition-colors duration-150"
        >
          + Custom response
        </button>
      )}
    </div>
  )
}
