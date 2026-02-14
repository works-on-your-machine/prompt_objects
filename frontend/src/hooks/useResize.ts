import { useState, useCallback, useEffect, useRef } from 'react'

interface UseResizeOptions {
  direction: 'horizontal' | 'vertical'
  initialSize: number
  minSize: number
  maxSize: number
  /** If true, dragging down/right increases size. If false (for bottom panels), dragging up increases. */
  inverted?: boolean
}

export function useResize({ direction, initialSize, minSize, maxSize, inverted = false }: UseResizeOptions) {
  const [size, setSize] = useState(initialSize)
  const dragging = useRef(false)
  const startPos = useRef(0)
  const startSize = useRef(0)

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    dragging.current = true
    startPos.current = direction === 'horizontal' ? e.clientX : e.clientY
    startSize.current = size
    document.body.style.cursor = direction === 'horizontal' ? 'col-resize' : 'row-resize'
    document.body.style.userSelect = 'none'
  }, [direction, size])

  useEffect(() => {
    const onMouseMove = (e: MouseEvent) => {
      if (!dragging.current) return
      const currentPos = direction === 'horizontal' ? e.clientX : e.clientY
      const delta = currentPos - startPos.current
      const newSize = inverted
        ? startSize.current - delta
        : startSize.current + delta
      setSize(Math.min(maxSize, Math.max(minSize, newSize)))
    }

    const onMouseUp = () => {
      if (dragging.current) {
        dragging.current = false
        document.body.style.cursor = ''
        document.body.style.userSelect = ''
      }
    }

    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
    return () => {
      document.removeEventListener('mousemove', onMouseMove)
      document.removeEventListener('mouseup', onMouseUp)
    }
  }, [direction, minSize, maxSize, inverted])

  return { size, onMouseDown }
}
