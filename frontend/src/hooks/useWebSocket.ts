import { useEffect, useRef, useCallback } from 'react'
import { useStore } from '../store'
import type {
  WSMessage,
  PromptObject,
  BusMessage,
  Notification,
  Environment,
  SendMessagePayload,
  RespondToNotificationPayload,
  CreateSessionPayload,
  SwitchSessionPayload,
} from '../types'

export function useWebSocket() {
  const ws = useRef<WebSocket | null>(null)
  const reconnectTimeout = useRef<number | null>(null)

  const {
    setConnected,
    setEnvironment,
    setPromptObject,
    addBusMessage,
    addNotification,
    removeNotification,
    appendStreamChunk,
    clearStream,
    setPendingResponse,
    clearPendingResponse,
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
      setPendingResponse,
      clearPendingResponse,
      appendStreamChunk,
      clearStream,
      addBusMessage,
      addNotification,
      removeNotification,
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
  const sendMessage = useCallback((target: string, content: string) => {
    if (!ws.current || ws.current.readyState !== WebSocket.OPEN) {
      console.error('WebSocket not connected')
      return
    }

    const payload: SendMessagePayload = { target, content }
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

  return {
    sendMessage,
    respondToNotification,
    createSession,
    switchSession,
  }
}
