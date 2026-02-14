import { useState, useMemo } from 'react'
import { usePONotifications } from '../store'
import { useResize } from '../hooks/useResize'
import { MethodList } from './MethodList'
import { SourcePane } from './SourcePane'
import { Workspace } from './Workspace'
import { ContextMenu } from './ContextMenu'
import type { PromptObject, CapabilityInfo } from '../types'

interface InspectorProps {
  po: PromptObject
  sendMessage: (target: string, content: string, newThread?: boolean) => void
  createSession?: (target: string, name?: string) => void
  switchSession: (target: string, sessionId: string) => void
  createThread: (target: string) => void
  updatePrompt: (target: string, prompt: string) => void
  requestUsage?: (sessionId: string, includeTree?: boolean) => void
  exportThread?: (sessionId: string, format?: string) => void
}

export function Inspector({
  po,
  sendMessage,
  switchSession,
  createThread,
  updatePrompt,
  requestUsage,
  exportThread,
}: InspectorProps) {
  const [selectedCapability, setSelectedCapability] = useState<CapabilityInfo | null>(null)
  const [threadMenuOpen, setThreadMenuOpen] = useState(false)
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; sessionId: string } | null>(null)
  const notifications = usePONotifications(po.name)

  const topPaneResize = useResize({
    direction: 'vertical',
    initialSize: 260,
    minSize: 120,
    maxSize: 600,
  })

  const methodListResize = useResize({
    direction: 'horizontal',
    initialSize: 192,
    minSize: 120,
    maxSize: 320,
  })

  const sessions = po.sessions || []
  const currentSessionId = po.current_session?.id

  // Sort sessions: current first, then by updated_at desc
  const sortedSessions = useMemo(() => {
    return [...sessions].sort((a, b) => {
      if (a.id === currentSessionId) return -1
      if (b.id === currentSessionId) return 1
      return (b.updated_at || '').localeCompare(a.updated_at || '')
    })
  }, [sessions, currentSessionId])

  const statusDot = {
    idle: 'bg-po-status-idle',
    thinking: 'bg-po-status-active animate-pulse',
    calling_tool: 'bg-po-status-calling animate-pulse',
  }[po.status] || 'bg-po-status-idle'

  const statusLabel = {
    idle: 'idle',
    thinking: 'thinking...',
    calling_tool: 'calling tool...',
  }[po.status] || po.status

  const handleThreadContextMenu = (e: React.MouseEvent, sessionId: string) => {
    e.preventDefault()
    setContextMenu({ x: e.clientX, y: e.clientY, sessionId })
  }

  return (
    <div className="h-full flex flex-col">
      {/* Inspector Header */}
      <div className="h-8 bg-po-surface-2 border-b border-po-border flex items-center px-3 gap-2 flex-shrink-0">
        <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${statusDot}`} />
        <span className="font-mono text-xs text-po-text-primary font-medium">{po.name}</span>
        <span className="text-2xs text-po-text-tertiary truncate">{statusLabel}</span>
        {po.description && (
          <span className="text-2xs text-po-text-ghost truncate hidden sm:inline">{po.description}</span>
        )}
        {notifications.length > 0 && (
          <span className="text-2xs font-mono bg-po-warning text-po-bg px-1 rounded font-bold">
            {notifications.length}
          </span>
        )}

        <div className="flex-1" />

        {/* Thread picker */}
        <div className="relative">
          <button
            onClick={() => setThreadMenuOpen(!threadMenuOpen)}
            className="flex items-center gap-1 text-2xs text-po-text-secondary hover:text-po-text-primary transition-colors duration-150"
          >
            <span className="font-mono">
              {currentSessionId
                ? sessions.find(s => s.id === currentSessionId)?.name || `Thread ${currentSessionId.slice(0, 6)}`
                : 'No thread'}
            </span>
            <svg className={`w-3 h-3 transition-transform ${threadMenuOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          {threadMenuOpen && (
            <div className="absolute right-0 top-full mt-1 w-56 bg-po-surface-2 border border-po-border rounded shadow-xl z-50 overflow-hidden">
              <button
                onClick={() => { createThread(po.name); setThreadMenuOpen(false) }}
                className="w-full text-left px-2.5 py-1.5 text-xs text-po-accent hover:bg-po-surface-3 transition-colors duration-150 border-b border-po-border"
              >
                + New Thread
              </button>
              <div className="max-h-48 overflow-auto">
                {sortedSessions.map((session) => (
                  <button
                    key={session.id}
                    onClick={() => { switchSession(po.name, session.id); setThreadMenuOpen(false) }}
                    onContextMenu={(e) => handleThreadContextMenu(e, session.id)}
                    className={`w-full text-left px-2.5 py-1.5 text-xs transition-colors duration-150 ${
                      session.id === currentSessionId
                        ? 'bg-po-accent-wash text-po-accent'
                        : 'text-po-text-secondary hover:bg-po-surface-3'
                    }`}
                  >
                    <div className="flex items-center gap-1.5">
                      {session.thread_type === 'delegation' && <span className="text-po-status-delegated">&#8627;</span>}
                      <span className="font-mono truncate flex-1">
                        {session.name || `Thread ${session.id.slice(0, 6)}`}
                      </span>
                      <span className="text-2xs text-po-text-ghost">{session.message_count}m</span>
                    </div>
                    {session.parent_po && (
                      <div className="text-2xs text-po-status-delegated mt-0.5">from {session.parent_po}</div>
                    )}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Top: Methods + Source (resizable height) */}
      <div className="flex overflow-hidden flex-shrink-0" style={{ height: topPaneResize.size }}>
        {/* Method List (resizable width) */}
        <div style={{ width: methodListResize.size }} className="flex-shrink-0">
          <MethodList
            po={po}
            selectedCapability={selectedCapability}
            onSelectCapability={setSelectedCapability}
          />
        </div>

        {/* Resize handle */}
        <div
          className="resize-handle"
          onMouseDown={methodListResize.onMouseDown}
        />

        {/* Source Pane */}
        <SourcePane
          po={po}
          selectedCapability={selectedCapability}
          onSave={(prompt) => updatePrompt(po.name, prompt)}
        />
      </div>

      {/* Resize handle between top and workspace */}
      <div
        className="resize-handle-h"
        onMouseDown={topPaneResize.onMouseDown}
      />

      {/* Bottom: Workspace */}
      <div className="flex-1 overflow-hidden">
        <Workspace po={po} sendMessage={sendMessage} />
      </div>

      {/* Context menu for thread right-click */}
      {contextMenu && (
        <ContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          onClose={() => setContextMenu(null)}
          items={[
            ...(requestUsage ? [
              { label: 'View Usage', onClick: () => requestUsage(contextMenu.sessionId) },
              { label: 'View Tree Usage', onClick: () => requestUsage(contextMenu.sessionId, true) },
            ] : []),
            ...(exportThread ? [
              { label: 'Export Markdown', onClick: () => exportThread(contextMenu.sessionId, 'markdown') },
              { label: 'Export JSON', onClick: () => exportThread(contextMenu.sessionId, 'json') },
            ] : []),
          ]}
        />
      )}
    </div>
  )
}
