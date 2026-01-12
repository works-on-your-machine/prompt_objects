import { useMemo } from 'react'
import type { PromptObject, Session, ThreadType } from '../types'

interface SessionsPanelProps {
  po: PromptObject
  createSession: (target: string, name?: string) => void
  switchSession: (target: string, sessionId: string) => void
  createThread?: (target: string, name?: string) => void
}

// Build a tree structure from flat sessions list
interface ThreadNode {
  session: Session
  children: ThreadNode[]
  depth: number
}

function buildThreadTree(sessions: Session[]): ThreadNode[] {
  const sessionMap = new Map<string, Session>()
  const childrenMap = new Map<string, Session[]>()

  // Index all sessions
  sessions.forEach((s) => {
    sessionMap.set(s.id, s)
    if (s.parent_session_id) {
      const children = childrenMap.get(s.parent_session_id) || []
      children.push(s)
      childrenMap.set(s.parent_session_id, children)
    }
  })

  // Build tree recursively
  function buildNode(session: Session, depth: number): ThreadNode {
    const children = childrenMap.get(session.id) || []
    return {
      session,
      children: children
        .sort((a, b) => (a.updated_at || '').localeCompare(b.updated_at || ''))
        .map((child) => buildNode(child, depth + 1)),
      depth,
    }
  }

  // Get root sessions (no parent)
  const roots = sessions
    .filter((s) => !s.parent_session_id)
    .sort((a, b) => (b.updated_at || '').localeCompare(a.updated_at || ''))

  return roots.map((root) => buildNode(root, 0))
}

// Flatten tree for rendering
function flattenTree(nodes: ThreadNode[]): ThreadNode[] {
  const result: ThreadNode[] = []
  function traverse(node: ThreadNode) {
    result.push(node)
    node.children.forEach(traverse)
  }
  nodes.forEach(traverse)
  return result
}

// Thread type icons/badges
function ThreadTypeBadge({ type }: { type: ThreadType }) {
  switch (type) {
    case 'delegation':
      return (
        <span className="text-xs bg-purple-600/30 text-purple-300 px-1.5 py-0.5 rounded">
          ↳ delegation
        </span>
      )
    case 'fork':
      return (
        <span className="text-xs bg-blue-600/30 text-blue-300 px-1.5 py-0.5 rounded">
          ⑂ fork
        </span>
      )
    case 'continuation':
      return (
        <span className="text-xs bg-gray-600/30 text-gray-300 px-1.5 py-0.5 rounded">
          → continued
        </span>
      )
    default:
      return null
  }
}

export function SessionsPanel({
  po,
  createSession,
  switchSession,
  createThread,
}: SessionsPanelProps) {
  const sessions = po.sessions || []
  const currentSessionId = po.current_session?.id

  // Build and flatten thread tree
  const flatNodes = useMemo(() => {
    const tree = buildThreadTree(sessions)
    return flattenTree(tree)
  }, [sessions])

  const handleNewThread = () => {
    if (createThread) {
      createThread(po.name)
    } else {
      // Fallback to createSession
      const name = prompt('Thread name (optional):')
      createSession(po.name, name || undefined)
    }
  }

  return (
    <div className="h-full overflow-auto p-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-white">Threads</h3>
        <button
          onClick={handleNewThread}
          className="px-3 py-1.5 bg-po-accent text-white text-sm rounded hover:bg-po-accent/80 transition-colors"
        >
          + New Thread
        </button>
      </div>

      {flatNodes.length === 0 ? (
        <div className="text-gray-500 text-center py-8">
          No threads yet. Start a conversation to create one.
        </div>
      ) : (
        <div className="space-y-1">
          {flatNodes.map(({ session, depth }) => (
            <button
              key={session.id}
              onClick={() => switchSession(po.name, session.id)}
              className={`w-full text-left p-3 rounded-lg border transition-colors ${
                session.id === currentSessionId
                  ? 'bg-po-accent/20 border-po-accent'
                  : 'bg-po-surface border-po-border hover:border-po-accent/50'
              }`}
              style={{ marginLeft: `${depth * 16}px`, width: `calc(100% - ${depth * 16}px)` }}
            >
              <div className="flex items-center gap-2 mb-1">
                {depth > 0 && (
                  <span className="text-gray-500 text-xs">↳</span>
                )}
                <span className="font-medium text-white truncate flex-1">
                  {session.name || `Thread ${session.id.slice(0, 8)}`}
                </span>
                <ThreadTypeBadge type={session.thread_type} />
                {session.id === currentSessionId && (
                  <span className="text-xs bg-po-accent text-white px-2 py-0.5 rounded flex-shrink-0">
                    Active
                  </span>
                )}
              </div>
              <div className="text-sm text-gray-400 flex items-center gap-2">
                <span>{session.message_count} messages</span>
                {session.parent_po && (
                  <span className="text-purple-400">from {session.parent_po}</span>
                )}
                {session.updated_at && (
                  <span className="ml-auto">
                    {new Date(session.updated_at).toLocaleDateString()}
                  </span>
                )}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
