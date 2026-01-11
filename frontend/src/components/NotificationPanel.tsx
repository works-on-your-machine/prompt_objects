import { useState } from 'react'
import { useStore } from '../store'

interface NotificationPanelProps {
  respondToNotification: (id: string, response: string) => void
}

export function NotificationPanel({
  respondToNotification,
}: NotificationPanelProps) {
  const { notifications, selectPO } = useStore()

  if (notifications.length === 0) return null

  return (
    <div className="fixed bottom-4 right-4 w-96 max-h-[60vh] overflow-auto bg-po-surface border border-po-border rounded-lg shadow-xl">
      <div className="sticky top-0 bg-po-surface border-b border-po-border p-3">
        <h3 className="font-medium text-white">
          Notifications ({notifications.length})
        </h3>
      </div>
      <div className="p-2 space-y-2">
        {notifications.map((notification) => (
          <NotificationCard
            key={notification.id}
            notification={notification}
            onRespond={(response) =>
              respondToNotification(notification.id, response)
            }
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

function NotificationCard({
  notification,
  onRespond,
  onViewPO,
}: NotificationCardProps) {
  const [customInput, setCustomInput] = useState('')
  const [showCustom, setShowCustom] = useState(false)

  const handleOptionClick = (option: string) => {
    onRespond(option)
  }

  const handleCustomSubmit = () => {
    if (customInput.trim()) {
      onRespond(customInput.trim())
      setCustomInput('')
      setShowCustom(false)
    }
  }

  return (
    <div className="bg-po-bg border border-po-border rounded-lg p-3">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-xs bg-po-warning text-black px-2 py-0.5 rounded font-medium">
          {notification.type}
        </span>
        <button
          onClick={onViewPO}
          className="text-xs text-po-accent hover:underline"
        >
          {notification.po_name}
        </button>
      </div>

      <p className="text-sm text-gray-200 mb-3">{notification.message}</p>

      {notification.options.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-2">
          {notification.options.map((option, index) => (
            <button
              key={index}
              onClick={() => handleOptionClick(option)}
              className="px-3 py-1.5 text-sm bg-po-surface border border-po-border rounded hover:border-po-accent transition-colors"
            >
              {option}
            </button>
          ))}
        </div>
      )}

      {showCustom ? (
        <div className="flex gap-2">
          <input
            type="text"
            value={customInput}
            onChange={(e) => setCustomInput(e.target.value)}
            placeholder="Custom response..."
            className="flex-1 bg-po-surface border border-po-border rounded px-2 py-1 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-po-accent"
            onKeyDown={(e) => e.key === 'Enter' && handleCustomSubmit()}
            autoFocus
          />
          <button
            onClick={handleCustomSubmit}
            className="px-2 py-1 text-sm bg-po-accent text-white rounded hover:bg-po-accent/80"
          >
            Send
          </button>
          <button
            onClick={() => setShowCustom(false)}
            className="px-2 py-1 text-sm text-gray-400 hover:text-white"
          >
            Cancel
          </button>
        </div>
      ) : (
        <button
          onClick={() => setShowCustom(true)}
          className="text-xs text-gray-400 hover:text-white"
        >
          + Custom response
        </button>
      )}
    </div>
  )
}
