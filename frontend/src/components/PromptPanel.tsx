import { useState, useEffect, useCallback, useRef } from 'react'
import type { PromptObject } from '../types'
import { MarkdownMessage } from './MarkdownMessage'

interface PromptPanelProps {
  po: PromptObject
  onSave?: (prompt: string) => void
}

export function PromptPanel({ po, onSave }: PromptPanelProps) {
  const prompt = po.prompt || ''
  const config = po.config || {}
  const [isEditing, setIsEditing] = useState(false)
  const [editedPrompt, setEditedPrompt] = useState(prompt)
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving' | 'unsaved'>('saved')
  const saveTimeoutRef = useRef<number | null>(null)

  // Sync editedPrompt when po.prompt changes from server
  useEffect(() => {
    if (!isEditing) {
      setEditedPrompt(prompt)
    }
  }, [prompt, isEditing])

  // Debounced auto-save
  const debouncedSave = useCallback((newPrompt: string) => {
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current)
    }

    setSaveStatus('unsaved')

    saveTimeoutRef.current = window.setTimeout(() => {
      if (onSave && newPrompt !== prompt) {
        setSaveStatus('saving')
        onSave(newPrompt)
        // Assume save succeeded - server will broadcast update
        setTimeout(() => setSaveStatus('saved'), 500)
      } else {
        setSaveStatus('saved')
      }
    }, 1000) // 1 second debounce
  }, [onSave, prompt])

  const handlePromptChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newPrompt = e.target.value
    setEditedPrompt(newPrompt)
    debouncedSave(newPrompt)
  }

  const handleStartEditing = () => {
    setEditedPrompt(prompt)
    setIsEditing(true)
  }

  const handleStopEditing = () => {
    // Save any pending changes
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current)
    }
    if (editedPrompt !== prompt && onSave) {
      onSave(editedPrompt)
    }
    setIsEditing(false)
    setSaveStatus('saved')
  }

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current)
      }
    }
  }, [])

  return (
    <div className="h-full overflow-auto p-4">
      {/* Config/Frontmatter */}
      <div className="mb-6">
        <h3 className="text-lg font-medium text-white mb-3">Configuration</h3>
        <div className="bg-po-bg rounded-lg border border-po-border p-4">
          <pre className="text-sm text-gray-300 font-mono whitespace-pre-wrap">
            {JSON.stringify(config, null, 2)}
          </pre>
        </div>
      </div>

      {/* Prompt/Body */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-lg font-medium text-white">Prompt</h3>
          <div className="flex items-center gap-3">
            {isEditing && (
              <span className={`text-xs ${
                saveStatus === 'saved' ? 'text-green-400' :
                saveStatus === 'saving' ? 'text-yellow-400' :
                'text-gray-400'
              }`}>
                {saveStatus === 'saved' ? 'Saved' :
                 saveStatus === 'saving' ? 'Saving...' :
                 'Unsaved changes'}
              </span>
            )}
            <button
              onClick={isEditing ? handleStopEditing : handleStartEditing}
              className={`px-3 py-1 text-sm rounded transition-colors ${
                isEditing
                  ? 'bg-po-accent text-black hover:bg-po-accent/80'
                  : 'bg-po-surface border border-po-border text-gray-300 hover:text-white hover:border-po-accent'
              }`}
            >
              {isEditing ? 'Done' : 'Edit'}
            </button>
          </div>
        </div>

        <div className="bg-po-bg rounded-lg border border-po-border">
          {isEditing ? (
            <textarea
              value={editedPrompt}
              onChange={handlePromptChange}
              className="w-full h-96 p-4 bg-transparent text-gray-200 font-mono text-sm resize-none focus:outline-none focus:ring-1 focus:ring-po-accent rounded-lg"
              placeholder="Enter prompt markdown..."
              spellCheck={false}
            />
          ) : (
            <div className="p-4">
              {prompt ? (
                <div className="prose prose-invert max-w-none">
                  <MarkdownMessage content={prompt} />
                </div>
              ) : (
                <p className="text-gray-500 italic">No prompt defined. Click Edit to add one.</p>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Raw source toggle (only in view mode) */}
      {!isEditing && (
        <details className="mt-6">
          <summary className="text-sm text-gray-400 cursor-pointer hover:text-white">
            View raw source
          </summary>
          <div className="mt-2 bg-po-bg rounded-lg border border-po-border p-4">
            <pre className="text-xs text-gray-400 font-mono whitespace-pre-wrap overflow-x-auto">
              {prompt || '(empty)'}
            </pre>
          </div>
        </details>
      )}
    </div>
  )
}
