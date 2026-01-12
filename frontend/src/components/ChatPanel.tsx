import { useState, useRef, useEffect } from 'react'
import { useStore } from '../store'
import { MarkdownMessage } from './MarkdownMessage'
import type { PromptObject, Message, ToolCall } from '../types'

interface ChatPanelProps {
  po: PromptObject
  sendMessage: (target: string, content: string) => void
}

export function ChatPanel({ po, sendMessage }: ChatPanelProps) {
  const [input, setInput] = useState('')
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const { streamingContent, addMessageToPO } = useStore()

  const messages = po.current_session?.messages || []
  const streaming = streamingContent[po.name]

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, streaming])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim()) return

    const content = input.trim()

    // Add user message immediately (optimistic update)
    addMessageToPO(po.name, {
      role: 'user',
      content,
      from: 'human',
    })

    // Send to server
    sendMessage(po.name, content)
    setInput('')
  }

  return (
    <div className="h-full flex flex-col">
      {/* Messages */}
      <div className="flex-1 overflow-auto p-4 space-y-4">
        {messages.length === 0 && !streaming && (
          <div className="h-full flex items-center justify-center text-gray-500">
            <div className="text-center">
              <div className="text-2xl mb-2">💬</div>
              <div>Start a conversation with {po.name}</div>
            </div>
          </div>
        )}

        {messages.map((message, index) => (
          <MessageBubble key={index} message={message} />
        ))}

        {/* Streaming content */}
        {streaming && (
          <div className="flex gap-3">
            <div className="w-8 h-8 rounded-full bg-po-accent flex items-center justify-center text-white text-sm font-medium flex-shrink-0">
              AI
            </div>
            <div className="flex-1 bg-po-surface rounded-lg p-3 text-gray-200">
              <MarkdownMessage content={streaming} />
              <span className="inline-block w-2 h-4 bg-po-accent animate-pulse ml-1" />
            </div>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSubmit} className="border-t border-po-border p-4">
        <div className="flex gap-3">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder={`Message ${po.name}...`}
            className="flex-1 bg-po-surface border border-po-border rounded-lg px-4 py-2 text-white placeholder-gray-500 focus:outline-none focus:border-po-accent"
            disabled={po.status !== 'idle'}
          />
          <button
            type="submit"
            disabled={!input.trim() || po.status !== 'idle'}
            className="px-4 py-2 bg-po-accent text-white rounded-lg font-medium hover:bg-po-accent/80 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Send
          </button>
        </div>
      </form>
    </div>
  )
}

function MessageBubble({ message }: { message: Message }) {
  const isUser = message.role === 'user'
  const isAssistant = message.role === 'assistant'
  const isTool = message.role === 'tool'

  if (isTool) {
    return (
      <div className="text-xs text-gray-500 bg-po-bg rounded p-2 font-mono">
        <div className="text-gray-400 mb-1">Tool Result:</div>
        <div className="whitespace-pre-wrap break-all">
          {message.content?.slice(0, 500)}
          {message.content && message.content.length > 500 && '...'}
        </div>
      </div>
    )
  }

  return (
    <div className={`flex gap-3 ${isUser ? 'flex-row-reverse' : ''}`}>
      <div
        className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium flex-shrink-0 ${
          isUser ? 'bg-po-border text-white' : 'bg-po-accent text-white'
        }`}
      >
        {isUser ? 'You' : 'AI'}
      </div>
      <div
        className={`flex-1 max-w-[80%] rounded-lg p-3 ${
          isUser
            ? 'bg-po-accent text-white'
            : 'bg-po-surface text-gray-200'
        }`}
      >
        {message.content && (
          isAssistant ? (
            <MarkdownMessage content={message.content} />
          ) : (
            <div className="whitespace-pre-wrap">{message.content}</div>
          )
        )}

        {/* Tool calls */}
        {isAssistant && message.tool_calls && message.tool_calls.length > 0 && (
          <div className="mt-2 space-y-2">
            {message.tool_calls.map((tc) => (
              <ToolCallDisplay key={tc.id} toolCall={tc} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

function ToolCallDisplay({ toolCall }: { toolCall: ToolCall }) {
  const { notifications } = useStore()

  // Special display for ask_human
  if (toolCall.name === 'ask_human') {
    const question = toolCall.arguments.question as string
    const options = toolCall.arguments.options as string[] | undefined

    // Check if there's a pending notification for this (by matching question)
    const isPending = notifications.some((n) => n.message === question)

    return (
      <div className="bg-po-warning/10 border border-po-warning/30 rounded-lg p-3">
        <div className="flex items-center gap-2 mb-2">
          <span className="text-po-warning text-sm font-medium">
            Waiting for human input
          </span>
          {isPending ? (
            <span className="text-xs bg-po-warning text-black px-2 py-0.5 rounded animate-pulse">
              PENDING
            </span>
          ) : (
            <span className="text-xs bg-green-600 text-white px-2 py-0.5 rounded">
              RESOLVED
            </span>
          )}
        </div>
        <p className="text-gray-200 text-sm mb-2">{question}</p>
        {options && options.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {options.map((opt, i) => (
              <span
                key={i}
                className="text-xs bg-po-bg px-2 py-1 rounded text-gray-400"
              >
                {opt}
              </span>
            ))}
          </div>
        )}
      </div>
    )
  }

  // Default display for other tool calls
  return (
    <div className="text-xs bg-po-bg/50 rounded px-2 py-1 font-mono">
      <span className="text-po-accent">{toolCall.name}</span>
      <span className="text-gray-500">
        ({Object.keys(toolCall.arguments).join(', ')})
      </span>
    </div>
  )
}
