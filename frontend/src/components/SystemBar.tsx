import { useStore, useNotificationCount } from '../store'
import { ModelSelector } from './ModelSelector'

interface Props {
  switchLLM: (provider: string, model?: string) => void
}

export function SystemBar({ switchLLM }: Props) {
  const { connected, environment, toggleBus, busOpen, currentView, setCurrentView } =
    useStore()
  const notificationCount = useNotificationCount()

  return (
    <header className="h-8 bg-po-surface-2 border-b border-po-border flex items-center px-3 gap-3 flex-shrink-0">
      {/* Logo / Environment */}
      <div className="flex items-center gap-1.5 text-xs">
        <span className="font-mono text-po-text-primary font-medium">PromptObjects</span>
        {environment && (
          <>
            <span className="text-po-text-ghost">/</span>
            <span className="text-po-text-secondary">{environment.name}</span>
          </>
        )}
      </div>

      <div className="flex-1" />

      {/* Connection dot */}
      <div
        className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${
          connected ? 'bg-po-success' : 'bg-po-error animate-pulse'
        }`}
        title={connected ? 'Connected' : 'Disconnected'}
      />

      {/* Model selector */}
      <ModelSelector switchLLM={switchLLM} />

      {/* Notification count */}
      {notificationCount > 0 && (
        <span
          className="text-2xs font-mono bg-po-warning text-po-bg px-1.5 py-0.5 rounded font-bold"
          title={`${notificationCount} pending requests`}
        >
          {notificationCount}
        </span>
      )}

      {/* Canvas toggle */}
      <button
        onClick={() => setCurrentView(currentView === 'canvas' ? 'dashboard' : 'canvas')}
        className={`text-xs px-2 py-0.5 rounded transition-colors duration-150 ${
          currentView === 'canvas'
            ? 'bg-po-accent text-po-bg font-medium'
            : 'text-po-text-secondary hover:text-po-text-primary hover:bg-po-surface-3'
        }`}
      >
        Canvas
      </button>

      {/* Transcript toggle */}
      <button
        onClick={toggleBus}
        className={`text-xs px-2 py-0.5 rounded transition-colors duration-150 ${
          busOpen
            ? 'bg-po-accent text-po-bg font-medium'
            : 'text-po-text-secondary hover:text-po-text-primary hover:bg-po-surface-3'
        }`}
      >
        Transcript
      </button>
    </header>
  )
}
