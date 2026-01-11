import { useStore, useSelectedPO, usePONotifications } from '../store'
import { ChatPanel } from './ChatPanel'
import { SessionsPanel } from './SessionsPanel'
import { CapabilitiesPanel } from './CapabilitiesPanel'

interface PODetailProps {
  sendMessage: (target: string, content: string) => void
  createSession: (target: string, name?: string) => void
  switchSession: (target: string, sessionId: string) => void
}

export function PODetail({
  sendMessage,
  createSession,
  switchSession,
}: PODetailProps) {
  const { activeTab, setActiveTab, selectPO } = useStore()
  const po = useSelectedPO()
  const notifications = usePONotifications(po?.name || '')

  if (!po) {
    return (
      <div className="h-full flex items-center justify-center text-gray-500">
        Select a Prompt Object
      </div>
    )
  }

  const tabs = [
    { id: 'chat' as const, label: 'Chat' },
    { id: 'sessions' as const, label: `Sessions (${po.sessions?.length || 0})` },
    { id: 'capabilities' as const, label: `Capabilities (${po.capabilities?.length || 0})` },
  ]

  return (
    <div className="h-full flex flex-col">
      {/* PO Header */}
      <div className="border-b border-po-border bg-po-surface px-4 py-3">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <button
              onClick={() => selectPO(null)}
              className="text-gray-400 hover:text-white transition-colors"
            >
              ← Back
            </button>
            <h2 className="text-lg font-semibold text-white">{po.name}</h2>
            {notifications.length > 0 && (
              <span className="bg-po-warning text-black text-xs font-bold px-2 py-0.5 rounded-full">
                {notifications.length} pending
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 text-sm">
            <StatusIndicator status={po.status} />
          </div>
        </div>
        <p className="text-sm text-gray-400">{po.description}</p>
      </div>

      {/* Tabs */}
      <div className="border-b border-po-border bg-po-surface px-4">
        <div className="flex gap-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px ${
                activeTab === tab.id
                  ? 'text-po-accent border-po-accent'
                  : 'text-gray-400 border-transparent hover:text-white'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Tab content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'chat' && (
          <ChatPanel po={po} sendMessage={sendMessage} />
        )}
        {activeTab === 'sessions' && (
          <SessionsPanel
            po={po}
            createSession={createSession}
            switchSession={switchSession}
          />
        )}
        {activeTab === 'capabilities' && <CapabilitiesPanel po={po} />}
      </div>
    </div>
  )
}

function StatusIndicator({ status }: { status: string }) {
  const config = {
    idle: { color: 'bg-gray-500', label: 'Idle' },
    thinking: { color: 'bg-po-accent animate-pulse', label: 'Thinking...' },
    calling_tool: { color: 'bg-po-warning animate-pulse', label: 'Calling tool...' },
  }[status] || { color: 'bg-gray-500', label: status }

  return (
    <div className="flex items-center gap-2">
      <div className={`w-2 h-2 rounded-full ${config.color}`} />
      <span className="text-gray-400">{config.label}</span>
    </div>
  )
}
