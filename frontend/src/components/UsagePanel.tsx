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
        className="bg-po-surface-2 border border-po-border rounded shadow-2xl w-[400px] max-h-[80vh] overflow-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-4 py-2.5 border-b border-po-border">
          <h3 className="font-mono text-xs text-po-text-primary">
            Token Usage {usage.include_tree && <span className="text-po-text-ghost ml-1">(full tree)</span>}
          </h3>
          <button onClick={onClose} className="text-po-text-ghost hover:text-po-text-primary transition-colors duration-150">
            {'\u2715'}
          </button>
        </div>

        <div className="p-4 space-y-4">
          {/* Summary */}
          <div className="grid grid-cols-3 gap-2">
            <div className="bg-po-surface rounded p-2.5 text-center">
              <div className="text-sm font-mono text-po-accent">{formatTokens(usage.input_tokens)}</div>
              <div className="text-2xs text-po-text-ghost uppercase tracking-wider mt-0.5">Input</div>
            </div>
            <div className="bg-po-surface rounded p-2.5 text-center">
              <div className="text-sm font-mono text-po-warning">{formatTokens(usage.output_tokens)}</div>
              <div className="text-2xs text-po-text-ghost uppercase tracking-wider mt-0.5">Output</div>
            </div>
            <div className="bg-po-surface rounded p-2.5 text-center">
              <div className="text-sm font-mono text-po-text-primary">{formatCost(usage.estimated_cost_usd)}</div>
              <div className="text-2xs text-po-text-ghost uppercase tracking-wider mt-0.5">Est. Cost</div>
            </div>
          </div>

          <div className="flex justify-between text-2xs text-po-text-ghost px-1 font-mono">
            <span>{usage.calls} call{usage.calls !== 1 ? 's' : ''}</span>
            <span>{formatTokens(usage.total_tokens)} total</span>
          </div>

          {/* Per-model breakdown */}
          {models.length > 0 && (
            <div>
              <h4 className="text-2xs text-po-text-ghost uppercase tracking-wider mb-2">By Model</h4>
              <div className="space-y-1.5">
                {models.map(([model, data]) => (
                  <div key={model} className="bg-po-surface rounded p-2.5">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs font-mono text-po-text-primary">{model}</span>
                      <span className="text-2xs text-po-text-ghost">{data.calls} call{data.calls !== 1 ? 's' : ''}</span>
                    </div>
                    <div className="flex justify-between text-2xs text-po-text-ghost font-mono">
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
            <div className="text-center text-po-text-ghost text-xs py-4 font-mono">
              No usage data recorded.
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
