import { useWebSocket } from './hooks/useWebSocket'
import { useStore, useSelectedPO } from './store'
import { useResize } from './hooks/useResize'
import { SystemBar } from './components/SystemBar'
import { ObjectList } from './components/ObjectList'
import { Inspector } from './components/Inspector'
import { Transcript } from './components/Transcript'
import { NotificationPanel } from './components/NotificationPanel'
import { UsagePanel } from './components/UsagePanel'
import { CanvasView } from './canvas/CanvasView'

export default function App() {
  const { sendMessage, respondToNotification, createSession, switchSession, switchLLM, createThread, updatePrompt, requestUsage, exportThread, requestEnvData } =
    useWebSocket()
  const { selectedPO, busOpen, notifications, usageData, clearUsageData, currentView } = useStore()
  const selectedPOData = useSelectedPO()

  const objectListResize = useResize({
    direction: 'horizontal',
    initialSize: 192,
    minSize: 120,
    maxSize: 320,
  })

  const transcriptResize = useResize({
    direction: 'vertical',
    initialSize: 180,
    minSize: 80,
    maxSize: 400,
    inverted: true,
  })

  return (
    <div className="h-screen flex flex-col bg-po-bg">
      <SystemBar switchLLM={switchLLM} />

      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Main view area */}
        <div className="flex-1 flex overflow-hidden">
          {currentView === 'canvas' ? (
            <CanvasView />
          ) : (
            <>
              {/* Object List - resizable */}
              <div style={{ width: objectListResize.size }} className="flex-shrink-0">
                <ObjectList />
              </div>

              {/* Resize handle */}
              <div
                className="resize-handle"
                onMouseDown={objectListResize.onMouseDown}
              />

              {/* Main content */}
              <main className="flex-1 overflow-hidden flex flex-col">
                {selectedPO && selectedPOData ? (
                  <Inspector
                    po={selectedPOData}
                    sendMessage={sendMessage}
                    createSession={createSession}
                    switchSession={switchSession}
                    createThread={createThread}
                    updatePrompt={updatePrompt}
                    requestUsage={requestUsage}
                    exportThread={exportThread}
                    requestEnvData={requestEnvData}
                  />
                ) : (
                  <div className="h-full flex items-center justify-center text-po-text-ghost">
                    <span className="font-mono text-xs">Select an object</span>
                  </div>
                )}
              </main>
            </>
          )}
        </div>

        {/* Transcript - resizable bottom pane, visible in both views */}
        {busOpen && (
          <>
            <div
              className="resize-handle-h"
              onMouseDown={transcriptResize.onMouseDown}
            />
            <div style={{ height: transcriptResize.size }} className="flex-shrink-0">
              <Transcript />
            </div>
          </>
        )}
      </div>

      {/* Notification panel - floating */}
      {notifications.length > 0 && (
        <NotificationPanel respondToNotification={respondToNotification} />
      )}

      {/* Usage panel modal */}
      {usageData && (
        <UsagePanel usage={usageData as any} onClose={clearUsageData} />
      )}
    </div>
  )
}
