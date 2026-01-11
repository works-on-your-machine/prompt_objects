import { useState, useEffect, useRef } from 'react'
import { useStore, useNotificationCount } from '../store'

export function Header() {
  const { connected, environment, selectedPO, selectPO, toggleBus, busOpen, notifications } =
    useStore()
  const notificationCount = useNotificationCount()
  const [showNotifications, setShowNotifications] = useState(false)
  const [animate, setAnimate] = useState(false)
  const prevCount = useRef(notificationCount)

  // Animate badge when count increases
  useEffect(() => {
    if (notificationCount > prevCount.current) {
      setAnimate(true)
      const timer = setTimeout(() => setAnimate(false), 500)
      return () => clearTimeout(timer)
    }
    prevCount.current = notificationCount
  }, [notificationCount])

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

      {/* Notification bell with badge */}
      <div className="relative">
        <button
          onClick={() => setShowNotifications(!showNotifications)}
          className={`relative p-2 rounded transition-colors ${
            notificationCount > 0
              ? 'text-po-warning hover:bg-po-warning/20'
              : 'text-gray-400 hover:text-white hover:bg-po-border'
          }`}
          title={notificationCount > 0 ? `${notificationCount} pending requests` : 'No notifications'}
        >
          {/* Bell icon */}
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
          </svg>
          {/* Badge */}
          {notificationCount > 0 && (
            <span
              className={`absolute -top-1 -right-1 bg-po-warning text-black text-xs font-bold w-5 h-5 flex items-center justify-center rounded-full ${
                animate ? 'animate-bounce' : ''
              }`}
            >
              {notificationCount}
            </span>
          )}
        </button>

        {/* Dropdown with notification summaries */}
        {showNotifications && notifications.length > 0 && (
          <div className="absolute right-0 top-full mt-2 w-80 bg-po-surface border border-po-border rounded-lg shadow-xl z-50">
            <div className="p-3 border-b border-po-border">
              <h3 className="font-medium text-white">Pending Requests</h3>
            </div>
            <div className="max-h-64 overflow-auto">
              {notifications.map((n) => (
                <div key={n.id} className="p-3 border-b border-po-border last:border-0 hover:bg-po-bg">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-xs bg-po-warning text-black px-1.5 py-0.5 rounded font-medium">
                      {n.type}
                    </span>
                    <span className="text-xs text-po-accent">{n.po_name}</span>
                  </div>
                  <p className="text-sm text-gray-300 line-clamp-2">{n.message}</p>
                </div>
              ))}
            </div>
            <div className="p-2 border-t border-po-border">
              <p className="text-xs text-gray-500 text-center">
                Respond in the notification panel below
              </p>
            </div>
          </div>
        )}
      </div>

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
