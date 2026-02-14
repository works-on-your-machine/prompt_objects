import { useRef, useEffect, useState } from 'react'
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
          busMessages.map((msg, index) => (
            <TranscriptRow key={index} msg={msg} />
          ))
        )}
        <div ref={messagesEndRef} />
      </div>
    </div>
  )
}

function TranscriptRow({ msg }: { msg: { from: string; to: string; content: string | Record<string, unknown>; summary?: string; timestamp: string } }) {
  const [expanded, setExpanded] = useState(false)
  const fullText = msg.summary || (typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content, null, 2))
  const isLong = fullText.length > 120
  const truncated = isLong ? fullText.slice(0, 120) + '...' : fullText

  return (
    <div>
      <div
        onClick={() => isLong && setExpanded(!expanded)}
        className={`text-2xs leading-relaxed flex items-baseline gap-1.5 ${isLong ? 'cursor-pointer hover:bg-po-surface-2' : ''} ${expanded ? 'bg-po-surface-2' : ''}`}
      >
        <span className="text-po-text-ghost flex-shrink-0 whitespace-nowrap">
          {new Date(msg.timestamp).toLocaleTimeString('en-US', { hour12: false })}
        </span>
        <span className="text-po-accent flex-shrink-0">{msg.from}</span>
        <span className="text-po-text-ghost">{'\u2192'}</span>
        <span className="text-po-status-calling flex-shrink-0">{msg.to}</span>
        {!expanded && (
          <span className="text-po-text-secondary truncate">{truncated}</span>
        )}
        {isLong && (
          <span className="text-po-text-ghost flex-shrink-0 ml-auto">{expanded ? '\u25BC' : '\u25B8'}</span>
        )}
      </div>
      {expanded && (
        <pre className="text-2xs text-po-text-secondary whitespace-pre-wrap break-all pl-[4.5rem] pb-1.5 bg-po-surface-2 rounded-b mb-0.5">
          {fullText}
        </pre>
      )}
    </div>
  )
}
