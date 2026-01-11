import type { PromptObject } from '../types'

interface SessionsPanelProps {
  po: PromptObject
  createSession: (target: string, name?: string) => void
  switchSession: (target: string, sessionId: string) => void
}

export function SessionsPanel({
  po,
  createSession,
  switchSession,
}: SessionsPanelProps) {
  const sessions = po.sessions || []
  const currentSessionId = po.current_session?.id

  const handleNewSession = () => {
    const name = prompt('Session name (optional):')
    createSession(po.name, name || undefined)
  }

  return (
    <div className="h-full overflow-auto p-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-white">Sessions</h3>
        <button
          onClick={handleNewSession}
          className="px-3 py-1.5 bg-po-accent text-white text-sm rounded hover:bg-po-accent/80 transition-colors"
        >
          + New Session
        </button>
      </div>

      {sessions.length === 0 ? (
        <div className="text-gray-500 text-center py-8">
          No sessions yet. Start a conversation to create one.
        </div>
      ) : (
        <div className="space-y-2">
          {sessions.map((session) => (
            <button
              key={session.id}
              onClick={() => switchSession(po.name, session.id)}
              className={`w-full text-left p-3 rounded-lg border transition-colors ${
                session.id === currentSessionId
                  ? 'bg-po-accent/20 border-po-accent'
                  : 'bg-po-surface border-po-border hover:border-po-accent/50'
              }`}
            >
              <div className="flex items-center justify-between mb-1">
                <span className="font-medium text-white">
                  {session.name || `Session ${session.id.slice(0, 8)}`}
                </span>
                {session.id === currentSessionId && (
                  <span className="text-xs bg-po-accent text-white px-2 py-0.5 rounded">
                    Active
                  </span>
                )}
              </div>
              <div className="text-sm text-gray-400">
                {session.message_count} messages
                {session.updated_at && (
                  <span className="ml-2">
                    • {new Date(session.updated_at).toLocaleDateString()}
                  </span>
                )}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
