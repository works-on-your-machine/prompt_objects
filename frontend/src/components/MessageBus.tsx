import { useRef, useEffect } from 'react'
import { useStore } from '../store'

export function MessageBus() {
  const { busMessages, toggleBus } = useStore()
  const messagesEndRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [busMessages])

  return (
    <div className="h-full flex flex-col">
      <div className="flex items-center justify-between p-3 border-b border-po-border">
        <h3 className="font-medium text-white">Message Bus</h3>
        <button
          onClick={toggleBus}
          className="text-gray-400 hover:text-white transition-colors"
        >
          ✕
        </button>
      </div>

      <div className="flex-1 overflow-auto p-3 space-y-2">
        {busMessages.length === 0 ? (
          <div className="text-gray-500 text-sm text-center py-4">
            No messages yet
          </div>
        ) : (
          busMessages.map((msg, index) => (
            <div
              key={index}
              className="text-xs bg-po-bg rounded p-2 border border-po-border"
            >
              <div className="flex items-center gap-2 mb-1">
                <span className="text-po-accent font-medium">{msg.from}</span>
                <span className="text-gray-500">→</span>
                <span className="text-po-warning font-medium">{msg.to}</span>
                <span className="text-gray-600 ml-auto">
                  {new Date(msg.timestamp).toLocaleTimeString()}
                </span>
              </div>
              <div className="text-gray-300 break-words">
                {(() => {
                  const text = msg.summary || (typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content))
                  return text.length > 200 ? text.slice(0, 200) + '...' : text
                })()}
              </div>
            </div>
          ))
        )}
        <div ref={messagesEndRef} />
      </div>
    </div>
  )
}
