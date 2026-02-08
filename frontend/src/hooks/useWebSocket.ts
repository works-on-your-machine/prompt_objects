import { useEffect, useRef, useCallback } from 'react'
import { useStore } from '../store'
import type {
  WSMessage,
  PromptObject,
  BusMessage,
  Notification,
  Environment,
  Message,
  LLMConfig,
  SendMessagePayload,
  RespondToNotificationPayload,
  CreateSessionPayload,
  SwitchSessionPayload,
  CreateThreadPayload,
  ThreadType,
} from '../types'

export function useWebSocket() {
  const ws = useRef<WebSocket | null>(null)
  const reconnectTimeout = useRef<number | null>(null)

  const {
    setConnected,
    setEnvironment,
    setPromptObject,
    removePromptObject,
    updateSessionMessages,
    switchPOSession,
    addBusMessage,
    addNotification,
    removeNotification,
    appendStreamChunk,
    clearStream,
    setPendingResponse,
    clearPendingResponse,
    setLLMConfig,
    updateCurrentLLM,
    setUsageData,
  } = useStore()

  const connect = useCallback(() => {
    // Determine WebSocket URL
    // In dev mode (Vite on 5173), connect directly to Ruby server on 3000
    // In production, connect to same host
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const isDev = window.location.port === '5173'
    const host = isDev ? 'localhost:3000' : window.location.host
    const wsUrl = `${protocol}//${host}`

    console.log('Connecting to WebSocket:', wsUrl)
    ws.current = new WebSocket(wsUrl)

    ws.current.onopen = () => {
      console.log('WebSocket connected')
      setConnected(true)

      // Clear any pending reconnect
      if (reconnectTimeout.current) {
        clearTimeout(reconnectTimeout.current)
        reconnectTimeout.current = null
      }
    }

    ws.current.onclose = () => {
      console.log('WebSocket disconnected')
      setConnected(false)

      // Attempt to reconnect after 2 seconds
      reconnectTimeout.current = window.setTimeout(() => {
        console.log('Attempting to reconnect...')
        connect()
      }, 2000)
    }

    ws.current.onerror = (error) => {
      console.error('WebSocket error:', error)
    }

    ws.current.onmessage = (event) => {
      try {
        const message: WSMessage = JSON.parse(event.data)
        handleMessage(message)
      } catch (error) {
        console.error('Failed to parse WebSocket message:', error)
      }
    }
  }, [setConnected])

  const handleMessage = useCallback(
    (message: WSMessage) => {
      switch (message.type) {
        case 'environment':
          setEnvironment(message.payload as Environment)
          break

        case 'po_state': {
          const { name, state } = message.payload as {
            name: string
            state: Partial<PromptObject>
          }
          setPromptObject(name, state)
          break
        }

        case 'po_response': {
          const { target, content } = message.payload as {
            target: string
            content: string
          }
          setPendingResponse(target, content)
          // Clear after a short delay to allow UI to update
          setTimeout(() => clearPendingResponse(target), 100)
          break
        }

        case 'stream': {
          const { target, chunk } = message.payload as {
            target: string
            chunk: string
          }
          appendStreamChunk(target, chunk)
          break
        }

        case 'stream_end': {
          const { target } = message.payload as { target: string }
          clearStream(target)
          break
        }

        case 'bus_message':
          addBusMessage(message.payload as BusMessage)
          break

        case 'notification':
          addNotification(message.payload as Notification)
          break

        case 'notification_resolved': {
          const { id } = message.payload as { id: string }
          removeNotification(id)
          break
        }

        // Live file updates
        case 'po_added': {
          const { name, state } = message.payload as {
            name: string
            state: Partial<PromptObject>
          }
          console.log('PO added:', name)
          setPromptObject(name, state)
          break
        }

        case 'po_modified': {
          const { name, state } = message.payload as {
            name: string
            state: Partial<PromptObject>
          }
          console.log('PO modified:', name)
          setPromptObject(name, state)
          break
        }

        case 'po_removed': {
          const { name } = message.payload as { name: string }
          console.log('PO removed:', name)
          removePromptObject(name)
          break
        }

        case 'session_updated': {
          const { target, session_id, messages } = message.payload as {
            target: string
            session_id: string
            messages: Message[]
          }
          updateSessionMessages(target, session_id, messages)
          break
        }

        case 'thread_created': {
          const { target, thread_id, thread_type } = message.payload as {
            target: string
            thread_id: string
            name: string | null
            thread_type: ThreadType
          }
          console.log('Thread created:', target, thread_id, thread_type)
          // IMMEDIATELY switch to the new thread so user sees their message
          // This ensures session_updated messages for this thread are displayed
          switchPOSession(target, thread_id)
          break
        }

        case 'thread_tree': {
          // Thread tree response - could be used for navigation
          console.log('Thread tree received:', message.payload)
          break
        }

        case 'llm_config':
          setLLMConfig(message.payload as LLMConfig)
          break

        case 'llm_switched': {
          const { provider, model } = message.payload as {
            provider: string
            model: string
          }
          updateCurrentLLM(provider, model)
          break
        }

        case 'session_usage': {
          setUsageData(message.payload as Record<string, unknown>)
          break
        }

        case 'thread_export': {
          const { content, format, session_id } = message.payload as { content: string; format: string; session_id: string }
          const mimeType = format === 'json' ? 'application/json' : 'text/markdown'
          const ext = format === 'json' ? 'json' : 'md'
          const blob = new Blob([content], { type: mimeType })
          const url = URL.createObjectURL(blob)
          const a = document.createElement('a')
          a.href = url
          a.download = `${session_id}.${ext}`
          a.click()
          URL.revokeObjectURL(url)
          break
        }

        case 'error': {
          const { message: errorMsg } = message.payload as { message: string }
          console.error('Server error:', errorMsg)
          break
        }

        case 'pong':
          // Heartbeat response, ignore
          break

        default:
          console.log('Unknown message type:', message.type)
      }
    },
    [
      setEnvironment,
      setPromptObject,
      removePromptObject,
      updateSessionMessages,
      switchPOSession,
      setPendingResponse,
      clearPendingResponse,
      appendStreamChunk,
      clearStream,
      addBusMessage,
      addNotification,
      removeNotification,
      setLLMConfig,
      updateCurrentLLM,
      setUsageData,
    ]
  )

  // Connect on mount
  useEffect(() => {
    connect()

    return () => {
      if (reconnectTimeout.current) {
        clearTimeout(reconnectTimeout.current)
      }
      ws.current?.close()
    }
  }, [connect])

  // Send message to a PO
  const sendMessage = useCallback((target: string, content: string, newThread?: boolean) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    const payload: SendMessagePayload = { target, content, new_thread: newThread }
    ws.current.send(
      JSON.stringify({
        type: 'send_message',
        payload,
      })
    )
  }, [])

  // Respond to a notification
  const respondToNotification = useCallback((id: string, response: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    const payload: RespondToNotificationPayload = { id, response }
    ws.current.send(
      JSON.stringify({
        type: 'respond_to_notification',
        payload,
      })
    )
  }, [])

  // Create a new session
  const createSession = useCallback((target: string, name?: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    const payload: CreateSessionPayload = { target, name }
    ws.current.send(
      JSON.stringify({
        type: 'create_session',
        payload,
      })
    )
  }, [])

  // Switch to a different session
  const switchSession = useCallback((target: string, sessionId: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    const payload: SwitchSessionPayload = { target, session_id: sessionId }
    ws.current.send(
      JSON.stringify({
        type: 'switch_session',
        payload,
      })
    )
  }, [])

  // Switch LLM provider/model
  const switchLLM = useCallback((provider: string, model?: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    ws.current.send(
      JSON.stringify({
        type: 'switch_llm',
        payload: { provider, model },
      })
    )
  }, [])

  // Create a new thread (defaults to root thread)
  const createThread = useCallback((target: string, name?: string, threadType?: ThreadType) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    const payload: CreateThreadPayload = { target, name, thread_type: threadType }
    ws.current.send(
      JSON.stringify({
        type: 'create_thread',
        payload,
      })
    )
  }, [])

  // Request usage data for a session
  const requestUsage = useCallback((sessionId: string, includeTree?: boolean) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    ws.current.send(
      JSON.stringify({
        type: 'get_session_usage',
        payload: { session_id: sessionId, include_tree: includeTree || false },
      })
    )
  }, [])

  // Export a thread as markdown or JSON
  const exportThread = useCallback((sessionId: string, format?: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    ws.current.send(
      JSON.stringify({
        type: 'export_thread',
        payload: { session_id: sessionId, format: format || 'markdown' },
      })
    )
  }, [])

  // Update a PO's prompt (markdown body)
  const updatePrompt = useCallback((target: string, prompt: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    ws.current.send(
      JSON.stringify({
        type: 'update_prompt',
        payload: { target, prompt },
      })
    )
  }, [])

  return {
    sendMessage,
    respondToNotification,
    createSession,
    switchSession,
    switchLLM,
    createThread,
    updatePrompt,
    requestUsage,
    exportThread,
  }
}
