import { useMemo } from 'react'
import type { PromptObject, Session, ThreadType } from '../types'

interface ThreadsSidebarProps {
  po: PromptObject
  switchSession: (target: string, sessionId: string) => void
  createThread: (target: string) => void
}

// Build a flat list with depth info
interface ThreadItem {
  session: Session
  depth: number
}

function buildThreadList(sessions: Session[]): ThreadItem[] {
  const childrenMap = new Map<string, Session[]>()

  // Index children
  sessions.forEach((s) => {
    if (s.parent_session_id) {
      const children = childrenMap.get(s.parent_session_id) || []
      children.push(s)
      childrenMap.set(s.parent_session_id, children)
    }
  })

  // Build flat list with depth
  const result: ThreadItem[] = []

  function traverse(session: Session, depth: number) {
    result.push({ session, depth })
    const children = childrenMap.get(session.id) || []
    children
      .sort((a, b) => (a.updated_at || '').localeCompare(b.updated_at || ''))
      .forEach((child) => traverse(child, depth + 1))
  }

  // Get roots and traverse
  const roots = sessions
    .filter((s) => !s.parent_session_id)
    .sort((a, b) => (b.updated_at || '').localeCompare(a.updated_at || ''))

  roots.forEach((root) => traverse(root, 0))

  return result
}

function ThreadTypeIcon({ type }: { type: ThreadType }) {
  switch (type) {
    case 'delegation':
      return <span className="text-purple-400" title="Delegation">↳</span>
    case 'fork':
      return <span className="text-blue-400" title="Fork">⑂</span>
    case 'continuation':
      return <span className="text-gray-400" title="Continuation">→</span>
    default:
      return null
  }
}

export function ThreadsSidebar({ po, switchSession, createThread }: ThreadsSidebarProps) {
  const sessions = po.sessions || []
  const currentSessionId = po.current_session?.id

  const threadList = useMemo(() => buildThreadList(sessions), [sessions])

  return (
    <div className="h-full flex flex-col">
      <div className="p-3 border-b border-po-border flex items-center justify-between">
        <h2 className="text-sm font-medium text-gray-400">Threads</h2>
        <button
          onClick={() => createThread(po.name)}
          className="text-xs text-gray-500 hover:text-po-accent transition-colors"
          title="New thread"
        >
          + New
        </button>
      </div>

      <div className="flex-1 overflow-auto p-2 space-y-1">
        {threadList.length === 0 ? (
          <div className="text-xs text-gray-500 text-center py-4">
            No threads yet
          </div>
        ) : (
          threadList.map(({ session, depth }) => (
            <button
              key={session.id}
              onClick={() => switchSession(po.name, session.id)}
              className={`w-full text-left p-2 rounded text-xs transition-colors ${
                session.id === currentSessionId
                  ? 'bg-po-accent/20 border border-po-accent'
                  : 'hover:bg-po-surface border border-transparent'
              }`}
              style={{ paddingLeft: `${8 + depth * 12}px` }}
            >
              <div className="flex items-center gap-1">
                {depth > 0 && <ThreadTypeIcon type={session.thread_type} />}
                <span className={`truncate flex-1 ${session.id === currentSessionId ? 'text-white' : 'text-gray-300'}`}>
                  {session.name || `Thread ${session.id.slice(0, 6)}`}
                </span>
                {session.id === currentSessionId && (
                  <span className="w-1.5 h-1.5 rounded-full bg-po-accent flex-shrink-0" />
                )}
              </div>
              <div className="text-gray-500 text-[10px] mt-0.5">
                {session.message_count} msgs
                {session.parent_po && (
                  <span className="text-purple-400 ml-1">from {session.parent_po}</span>
                )}
              </div>
            </button>
          ))
        )}
      </div>
    </div>
  )
}
