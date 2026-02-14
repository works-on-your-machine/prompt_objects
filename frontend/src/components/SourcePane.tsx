import { useState, useEffect, useCallback, useRef } from 'react'
import type { PromptObject, CapabilityInfo } from '../types'

interface SourcePaneProps {
  po: PromptObject
  selectedCapability: CapabilityInfo | null
  onSave?: (prompt: string) => void
}

export function SourcePane({ po, selectedCapability, onSave }: SourcePaneProps) {
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
        setTimeout(() => setSaveStatus('saved'), 500)
      } else {
        setSaveStatus('saved')
      }
    }, 1000)
  }, [onSave, prompt])

  const handlePromptChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newPrompt = e.target.value
    setEditedPrompt(newPrompt)
    debouncedSave(newPrompt)
  }

  const handleToggleEdit = () => {
    if (isEditing) {
      // Save on exit
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current)
      }
      if (editedPrompt !== prompt && onSave) {
        onSave(editedPrompt)
      }
      setIsEditing(false)
      setSaveStatus('saved')
    } else {
      setEditedPrompt(prompt)
      setIsEditing(true)
    }
  }

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current)
      }
    }
  }, [])

  // Capability detail view
  if (selectedCapability) {
    return (
      <div className="flex-1 overflow-auto bg-po-bg">
        <div className="px-3 py-2 border-b border-po-border bg-po-surface">
          <span className="font-mono text-xs text-po-accent">{selectedCapability.name}</span>
        </div>
        <div className="p-3 space-y-3">
          <p className="text-xs text-po-text-secondary">{selectedCapability.description}</p>
          {selectedCapability.parameters && (
            <ParametersView parameters={selectedCapability.parameters} />
          )}
        </div>
      </div>
    )
  }

  // Prompt source view
  return (
    <div className="flex-1 overflow-auto bg-po-bg flex flex-col">
      {/* Header with edit toggle and save status */}
      <div className="px-3 py-1.5 border-b border-po-border bg-po-surface flex items-center gap-2 flex-shrink-0">
        <span className="text-2xs text-po-text-ghost uppercase tracking-wider flex-1">Source</span>

        {isEditing && (
          <span className="flex items-center gap-1">
            <span className={`w-1.5 h-1.5 rounded-full ${
              saveStatus === 'saved' ? 'bg-po-success' :
              saveStatus === 'saving' ? 'bg-po-accent animate-pulse' :
              'bg-po-text-ghost'
            }`} />
            <span className={`text-2xs ${
              saveStatus === 'saved' ? 'text-po-success' :
              saveStatus === 'saving' ? 'text-po-accent' :
              'text-po-text-ghost'
            }`}>
              {saveStatus === 'saved' ? 'saved' : saveStatus === 'saving' ? 'saving' : 'unsaved'}
            </span>
          </span>
        )}

        <button
          onClick={handleToggleEdit}
          className={`text-2xs px-1.5 py-0.5 rounded transition-colors duration-150 ${
            isEditing
              ? 'bg-po-accent text-po-bg'
              : 'text-po-text-tertiary hover:text-po-text-primary hover:bg-po-surface-2'
          }`}
        >
          {isEditing ? 'Done' : 'Edit'}
        </button>
      </div>

      {/* Config (collapsed) */}
      {Object.keys(config).length > 0 && (
        <details className="border-b border-po-border">
          <summary className="px-3 py-1 text-2xs text-po-text-ghost cursor-pointer hover:text-po-text-secondary transition-colors duration-150">
            Frontmatter
          </summary>
          <pre className="px-3 pb-2 text-2xs text-po-text-tertiary font-mono whitespace-pre-wrap">
            {JSON.stringify(config, null, 2)}
          </pre>
        </details>
      )}

      {/* Prompt content */}
      {isEditing ? (
        <textarea
          value={editedPrompt}
          onChange={handlePromptChange}
          className="flex-1 w-full p-3 bg-transparent text-po-text-primary font-mono text-xs resize-none focus:outline-none"
          placeholder="Enter prompt markdown..."
          spellCheck={false}
        />
      ) : (
        <pre className="flex-1 p-3 text-xs text-po-text-secondary font-mono whitespace-pre-wrap overflow-auto">
          {prompt || '(empty)'}
        </pre>
      )}
    </div>
  )
}

function ParametersView({ parameters }: { parameters: Record<string, unknown> }) {
  const properties = (parameters.properties as Record<string, unknown>) || {}
  const required = (parameters.required as string[]) || []

  const propertyNames = Object.keys(properties)
  if (propertyNames.length === 0) return null

  return (
    <div>
      <div className="text-2xs text-po-text-ghost uppercase tracking-wider mb-1.5">Parameters</div>
      <div className="space-y-1.5">
        {propertyNames.map((propName) => {
          const prop = properties[propName] as Record<string, unknown>
          const isRequired = required.includes(propName)
          const propType = prop.type ? String(prop.type) : null
          const propDescription = prop.description ? String(prop.description) : null
          const propEnum = prop.enum as string[] | undefined

          return (
            <div key={propName} className="bg-po-surface rounded p-2">
              <div className="flex items-center gap-1.5">
                <span className="font-mono text-2xs text-po-accent">{propName}</span>
                {propType && <span className="text-2xs text-po-text-ghost">({propType})</span>}
                {isRequired && <span className="text-2xs text-po-error">req</span>}
              </div>
              {propDescription && (
                <p className="text-2xs text-po-text-tertiary mt-0.5">{propDescription}</p>
              )}
              {propEnum && propEnum.length > 0 && (
                <div className="mt-1 flex flex-wrap gap-1">
                  {propEnum.map((val) => (
                    <span key={val} className="text-2xs bg-po-surface-2 px-1 py-0.5 rounded text-po-text-ghost">
                      {val}
                    </span>
                  ))}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
