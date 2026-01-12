import { useState } from 'react'
import { useWebSocket } from './hooks/useWebSocket'
import { useStore } from './store'
import { Header } from './components/Header'
import { Dashboard } from './components/Dashboard'
import { PODetail } from './components/PODetail'
import { MessageBus } from './components/MessageBus'
import { NotificationPanel } from './components/NotificationPanel'

export default function App() {
  const { sendMessage, respondToNotification, createSession, switchSession, switchLLM } =
    useWebSocket()
  const { selectedPO, busOpen, notifications } = useStore()
  const [splitView, setSplitView] = useState(true) // Default to split view

  return (
    <div className="h-screen flex flex-col bg-po-bg">
      <Header switchLLM={switchLLM} />

      <div className="flex-1 flex overflow-hidden">
        {/* Split view: Dashboard sidebar on left when PO selected */}
        {splitView && selectedPO && (
          <aside className="w-72 border-r border-po-border bg-po-surface overflow-hidden flex flex-col">
            <div className="p-3 border-b border-po-border flex items-center justify-between">
              <h2 className="text-sm font-medium text-gray-400">Prompt Objects</h2>
              <button
                onClick={() => setSplitView(false)}
                className="text-xs text-gray-500 hover:text-white"
                title="Hide sidebar"
              >
                ✕
              </button>
            </div>
            <div className="flex-1 overflow-auto">
              <Dashboard compact />
            </div>
          </aside>
        )}

        {/* Main content */}
        <main className="flex-1 overflow-hidden flex flex-col">
          {/* Show expand button when sidebar is hidden */}
          {!splitView && selectedPO && (
            <button
              onClick={() => setSplitView(true)}
              className="absolute left-2 top-16 z-10 bg-po-surface border border-po-border rounded px-2 py-1 text-xs text-gray-400 hover:text-white hover:border-po-accent transition-colors"
              title="Show dashboard sidebar"
            >
              ☰ POs
            </button>
          )}

          {selectedPO ? (
            <PODetail
              sendMessage={sendMessage}
              createSession={createSession}
              switchSession={switchSession}
            />
          ) : (
            <Dashboard />
          )}
        </main>

        {/* Message Bus sidebar */}
        {busOpen && (
          <aside className="w-80 border-l border-po-border bg-po-surface overflow-hidden">
            <MessageBus />
          </aside>
        )}
      </div>

      {/* Notification panel */}
      {notifications.length > 0 && (
        <NotificationPanel respondToNotification={respondToNotification} />
      )}
    </div>
  )
}
