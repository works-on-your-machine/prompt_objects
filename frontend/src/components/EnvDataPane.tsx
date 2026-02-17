import { useState, useEffect } from 'react'
import { useStore, useEnvData } from '../store'
import type { EnvDataEntry } from '../types'

interface EnvDataPaneProps {
  sessionId: string | undefined
  requestEnvData: (sessionId: string) => void
}

export function EnvDataPane({ sessionId, requestEnvData }: EnvDataPaneProps) {
  const sessionRootMap = useStore((s) => s.sessionRootMap)
  const rootThreadId = sessionId ? sessionRootMap[sessionId] : undefined
  const entries = useEnvData(rootThreadId)
  const [expandedKey, setExpandedKey] = useState<string | null>(null)

  useEffect(() => {
    if (sessionId) {
      requestEnvData(sessionId)
    }
  }, [sessionId, requestEnvData])

  if (entries.length === 0) {
    return (
      <div className="h-full flex items-center justify-center">
        <span className="font-mono text-xs text-po-text-ghost">No shared data</span>
      </div>
    )
  }

  return (
    <div className="h-full overflow-auto px-2 py-1">
      {entries.map((entry) => (
        <EnvDataRow
          key={entry.key}
          entry={entry}
          expanded={expandedKey === entry.key}
          onToggle={() => setExpandedKey(expandedKey === entry.key ? null : entry.key)}
        />
      ))}
    </div>
  )
}

function EnvDataRow({ entry, expanded, onToggle }: { entry: EnvDataEntry; expanded: boolean; onToggle: () => void }) {
  return (
    <div className="border-b border-po-border last:border-b-0">
      <button
        onClick={onToggle}
        className="w-full text-left px-1.5 py-1.5 hover:bg-po-surface-3 transition-colors duration-150 flex items-center gap-2"
      >
        <span className="text-2xs text-po-text-ghost">{expanded ? '▼' : '▶'}</span>
        <span className="font-mono text-sm text-po-accent truncate">{entry.key}</span>
        <span className="text-xs text-po-text-ghost truncate flex-1">{entry.short_description}</span>
        <span className="text-xs text-po-text-ghost flex-shrink-0">{entry.stored_by}</span>
      </button>
      {expanded && (
        <div className="px-2 pb-2">
          <div className="text-xs text-po-text-ghost mb-1">
            stored by <span className="text-po-text-secondary">{entry.stored_by}</span>
            {entry.updated_at && <> &middot; {new Date(entry.updated_at).toLocaleTimeString()}</>}
          </div>
          <pre className="font-mono text-xs text-po-text-primary bg-po-surface-1 rounded p-2 overflow-auto max-h-40 whitespace-pre-wrap break-all">
            {typeof entry.value === 'string' ? entry.value : JSON.stringify(entry.value, null, 2)}
          </pre>
        </div>
      )}
    </div>
  )
}
