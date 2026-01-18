import { useState } from 'react'
import type { PromptObject, UniversalCapability } from '../types'

interface CapabilitiesPanelProps {
  po: PromptObject
}

export function CapabilitiesPanel({ po }: CapabilitiesPanelProps) {
  const capabilities = po.capabilities || []
  const universalCapabilities = po.universal_capabilities || []

  return (
    <div className="h-full overflow-auto p-4">
      {/* Declared Capabilities */}
      <div className="mb-6">
        <h3 className="text-lg font-medium text-white mb-3">
          Declared Capabilities
          <span className="ml-2 text-sm text-gray-500">({capabilities.length})</span>
        </h3>

        {capabilities.length === 0 ? (
          <div className="text-gray-500 text-sm py-4 px-3 bg-po-bg rounded-lg border border-po-border">
            No capabilities declared. This PO can only use universal capabilities.
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
      </div>

      {/* Universal Capabilities */}
      <div>
        <h3 className="text-lg font-medium text-white mb-3">
          Universal Capabilities
          <span className="ml-2 text-sm text-gray-500">({universalCapabilities.length})</span>
        </h3>
        <p className="text-xs text-gray-500 mb-3">
          Available to all Prompt Objects automatically.
        </p>

        <div className="space-y-1">
          {universalCapabilities.map((cap) => (
            <UniversalCapabilityItem key={cap.name} capability={cap} />
          ))}
        </div>
      </div>
    </div>
  )
}

function UniversalCapabilityItem({ capability }: { capability: UniversalCapability }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className="bg-po-bg border border-po-border rounded-lg overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full px-3 py-2 flex items-center justify-between hover:bg-po-surface transition-colors"
      >
        <span className="font-mono text-sm text-gray-300">{capability.name}</span>
        <span className="text-gray-500 text-xs">{expanded ? '▼' : '▶'}</span>
      </button>
      {expanded && (
        <div className="px-3 py-2 border-t border-po-border bg-po-surface">
          <p className="text-xs text-gray-400">{capability.description}</p>
        </div>
      )}
    </div>
  )
}
