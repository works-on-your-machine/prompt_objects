interface PaneSlotProps {
  label: string
  collapsed: boolean
  onToggle: () => void
  height: number
  resizeHandle?: React.ReactNode
  children: React.ReactNode
}

export function PaneSlot({ label, collapsed, onToggle, height, resizeHandle, children }: PaneSlotProps) {
  return (
    <>
      <div
        className="h-7 bg-po-surface-2 border-b border-po-border flex items-center px-3 cursor-pointer hover:bg-po-surface-3 transition-colors duration-150 flex-shrink-0 select-none"
        onClick={onToggle}
      >
        <span className="text-2xs font-mono text-po-text-secondary flex-1">{label}</span>
        <span className="text-xs text-po-text-ghost">{collapsed ? '▼' : '▲'}</span>
      </div>
      {!collapsed && (
        <>
          <div className="flex-shrink-0 overflow-hidden" style={{ height }}>
            {children}
          </div>
          {resizeHandle}
        </>
      )}
    </>
  )
}
