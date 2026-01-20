import { useState } from 'react'
import type { PromptObject, CapabilityInfo } from '../types'

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
          <div className="space-y-1">
            {capabilities.map((cap) => (
              <CapabilityItem key={cap.name} capability={cap} accent />
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
            <CapabilityItem key={cap.name} capability={cap} />
          ))}
        </div>
      </div>
    </div>
  )
}

interface CapabilityItemProps {
  capability: CapabilityInfo
  accent?: boolean  // Use accent color for name (for declared caps)
}

function CapabilityItem({ capability, accent }: CapabilityItemProps) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className="bg-po-bg border border-po-border rounded-lg overflow-hidden">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full px-3 py-2 flex items-center justify-between hover:bg-po-surface transition-colors"
      >
        <span className={`font-mono text-sm ${accent ? 'text-po-accent' : 'text-gray-300'}`}>
          {capability.name}
        </span>
        <span className="text-gray-500 text-xs">{expanded ? '▼' : '▶'}</span>
      </button>
      {expanded && (
        <div className="px-3 py-2 border-t border-po-border bg-po-surface space-y-3">
          <p className="text-xs text-gray-400">{capability.description}</p>

          {capability.parameters && (
            <ParametersDisplay parameters={capability.parameters} />
          )}
        </div>
      )}
    </div>
  )
}

interface ParametersDisplayProps {
  parameters: Record<string, unknown>
}

function ParametersDisplay({ parameters }: ParametersDisplayProps) {
  const properties = (parameters.properties as Record<string, unknown>) || {}
  const required = (parameters.required as string[]) || []

  const propertyNames = Object.keys(properties)

  if (propertyNames.length === 0) {
    return null
  }

  return (
    <div>
      <div className="text-xs text-gray-500 mb-2 font-medium">Parameters</div>
      <div className="space-y-2">
        {propertyNames.map((propName) => {
          const prop = properties[propName] as Record<string, unknown>
          const isRequired = required.includes(propName)

          const propType = prop.type ? String(prop.type) : null
          const propDescription = prop.description ? String(prop.description) : null
          const propEnum = prop.enum as string[] | undefined

          return (
            <div key={propName} className="bg-po-bg rounded p-2">
              <div className="flex items-center gap-2">
                <span className="font-mono text-xs text-po-accent">{propName}</span>
                {propType && (
                  <span className="text-xs text-gray-600">({propType})</span>
                )}
                {isRequired && (
                  <span className="text-xs text-red-400">required</span>
                )}
              </div>
              {propDescription && (
                <p className="text-xs text-gray-500 mt-1">{propDescription}</p>
              )}
              {propEnum && propEnum.length > 0 && (
                <div className="mt-1 flex flex-wrap gap-1">
                  {propEnum.map((val) => (
                    <span key={val} className="text-xs bg-po-surface px-1.5 py-0.5 rounded text-gray-400">
                      {val}
                    </span>
                  ))}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
