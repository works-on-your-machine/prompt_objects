import { useState, useRef, useEffect } from 'react'
import { useStore } from '../store'
import { MarkdownMessage } from './MarkdownMessage'
import type { PromptObject, Message, ToolCall } from '../types'

interface WorkspaceProps {
  po: PromptObject
  sendMessage: (target: string, content: string, newThread?: boolean) => void
}

export function Workspace({ po, sendMessage }: WorkspaceProps) {
  const [input, setInput] = useState('')
  const [continueThread, setContinueThread] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const { streamingContent, connected } = useStore()

  const messages = po.current_session?.messages || []
  const streaming = streamingContent[po.name]
  const hasMessages = messages.length > 0
  const isBusy = po.status !== 'idle' && connected
  const canSend = connected && !isBusy && !!input.trim()

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, streaming])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim()) return
    const content = input.trim()
    const shouldCreateNewThread = !continueThread && hasMessages
    sendMessage(po.name, content, shouldCreateNewThread)
    setInput('')
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      if (canSend) {
        handleSubmit(e)
      }
    }
  }

  return (
    <div className="h-full flex flex-col">
      {/* Messages */}
      <div className="flex-1 overflow-auto px-4 py-2 space-y-1">
        {messages.length === 0 && !streaming && (
          <div className="h-full flex items-center justify-center">
            <span className="font-mono text-xs text-po-text-ghost">&gt; _</span>
          </div>
        )}

        {messages.map((message, index) => (
          <WorkspaceEntry key={index} message={message} />
        ))}

        {/* Streaming content */}
        {streaming && (
          <div className="py-1">
            <MarkdownMessage content={streaming} className="text-po-text-primary text-xs" />
            <span className="inline-block w-1.5 h-3.5 bg-po-accent animate-pulse ml-0.5 align-text-bottom" />
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div className="border-t border-po-border bg-po-surface-2 px-4 py-2">
        {!connected && (
          <div className="mb-1.5 text-2xs text-po-warning flex items-center gap-1.5 font-mono">
            <div className="w-1.5 h-1.5 rounded-full bg-po-warning animate-pulse" />
            reconnecting...
          </div>
        )}

        <form onSubmit={handleSubmit} className="flex items-center gap-2">
          <span className="text-po-text-ghost font-mono text-xs select-none">&gt;</span>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={!connected ? 'disconnected' : isBusy ? `${po.status.replace('_', ' ')}...` : ''}
            className="flex-1 bg-transparent text-po-text-primary font-mono text-xs placeholder-po-text-ghost focus:outline-none disabled:opacity-50"
            disabled={isBusy}
          />
        </form>

        {/* Thread toggle */}
        {hasMessages && (
          <div className="flex items-center gap-2 mt-1.5 text-2xs font-mono">
            <button
              type="button"
              onClick={() => setContinueThread(false)}
              className={`px-1.5 py-0.5 rounded transition-colors duration-150 ${
                !continueThread
                  ? 'bg-po-accent-wash text-po-accent'
                  : 'text-po-text-ghost hover:text-po-text-secondary'
              }`}
            >
              new thread
            </button>
            <button
              type="button"
              onClick={() => setContinueThread(true)}
              className={`px-1.5 py-0.5 rounded transition-colors duration-150 ${
                continueThread
                  ? 'bg-po-accent-wash text-po-accent'
                  : 'text-po-text-ghost hover:text-po-text-secondary'
              }`}
            >
              continue
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

function WorkspaceEntry({ message }: { message: Message }) {
  const isUser = message.role === 'user'
  const isAssistant = message.role === 'assistant'
  const isTool = message.role === 'tool'

  // Tool results
  if (isTool) {
    const results = message.results || []
    if (results.length === 0) return null
    return (
      <div className="space-y-1 pl-4">
        {results.map((result, idx) => (
          <ToolResultFrame key={result.tool_call_id || idx} result={result} />
        ))}
      </div>
    )
  }

  // User message: REPL-style "> message"
  if (isUser) {
    return (
      <div className="py-1">
        <span className="font-mono text-xs text-po-text-ghost select-none">&gt; </span>
        <span className="font-mono text-xs text-po-text-primary whitespace-pre-wrap">{message.content}</span>
      </div>
    )
  }

  // Assistant message: plain text with markdown
  if (isAssistant) {
    return (
      <div className="py-1">
        {message.content && (
          <MarkdownMessage content={message.content} className="text-po-text-primary text-xs" />
        )}

        {/* Tool calls as bordered frames */}
        {message.tool_calls && message.tool_calls.length > 0 && (
          <div className="mt-1 space-y-1">
            {message.tool_calls.map((tc) => (
              <ToolCallFrame key={tc.id} toolCall={tc} />
            ))}
          </div>
        )}
      </div>
    )
  }

  return null
}

function ToolCallFrame({ toolCall }: { toolCall: ToolCall }) {
  const [expanded, setExpanded] = useState(false)
  const { notifications } = useStore()

  // ask_human: amber-bordered frame
  if (toolCall.name === 'ask_human') {
    const question = toolCall.arguments.question as string
    const options = toolCall.arguments.options as string[] | undefined
    const isPending = notifications.some((n) => n.message === question)

    return (
      <div className="border-l-2 border-po-warning bg-po-accent-wash rounded-r px-3 py-2 my-1">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-2xs font-mono text-po-warning">ask_human</span>
          {isPending ? (
            <span className="text-2xs bg-po-warning text-po-bg px-1.5 py-0.5 rounded font-bold animate-pulse">
              PENDING
            </span>
          ) : (
            <span className="text-2xs bg-po-success text-po-bg px-1.5 py-0.5 rounded font-bold">
              RESOLVED
            </span>
          )}
        </div>
        <p className="text-xs text-po-text-primary mb-1.5">{question}</p>
        {options && options.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {options.map((opt, i) => (
              <span key={i} className="text-2xs font-mono bg-po-surface-2 px-1.5 py-0.5 rounded text-po-text-secondary">
                {opt}
              </span>
            ))}
          </div>
        )}
      </div>
    )
  }

  // Default tool call: bordered frame
  const argsStr = JSON.stringify(toolCall.arguments, null, 2)

  return (
    <div className="border-l-2 border-po-status-calling rounded-r overflow-hidden my-1">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full text-left px-3 py-1 flex items-center gap-1.5 hover:bg-po-surface-2 transition-colors duration-150 bg-po-surface"
      >
        <span className="text-2xs text-po-text-ghost">{expanded ? '\u25BC' : '\u25B8'}</span>
        <span className="text-xs font-mono text-po-status-calling">{toolCall.name}</span>
        <span className="text-2xs text-po-text-ghost">
          ({Object.keys(toolCall.arguments).length} args)
        </span>
      </button>
      {expanded && (
        <pre className="px-3 py-1.5 bg-po-surface text-2xs text-po-text-tertiary font-mono whitespace-pre-wrap break-all">
          {argsStr}
        </pre>
      )}
    </div>
  )
}

function ToolResultFrame({ result }: { result: { tool_call_id: string; name?: string; content: string } }) {
  const [expanded, setExpanded] = useState(false)
  const content = result.content || ''
  const chars = content.length

  return (
    <div className="border-l-2 border-po-status-calling rounded-r overflow-hidden my-0.5">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full text-left px-3 py-1 flex items-center gap-1.5 hover:bg-po-surface-2 transition-colors duration-150 bg-po-surface"
      >
        <span className="text-2xs text-po-text-ghost">{expanded ? '\u25BC' : '\u25B8'}</span>
        <span className="text-2xs text-po-text-tertiary">Result</span>
        {result.name && <span className="text-2xs text-po-status-calling font-mono">{result.name}</span>}
        <span className="text-2xs text-po-text-ghost">({chars} chars)</span>
      </button>
      {expanded && (
        <pre className="px-3 py-1.5 bg-po-surface text-2xs text-po-text-tertiary font-mono whitespace-pre-wrap break-all">
          {content}
        </pre>
      )}
    </div>
  )
}
