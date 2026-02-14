import type { PromptObject, CapabilityInfo } from '../types'

interface MethodListProps {
  po: PromptObject
  selectedCapability: CapabilityInfo | null
  onSelectCapability: (cap: CapabilityInfo | null) => void
}

export function MethodList({ po, selectedCapability, onSelectCapability }: MethodListProps) {
  const capabilities = po.capabilities || []
  const universalCapabilities = po.universal_capabilities || []

  const handleClick = (cap: CapabilityInfo) => {
    if (selectedCapability?.name === cap.name) {
      onSelectCapability(null) // Toggle off
    } else {
      onSelectCapability(cap)
    }
  }

  return (
    <div className="h-full border-r border-po-border overflow-auto bg-po-surface">
      {/* Source (prompt view) */}
      <button
        onClick={() => onSelectCapability(null)}
        className={`w-full text-left px-2.5 py-1 text-xs font-mono border-b border-po-border transition-colors duration-150 ${
          selectedCapability === null
            ? 'bg-po-accent-wash text-po-accent'
            : 'text-po-text-secondary hover:bg-po-surface-2'
        }`}
      >
        Source
      </button>

      {/* Declared capabilities */}
      {capabilities.length > 0 && (
        <div>
          <div className="px-2.5 py-1.5 border-b border-po-border">
            <span className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider">
              Methods ({capabilities.length})
            </span>
          </div>
          {capabilities.map((cap) => (
            <button
              key={cap.name}
              onClick={() => handleClick(cap)}
              className={`w-full text-left px-2.5 py-1 text-xs font-mono transition-colors duration-150 ${
                selectedCapability?.name === cap.name
                  ? 'bg-po-accent-wash text-po-accent'
                  : 'text-po-accent hover:bg-po-surface-2'
              }`}
            >
              {cap.name}
            </button>
          ))}
        </div>
      )}

      {/* Universal capabilities */}
      {universalCapabilities.length > 0 && (
        <div>
          <div className="px-2.5 py-1.5 border-b border-po-border border-t border-po-border">
            <span className="text-2xs font-medium text-po-text-ghost uppercase tracking-wider">
              Universal ({universalCapabilities.length})
            </span>
          </div>
          {universalCapabilities.map((cap) => (
            <button
              key={cap.name}
              onClick={() => handleClick(cap)}
              className={`w-full text-left px-2.5 py-1 text-xs font-mono transition-colors duration-150 ${
                selectedCapability?.name === cap.name
                  ? 'bg-po-accent-wash text-po-text-secondary'
                  : 'text-po-text-secondary hover:bg-po-surface-2'
              }`}
            >
              {cap.name}
            </button>
          ))}
        </div>
      )}

      {capabilities.length === 0 && universalCapabilities.length === 0 && (
        <div className="px-2.5 py-4 text-2xs text-po-text-ghost text-center">
          No capabilities
        </div>
      )}
    </div>
  )
}
