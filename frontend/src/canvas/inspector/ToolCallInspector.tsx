import { useCanvasStore } from '../canvasStore'

interface Props {
  toolCallId: string
}

const statusColors: Record<string, string> = {
  active: 'text-po-accent',
  completed: 'text-po-success',
  error: 'text-red-400',
}

export function ToolCallInspector({ toolCallId }: Props) {
  const toolCall = useCanvasStore((s) => s.activeToolCalls.get(toolCallId))

  if (!toolCall) {
    return (
      <div className="p-4 text-gray-500 text-sm">
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
        <h3 className="text-lg font-medium text-white font-mono">{toolCall.toolName}</h3>
        <div className="flex items-center gap-2 mt-1">
          <span className={`text-xs font-medium ${statusColors[toolCall.status] || ''}`}>
            {toolCall.status}
          </span>
          <span className="text-xs text-gray-500">{duration}</span>
        </div>
        <div className="text-xs text-gray-400 mt-1">
          Called by: <span className="text-po-accent">{toolCall.callerPO}</span>
        </div>
      </div>

      {/* Parameters */}
      <div>
        <h4 className="text-sm font-medium text-gray-400 mb-2">Parameters</h4>
        <div className="bg-po-bg border border-po-border rounded p-3 overflow-auto max-h-48">
          <pre className="text-xs text-gray-300 font-mono whitespace-pre-wrap">
            {JSON.stringify(toolCall.params, null, 2)}
          </pre>
        </div>
      </div>

      {/* Result */}
      {toolCall.result && (
        <div>
          <h4 className="text-sm font-medium text-gray-400 mb-2">Result</h4>
          <div className="bg-po-bg border border-po-border rounded p-3 overflow-auto max-h-64">
            <pre className="text-xs text-gray-300 font-mono whitespace-pre-wrap">
              {toolCall.result}
            </pre>
          </div>
        </div>
      )}
    </div>
  )
}
