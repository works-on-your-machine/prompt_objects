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

  // Adjust position to stay within viewport
  const adjustedStyle = {
    top: y,
    left: x,
  }

  return (
    <div
      ref={menuRef}
      className="fixed z-50 bg-po-surface border border-po-border rounded-lg shadow-xl py-1 min-w-[160px]"
      style={adjustedStyle}
    >
      {items.map((item, idx) => (
        <button
          key={idx}
          onClick={() => {
            item.onClick()
            onClose()
          }}
          className={`w-full text-left px-3 py-1.5 text-xs hover:bg-po-bg transition-colors flex items-center gap-2 ${
            item.danger ? 'text-red-400 hover:text-red-300' : 'text-gray-300 hover:text-white'
          }`}
        >
          {item.icon && <span>{item.icon}</span>}
          {item.label}
        </button>
      ))}
    </div>
  )
}
