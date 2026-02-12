import { useState, useCallback, useRef, useEffect } from 'react'
import { useStore, usePONotifications } from '../../store'
import { useWebSocket } from '../../hooks/useWebSocket'

interface Props {
  poName: string
}

const statusColors: Record<string, string> = {
  idle: 'bg-gray-500',
  thinking: 'bg-po-accent animate-pulse',
  calling_tool: 'bg-po-warning animate-pulse',
}

export function POInspector({ poName }: Props) {
  const po = useStore((s) => s.promptObjects[poName])
  const notifications = usePONotifications(poName)
  const { updatePrompt, respondToNotification } = useWebSocket()
  const { selectPO, setCurrentView } = useStore()

  if (!po) {
    return (
      <div className="p-4 text-gray-500 text-sm">
        Prompt Object "{poName}" not found.
      </div>
    )
  }

  return (
    <div className="p-4 space-y-5">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <h3 className="text-lg font-medium text-white">{po.name}</h3>
          <div className={`w-2 h-2 rounded-full ${statusColors[po.status] || statusColors.idle}`} />
        </div>
        <p className="text-sm text-gray-400">{po.description}</p>
        <span className="inline-block mt-1 text-xs text-gray-500 bg-po-bg px-2 py-0.5 rounded">
          {po.status}
        </span>
      </div>

      {/* Capabilities */}
      <div>
        <h4 className="text-sm font-medium text-gray-400 mb-2">
          Capabilities ({po.capabilities?.length || 0})
        </h4>
        <div className="space-y-1">
          {(po.capabilities || []).map((cap) => (
            <CapabilityItem key={cap.name} name={cap.name} description={cap.description} />
          ))}
        </div>
      </div>

      {/* Prompt */}
      <PromptSection
        prompt={po.prompt || ''}
        onSave={(prompt) => updatePrompt(poName, prompt)}
      />

      {/* Sessions */}
      <div>
        <h4 className="text-sm font-medium text-gray-400 mb-2">
          Sessions ({po.sessions?.length || 0})
        </h4>
        {po.current_session && (
          <div className="text-xs text-gray-500">
            Current: <span className="text-gray-300 font-mono">{po.current_session.id.slice(0, 8)}...</span>
            <span className="ml-2">({po.current_session.messages.length} messages)</span>
          </div>
        )}
      </div>

      {/* Notifications */}
      {notifications.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-po-warning mb-2">
            Pending Requests ({notifications.length})
          </h4>
          <div className="space-y-2">
            {notifications.map((n) => (
              <NotificationCard
                key={n.id}
                notification={n}
                onRespond={(response) => respondToNotification(n.id, response)}
              />
            ))}
          </div>
        </div>
      )}

      {/* Link to full detail */}
      <button
        onClick={() => {
          selectPO(poName)
          setCurrentView('dashboard')
        }}
        className="text-sm text-po-accent hover:underline"
      >
        Open full detail view
      </button>
    </div>
  )
}

function CapabilityItem({ name, description }: { name: string; description: string }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className="bg-po-bg border border-po-border rounded overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full px-3 py-1.5 flex items-center justify-between hover:bg-po-surface transition-colors"
      >
        <span className="font-mono text-xs text-po-accent">{name}</span>
        <span className="text-gray-500 text-xs">{expanded ? '▼' : '▶'}</span>
      </button>
      {expanded && (
        <div className="px-3 py-2 border-t border-po-border bg-po-surface">
          <p className="text-xs text-gray-400">{description}</p>
        </div>
      )}
    </div>
  )
}

function PromptSection({ prompt, onSave }: { prompt: string; onSave: (p: string) => void }) {
  const [isEditing, setIsEditing] = useState(false)
  const [edited, setEdited] = useState(prompt)
  const saveTimeoutRef = useRef<number | null>(null)

  useEffect(() => {
    if (!isEditing) setEdited(prompt)
  }, [prompt, isEditing])

  const debouncedSave = useCallback(
    (value: string) => {
      if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current)
      saveTimeoutRef.current = window.setTimeout(() => {
        if (value !== prompt) onSave(value)
      }, 1000)
    },
    [onSave, prompt]
  )

  useEffect(() => {
    return () => {
      if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current)
    }
  }, [])

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-sm font-medium text-gray-400">Prompt</h4>
        <button
          onClick={() => {
            if (isEditing && edited !== prompt) onSave(edited)
            setIsEditing(!isEditing)
          }}
          className={`text-xs px-2 py-0.5 rounded transition-colors ${
            isEditing
              ? 'bg-po-accent text-white'
              : 'bg-po-border text-gray-300 hover:text-white'
          }`}
        >
          {isEditing ? 'Done' : 'Edit'}
        </button>
      </div>
      {isEditing ? (
        <textarea
          value={edited}
          onChange={(e) => {
            setEdited(e.target.value)
            debouncedSave(e.target.value)
          }}
          className="w-full h-40 bg-po-bg border border-po-border rounded p-2 text-xs text-gray-200 font-mono resize-none focus:outline-none focus:border-po-accent"
          spellCheck={false}
        />
      ) : (
        <div className="bg-po-bg border border-po-border rounded p-2 max-h-32 overflow-auto">
          <pre className="text-xs text-gray-400 font-mono whitespace-pre-wrap">
            {prompt || '(no prompt)'}
          </pre>
        </div>
      )}
    </div>
  )
}

function NotificationCard({
  notification,
  onRespond,
}: {
  notification: { id: string; type: string; message: string; options: string[] }
  onRespond: (response: string) => void
}) {
  const [customInput, setCustomInput] = useState('')
  const [showCustom, setShowCustom] = useState(false)

  return (
    <div className="bg-po-bg border border-po-border rounded p-2">
      <span className="text-xs bg-po-warning text-black px-1.5 py-0.5 rounded font-medium">
        {notification.type}
      </span>
      <p className="text-xs text-gray-300 mt-1 mb-2">{notification.message}</p>

      {notification.options.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-1">
          {notification.options.map((opt, i) => (
            <button
              key={i}
              onClick={() => onRespond(opt)}
              className="px-2 py-1 text-xs bg-po-surface border border-po-border rounded hover:border-po-accent transition-colors"
            >
              {opt}
            </button>
          ))}
        </div>
      )}

      {showCustom ? (
        <div className="flex gap-1 mt-1">
          <input
            type="text"
            value={customInput}
            onChange={(e) => setCustomInput(e.target.value)}
            placeholder="Custom response..."
            className="flex-1 bg-po-surface border border-po-border rounded px-2 py-1 text-xs text-white placeholder-gray-500 focus:outline-none focus:border-po-accent"
            onKeyDown={(e) => {
              if (e.key === 'Enter' && customInput.trim()) {
                onRespond(customInput.trim())
                setCustomInput('')
                setShowCustom(false)
              }
            }}
            autoFocus
          />
          <button
            onClick={() => {
              if (customInput.trim()) {
                onRespond(customInput.trim())
                setCustomInput('')
                setShowCustom(false)
              }
            }}
            className="px-2 py-1 text-xs bg-po-accent text-white rounded"
          >
            Send
          </button>
        </div>
      ) : (
        <button
          onClick={() => setShowCustom(true)}
          className="text-xs text-gray-500 hover:text-white mt-1"
        >
          + Custom
        </button>
      )}
    </div>
  )
}
