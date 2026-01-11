import type { PromptObject } from '../types'

interface CapabilitiesPanelProps {
  po: PromptObject
}

export function CapabilitiesPanel({ po }: CapabilitiesPanelProps) {
  const capabilities = po.capabilities || []

  return (
    <div className="h-full overflow-auto p-4">
      <h3 className="text-lg font-medium text-white mb-4">Capabilities</h3>

      {capabilities.length === 0 ? (
        <div className="text-gray-500 text-center py-8">
          No capabilities defined.
        </div>
      ) : (
        <div className="space-y-2">
          {capabilities.map((cap, index) => (
            <div
              key={index}
              className="bg-po-surface border border-po-border rounded-lg p-3"
            >
              <div className="font-mono text-sm text-po-accent">{cap}</div>
            </div>
          ))}
        </div>
      )}

      <div className="mt-6 p-4 bg-po-bg rounded-lg border border-po-border">
        <h4 className="text-sm font-medium text-gray-400 mb-2">
          Universal Capabilities
        </h4>
        <p className="text-xs text-gray-500">
          All Prompt Objects automatically have access to universal capabilities
          like <code className="text-po-accent">ask_human</code>,{' '}
          <code className="text-po-accent">think</code>, and{' '}
          <code className="text-po-accent">request_capability</code>.
        </p>
      </div>
    </div>
  )
}
