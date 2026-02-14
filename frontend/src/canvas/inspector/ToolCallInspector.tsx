import { useCanvasStore } from '../canvasStore'

interface Props {
  toolCallId: string
}

const statusColors: Record<string, string> = {
  active: 'text-po-accent',
  completed: 'text-po-success',
  error: 'text-po-error',
}

export function ToolCallInspector({ toolCallId }: Props) {
  const toolCall = useCanvasStore((s) => s.activeToolCalls.get(toolCallId))

  if (!toolCall) {
    return (
      <div className="p-4 text-po-text-ghost text-xs font-mono">
        Tool call not found or has expired.
      </div>
    )
  }

  const duration = toolCall.completedAt
    ? ((toolCall.completedAt - toolCall.startedAt) / 1000).toFixed(1) + 's'
    : ((Date.now() - toolCall.startedAt) / 1000).toFixed(1) + 's (running)'

  return (
    <div className="p-4 space-y-4">
      {/* Header */}
      <div>
        <h3 className="text-sm font-mono font-medium text-po-text-primary">{toolCall.toolName}</h3>
        <div className="flex items-center gap-2 mt-1">
          <span className={`text-xs font-mono font-medium ${statusColors[toolCall.status] || ''}`}>
            {toolCall.status}
          </span>
          <span className="text-2xs text-po-text-ghost font-mono">{duration}</span>
        </div>
        <div className="text-xs text-po-text-tertiary mt-1">
          Called by: <span className="text-po-accent font-mono">{toolCall.callerPO}</span>
        </div>
      </div>

      {/* Parameters */}
      <div>
        <h4 className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider mb-2">Parameters</h4>
        <div className="bg-po-surface-2 border border-po-border rounded p-2.5 overflow-auto max-h-48">
          <pre className="text-xs text-po-text-secondary font-mono whitespace-pre-wrap">
            {JSON.stringify(toolCall.params, null, 2)}
          </pre>
        </div>
      </div>

      {/* Result */}
      {toolCall.result && (
        <div>
          <h4 className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider mb-2">Result</h4>
          <div className="bg-po-surface-2 border border-po-border rounded p-2.5 overflow-auto max-h-64">
            <pre className="text-xs text-po-text-secondary font-mono whitespace-pre-wrap">
              {toolCall.result}
            </pre>
          </div>
        </div>
      )}
    </div>
  )
}
