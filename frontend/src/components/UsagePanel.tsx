interface UsageData {
  session_id: string
  include_tree: boolean
  input_tokens: number
  output_tokens: number
  total_tokens: number
  estimated_cost_usd: number
  calls: number
  by_model: Record<string, {
    input_tokens: number
    output_tokens: number
    estimated_cost_usd: number
    calls: number
  }>
}

interface UsagePanelProps {
  usage: UsageData
  onClose: () => void
}

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`
  return n.toString()
}

function formatCost(usd: number): string {
  if (usd === 0) return '$0.00'
  if (usd < 0.01) return `$${usd.toFixed(4)}`
  return `$${usd.toFixed(2)}`
}

export function UsagePanel({ usage, onClose }: UsagePanelProps) {
  const models = Object.entries(usage.by_model)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
      <div
        className="bg-po-surface border border-po-border rounded-lg shadow-2xl w-[420px] max-h-[80vh] overflow-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-4 border-b border-po-border">
          <h3 className="font-medium text-white">
            Token Usage {usage.include_tree && <span className="text-xs text-gray-400 ml-1">(full tree)</span>}
          </h3>
          <button onClick={onClose} className="text-gray-400 hover:text-white transition-colors">
            &times;
          </button>
        </div>

        <div className="p-4 space-y-4">
          {/* Summary */}
          <div className="grid grid-cols-3 gap-3">
            <div className="bg-po-bg rounded-lg p-3 text-center">
              <div className="text-lg font-mono text-po-accent">{formatTokens(usage.input_tokens)}</div>
              <div className="text-[10px] text-gray-500 uppercase tracking-wider">Input</div>
            </div>
            <div className="bg-po-bg rounded-lg p-3 text-center">
              <div className="text-lg font-mono text-po-warning">{formatTokens(usage.output_tokens)}</div>
              <div className="text-[10px] text-gray-500 uppercase tracking-wider">Output</div>
            </div>
            <div className="bg-po-bg rounded-lg p-3 text-center">
              <div className="text-lg font-mono text-white">{formatCost(usage.estimated_cost_usd)}</div>
              <div className="text-[10px] text-gray-500 uppercase tracking-wider">Est. Cost</div>
            </div>
          </div>

          <div className="flex justify-between text-xs text-gray-400 px-1">
            <span>{usage.calls} LLM call{usage.calls !== 1 ? 's' : ''}</span>
            <span>{formatTokens(usage.total_tokens)} total tokens</span>
          </div>

          {/* Per-model breakdown */}
          {models.length > 0 && (
            <div>
              <h4 className="text-xs text-gray-500 uppercase tracking-wider mb-2">By Model</h4>
              <div className="space-y-2">
                {models.map(([model, data]) => (
                  <div key={model} className="bg-po-bg rounded-lg p-3">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs font-mono text-white">{model}</span>
                      <span className="text-xs text-gray-400">{data.calls} call{data.calls !== 1 ? 's' : ''}</span>
                    </div>
                    <div className="flex justify-between text-[10px] text-gray-500">
                      <span>In: {formatTokens(data.input_tokens)}</span>
                      <span>Out: {formatTokens(data.output_tokens)}</span>
                      <span>{formatCost(data.estimated_cost_usd)}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {usage.calls === 0 && (
            <div className="text-center text-gray-500 text-sm py-4">
              No usage data recorded for this thread.
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
