import { useState, useCallback, useRef, useEffect } from 'react'
import { useStore, usePONotifications } from '../../store'
import { useWebSocket } from '../../hooks/useWebSocket'

interface Props {
  poName: string
}

const statusColors: Record<string, string> = {
  idle: 'bg-po-status-idle',
  thinking: 'bg-po-status-active animate-pulse',
  calling_tool: 'bg-po-status-calling animate-pulse',
}

export function POInspector({ poName }: Props) {
  const po = useStore((s) => s.promptObjects[poName])
  const notifications = usePONotifications(poName)
  const { updatePrompt, respondToNotification } = useWebSocket()
  const { selectPO, setCurrentView } = useStore()

  if (!po) {
    return (
      <div className="p-4 text-po-text-ghost text-xs font-mono">
        Prompt Object "{poName}" not found.
      </div>
    )
  }

  return (
    <div className="p-4 space-y-5">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <h3 className="text-sm font-mono font-medium text-po-text-primary">{po.name}</h3>
          <div className={`w-2 h-2 rounded-full ${statusColors[po.status] || statusColors.idle}`} />
        </div>
        <p className="text-xs text-po-text-secondary">{po.description}</p>
        <span className="inline-block mt-1 text-2xs text-po-text-ghost bg-po-surface-2 px-1.5 py-0.5 rounded font-mono">
          {po.status}
        </span>
      </div>

      {/* Capabilities */}
      <div>
        <h4 className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider mb-2">
          Capabilities ({po.capabilities?.length || 0})
        </h4>
        <div className="space-y-1">
          {(po.capabilities || []).map((cap) => {
            // Handle both string (legacy broadcast) and object formats
            const name = typeof cap === 'string' ? cap : cap.name
            const description = typeof cap === 'string' ? cap : cap.description
            return <CapabilityItem key={name} name={name} description={description} />
          })}
        </div>
      </div>

      {/* Prompt */}
      <PromptSection
        prompt={po.prompt || ''}
        onSave={(prompt) => updatePrompt(poName, prompt)}
      />

      {/* Sessions */}
      <div>
        <h4 className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider mb-2">
          Sessions ({po.sessions?.length || 0})
        </h4>
        {po.current_session && (
          <div className="text-xs text-po-text-tertiary">
            Current: <span className="text-po-text-secondary font-mono">{po.current_session.id.slice(0, 8)}...</span>
            <span className="ml-2">({po.current_session.messages.length} messages)</span>
          </div>
        )}
      </div>

      {/* Notifications */}
      {notifications.length > 0 && (
        <div>
          <h4 className="text-2xs font-medium text-po-warning uppercase tracking-wider mb-2">
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
        className="text-xs text-po-accent hover:underline font-mono transition-colors duration-150"
      >
        Open in browser view
      </button>
    </div>
  )
}

function CapabilityItem({ name, description }: { name: string; description: string }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className="bg-po-surface-2 border border-po-border rounded overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full px-2.5 py-1.5 flex items-center justify-between hover:bg-po-surface-3 transition-colors duration-150"
      >
        <span className="font-mono text-xs text-po-accent">{name}</span>
        <span className="text-po-text-ghost text-xs">{expanded ? '\u25BC' : '\u25B8'}</span>
      </button>
      {expanded && (
        <div className="px-2.5 py-2 border-t border-po-border bg-po-surface">
          <p className="text-xs text-po-text-secondary">{description}</p>
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
        <h4 className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider">Prompt</h4>
        <button
          onClick={() => {
            if (isEditing && edited !== prompt) onSave(edited)
            setIsEditing(!isEditing)
          }}
          className={`text-2xs px-1.5 py-0.5 rounded transition-colors duration-150 ${
            isEditing
              ? 'bg-po-accent text-po-bg'
              : 'text-po-text-tertiary hover:text-po-text-primary hover:bg-po-surface-2'
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
          className="w-full h-40 bg-po-bg border border-po-border rounded p-2 text-xs text-po-text-primary font-mono resize-none focus:outline-none focus:border-po-accent"
          spellCheck={false}
        />
      ) : (
        <div className="bg-po-surface-2 border border-po-border rounded p-2 max-h-32 overflow-auto">
          <pre className="text-xs text-po-text-secondary font-mono whitespace-pre-wrap">
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
    <div className="bg-po-surface-2 border border-po-border rounded p-2">
      <span className="text-2xs font-mono bg-po-warning text-po-bg px-1.5 py-0.5 rounded font-bold">
        {notification.type}
      </span>
      <p className="text-xs text-po-text-primary mt-1.5 mb-2">{notification.message}</p>

      {notification.options.length > 0 && (
        <div className="flex flex-wrap gap-1.5 mb-1.5">
          {notification.options.map((opt, i) => (
            <button
              key={i}
              onClick={() => onRespond(opt)}
              className="px-2 py-0.5 text-xs bg-po-surface border border-po-border rounded hover:border-po-accent hover:text-po-accent transition-colors duration-150 text-po-text-secondary"
            >
              {opt}
            </button>
          ))}
        </div>
      )}

      {showCustom ? (
        <div className="flex gap-1.5 mt-1.5">
          <input
            type="text"
            value={customInput}
            onChange={(e) => setCustomInput(e.target.value)}
            placeholder="Custom response..."
            className="flex-1 bg-po-bg border border-po-border rounded px-2 py-1 text-xs text-po-text-primary placeholder-po-text-ghost focus:outline-none focus:border-po-accent"
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
            className="px-2 py-1 text-xs bg-po-accent text-po-bg rounded font-medium"
          >
            Send
          </button>
        </div>
      ) : (
        <button
          onClick={() => setShowCustom(true)}
          className="text-2xs text-po-text-ghost hover:text-po-text-secondary transition-colors duration-150 mt-1"
        >
          + Custom
        </button>
      )}
    </div>
  )
}
