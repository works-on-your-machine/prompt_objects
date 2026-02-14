import { useEffect, useRef } from 'react'

interface ContextMenuItem {
  label: string
  onClick: () => void
  icon?: string
  danger?: boolean
}

interface ContextMenuProps {
  x: number
  y: number
  items: ContextMenuItem[]
  onClose: () => void
}

export function ContextMenu({ x, y, items, onClose }: ContextMenuProps) {
  const menuRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose()
      }
    }
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }

    document.addEventListener('mousedown', handleClickOutside)
    document.addEventListener('keydown', handleEscape)
    return () => {
      document.removeEventListener('mousedown', handleClickOutside)
      document.removeEventListener('keydown', handleEscape)
    }
  }, [onClose])

  const adjustedStyle = {
    top: y,
    left: x,
  }

  return (
    <div
      ref={menuRef}
      className="fixed z-50 bg-po-surface-2 border border-po-border rounded shadow-xl py-0.5 min-w-[140px]"
      style={adjustedStyle}
    >
      {items.map((item, idx) => (
        <button
          key={idx}
          onClick={() => {
            item.onClick()
            onClose()
          }}
          className={`w-full text-left px-2.5 py-1.5 text-xs transition-colors duration-150 flex items-center gap-1.5 ${
            item.danger
              ? 'text-po-error hover:bg-po-surface-3'
              : 'text-po-text-secondary hover:bg-po-surface-3 hover:text-po-text-primary'
          }`}
        >
          {item.icon && <span>{item.icon}</span>}
          {item.label}
        </button>
      ))}
    </div>
  )
}
