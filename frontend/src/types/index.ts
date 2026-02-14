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
  name?: string  // Name of the tool that was called
  content: string
}

export type ThreadType = 'root' | 'continuation' | 'delegation' | 'fork'

export interface Session {
  id: string
  name: string | null
  message_count: number
  updated_at?: string
  // Thread fields
  parent_session_id?: string
  parent_po?: string
  thread_type: ThreadType
}

export interface ThreadTree {
  session: Session
  children: ThreadTree[]
}

export interface CurrentSession {
  id: string
  messages: Message[]
}

export interface CapabilityInfo {
  name: string
  description: string
  parameters?: Record<string, unknown>
}

// Alias for backwards compatibility
export type UniversalCapability = CapabilityInfo

export interface PromptObject {
  name: string
  description: string
  status: 'idle' | 'thinking' | 'calling_tool'
  capabilities: CapabilityInfo[]
  universal_capabilities?: CapabilityInfo[]
  current_session: CurrentSession | null
  sessions: Session[]
  prompt?: string  // The markdown body/prompt
  config?: Record<string, unknown>  // The YAML frontmatter config
  delegated_by?: string | null  // Name of the PO that called this one (set by delegation events)
}

export interface BusMessage {
  from: string
  to: string
  content: string | Record<string, unknown>
  summary?: string
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
  | 'po_delegation_started'
  | 'po_delegation_completed'
  | 'stream'
  | 'stream_end'
  | 'bus_message'
  | 'notification'
  | 'notification_resolved'
  | 'session_created'
  | 'session_switched'
  | 'session_updated'
  | 'thread_created'
  | 'thread_tree'
  | 'llm_config'
  | 'llm_switched'
  | 'session_usage'
  | 'thread_export'
  | 'prompt_updated'
  | 'llm_error'
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
  new_thread?: boolean  // If true, create a new thread before sending
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

export interface CreateThreadPayload {
  target: string
  name?: string
  thread_type?: ThreadType
}
