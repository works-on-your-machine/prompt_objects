import { useWebSocket } from './hooks/useWebSocket'
import { useStore } from './store'
import { Header } from './components/Header'
import { Dashboard } from './components/Dashboard'
import { PODetail } from './components/PODetail'
import { MessageBus } from './components/MessageBus'
import { NotificationPanel } from './components/NotificationPanel'

export default function App() {
  const { sendMessage, respondToNotification, createSession, switchSession } =
    useWebSocket()
  const { selectedPO, busOpen, notifications } = useStore()

  return (
    <div className="h-screen flex flex-col bg-po-bg">
      <Header />

      <div className="flex-1 flex overflow-hidden">
        {/* Main content */}
        <main className="flex-1 overflow-hidden">
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
