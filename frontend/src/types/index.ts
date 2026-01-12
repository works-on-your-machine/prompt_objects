// Core types for PromptObjects frontend

export interface Message {
  role: 'user' | 'assistant' | 'tool'
  content: string | null
  from?: string
  tool_calls?: ToolCall[]
  results?: ToolResult[]
}

export interface ToolCall {
  id: string
  name: string
  arguments: Record<string, unknown>
}

export interface ToolResult {
  tool_call_id: string
  content: string
}

export interface Session {
  id: string
  name: string | null
  message_count: number
  updated_at?: string
}

export interface CurrentSession {
  id: string
  messages: Message[]
}

export interface PromptObject {
  name: string
  description: string
  status: 'idle' | 'thinking' | 'calling_tool'
  capabilities: string[]
  current_session: CurrentSession | null
  sessions: Session[]
  prompt?: string  // The markdown body/prompt
  config?: Record<string, unknown>  // The YAML frontmatter config
}

export interface BusMessage {
  from: string
  to: string
  content: string
  timestamp: string
}

export interface Notification {
  id: string
  po_name: string
  type: string
  message: string
  options: string[]
}

export interface Environment {
  name: string
  path: string
  po_count: number
  primitive_count: number
}

// LLM Provider configuration
export interface LLMProvider {
  name: string
  models: string[]
  default_model: string
  available: boolean
}

export interface LLMConfig {
  current_provider: string
  current_model: string
  providers: LLMProvider[]
}

// WebSocket message types
export type WSMessageType =
  | 'environment'
  | 'po_state'
  | 'po_response'
  | 'po_added'
  | 'po_modified'
  | 'po_removed'
  | 'stream'
  | 'stream_end'
  | 'bus_message'
  | 'notification'
  | 'notification_resolved'
  | 'session_created'
  | 'session_switched'
  | 'session_updated'
  | 'llm_config'
  | 'llm_switched'
  | 'error'
  | 'pong'

export interface WSMessage<T = unknown> {
  type: WSMessageType
  payload: T
}

// Client -> Server message types
export interface SendMessagePayload {
  target: string
  content: string
}

export interface RespondToNotificationPayload {
  id: string
  response: string
}

export interface CreateSessionPayload {
  target: string
  name?: string
}

export interface SwitchSessionPayload {
  target: string
  session_id: string
}
