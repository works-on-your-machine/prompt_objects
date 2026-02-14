import { useRef, useEffect } from 'react'
import { useStore } from '../store'

export function Transcript() {
  const { busMessages, toggleBus } = useStore()
  const messagesEndRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [busMessages])

  return (
    <div className="h-full flex flex-col border-t border-po-border">
      {/* Header */}
      <div className="h-6 bg-po-surface-2 border-b border-po-border flex items-center px-3 flex-shrink-0">
        <span className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider flex-1">
          Transcript
        </span>
        <button
          onClick={toggleBus}
          className="text-2xs text-po-text-ghost hover:text-po-text-secondary transition-colors duration-150"
        >
          {'\u2715'}
        </button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-auto px-3 py-1 font-mono">
        {busMessages.length === 0 ? (
          <div className="text-2xs text-po-text-ghost text-center py-2">
            No messages
          </div>
        ) : (
          busMessages.map((msg, index) => {
            const text = msg.summary || (typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content))
            const truncated = text.length > 120 ? text.slice(0, 120) + '...' : text

            return (
              <div key={index} className="text-2xs leading-relaxed flex items-baseline gap-1.5 whitespace-nowrap">
                <span className="text-po-text-ghost flex-shrink-0">
                  {new Date(msg.timestamp).toLocaleTimeString('en-US', { hour12: false })}
                </span>
                <span className="text-po-accent flex-shrink-0">{msg.from}</span>
                <span className="text-po-text-ghost">{'\u2192'}</span>
                <span className="text-po-status-calling flex-shrink-0">{msg.to}</span>
                <span className="text-po-text-secondary truncate">{truncated}</span>
              </div>
            )
          })
        )}
        <div ref={messagesEndRef} />
      </div>
    </div>
  )
}
