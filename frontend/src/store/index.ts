import { create } from 'zustand'
import { useShallow } from 'zustand/react/shallow'
import type {
  PromptObject,
  BusMessage,
  Notification,
  Environment,
} from '../types'

interface Store {
  // Connection state
  connected: boolean
  setConnected: (connected: boolean) => void

  // Environment
  environment: Environment | null
  setEnvironment: (env: Environment) => void

  // Prompt Objects
  promptObjects: Record<string, PromptObject>
  setPromptObject: (name: string, state: Partial<PromptObject>) => void
  updatePromptObjectStatus: (name: string, status: PromptObject['status']) => void

  // Navigation
  selectedPO: string | null
  selectPO: (name: string | null) => void
  activeTab: 'chat' | 'sessions' | 'capabilities' | 'edit'
  setActiveTab: (tab: Store['activeTab']) => void

  // Message Bus
  busMessages: BusMessage[]
  addBusMessage: (message: BusMessage) => void
  busOpen: boolean
  toggleBus: () => void

  // Notifications
  notifications: Notification[]
  addNotification: (notification: Notification) => void
  removeNotification: (id: string) => void

  // Streaming
  streamingContent: Record<string, string>
  appendStreamChunk: (poName: string, chunk: string) => void
  clearStream: (poName: string) => void

  // Response handling
  pendingResponse: Record<string, string>
  setPendingResponse: (poName: string, content: string) => void
  clearPendingResponse: (poName: string) => void
}

export const useStore = create<Store>((set) => ({
  // Connection
  connected: false,
  setConnected: (connected) => set({ connected }),

  // Environment
  environment: null,
  setEnvironment: (environment) => set({ environment }),

  // Prompt Objects
  promptObjects: {},
  setPromptObject: (name, state) =>
    set((s) => ({
      promptObjects: {
        ...s.promptObjects,
        [name]: {
          ...s.promptObjects[name],
          ...state,
          name, // Ensure name is always set
        } as PromptObject,
      },
    })),
  updatePromptObjectStatus: (name, status) =>
    set((s) => ({
      promptObjects: {
        ...s.promptObjects,
        [name]: {
          ...s.promptObjects[name],
          status,
        },
      },
    })),

  // Navigation
  selectedPO: null,
  selectPO: (name) => set({ selectedPO: name, activeTab: 'chat' }),
  activeTab: 'chat',
  setActiveTab: (activeTab) => set({ activeTab }),

  // Message Bus
  busMessages: [],
  addBusMessage: (message) =>
    set((s) => ({
      busMessages: [...s.busMessages.slice(-99), message], // Keep last 100
    })),
  busOpen: false,
  toggleBus: () => set((s) => ({ busOpen: !s.busOpen })),

  // Notifications
  notifications: [],
  addNotification: (notification) =>
    set((s) => ({
      notifications: [...s.notifications, notification],
    })),
  removeNotification: (id) =>
    set((s) => ({
      notifications: s.notifications.filter((n) => n.id !== id),
    })),

  // Streaming
  streamingContent: {},
  appendStreamChunk: (poName, chunk) =>
    set((s) => ({
      streamingContent: {
        ...s.streamingContent,
        [poName]: (s.streamingContent[poName] || '') + chunk,
      },
    })),
  clearStream: (poName) =>
    set((s) => {
      const { [poName]: _, ...rest } = s.streamingContent
      return { streamingContent: rest }
    }),

  // Response handling
  pendingResponse: {},
  setPendingResponse: (poName, content) =>
    set((s) => ({
      pendingResponse: {
        ...s.pendingResponse,
        [poName]: content,
      },
    })),
  clearPendingResponse: (poName) =>
    set((s) => {
      const { [poName]: _, ...rest } = s.pendingResponse
      return { pendingResponse: rest }
    }),
}))

// Selectors - use useShallow to prevent infinite re-renders with derived arrays
export const usePromptObjects = () =>
  useStore(useShallow((s) => Object.values(s.promptObjects)))

export const useSelectedPO = () =>
  useStore((s) => (s.selectedPO ? s.promptObjects[s.selectedPO] : null))

export const useNotificationCount = () =>
  useStore((s) => s.notifications.length)

export const usePONotifications = (poName: string) =>
  useStore(useShallow((s) => s.notifications.filter((n) => n.po_name === poName)))
