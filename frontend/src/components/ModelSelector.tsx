import { useState, useRef, useEffect } from 'react'
import { useStore } from '../store'

interface Props {
  switchLLM: (provider: string, model?: string) => void
}

export function ModelSelector({ switchLLM }: Props) {
  const { llmConfig } = useStore()
  const [isOpen, setIsOpen] = useState(false)
  const dropdownRef = useRef<HTMLDivElement>(null)

  // Close dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  if (!llmConfig) return null

  const handleSelectModel = (provider: string, model: string) => {
    switchLLM(provider, model)
    setIsOpen(false)
  }

  // Provider display names
  const providerNames: Record<string, string> = {
    openai: 'OpenAI',
    anthropic: 'Anthropic',
    gemini: 'Gemini',
    ollama: 'Ollama',
    openrouter: 'OpenRouter',
  }

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 px-3 py-1.5 text-sm bg-po-border rounded hover:bg-po-accent/50 transition-colors"
      >
        <span className="text-gray-400">
          {providerNames[llmConfig.current_provider] || llmConfig.current_provider}
        </span>
        <span className="text-white font-medium">{llmConfig.current_model}</span>
        <svg
          className={`w-4 h-4 text-gray-400 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute right-0 top-full mt-2 w-64 bg-po-surface border border-po-border rounded-lg shadow-xl z-50 overflow-hidden">
          {llmConfig.providers.map((provider) => (
            <div key={provider.name}>
              <div className="px-3 py-2 bg-po-bg text-xs font-medium text-gray-400 uppercase tracking-wide flex items-center justify-between">
                <span>{providerNames[provider.name] || provider.name}</span>
                {!provider.available && (
                  <span className="text-red-400 text-[10px] normal-case">
                    {provider.name === 'ollama' ? 'Not Running' : 'No API Key'}
                  </span>
                )}
              </div>
              {provider.models.map((model) => {
                const isSelected =
                  provider.name === llmConfig.current_provider &&
                  model === llmConfig.current_model
                const isAvailable = provider.available
                const isDefault = model === provider.default_model

                return (
                  <button
                    key={`${provider.name}-${model}`}
                    onClick={() => isAvailable && handleSelectModel(provider.name, model)}
                    disabled={!isAvailable}
                    className={`w-full px-3 py-2 text-left text-sm flex items-center justify-between transition-colors ${
                      isSelected
                        ? 'bg-po-accent/20 text-po-accent'
                        : isAvailable
                        ? 'text-gray-300 hover:bg-po-border'
                        : 'text-gray-600 cursor-not-allowed'
                    }`}
                  >
                    <span className="flex items-center gap-2">
                      {model}
                      {isDefault && (
                        <span className="text-[10px] text-gray-500">(default)</span>
                      )}
                    </span>
                    {isSelected && (
                      <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                        <path
                          fillRule="evenodd"
                          d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                          clipRule="evenodd"
                        />
                      </svg>
                    )}
                  </button>
                )
              })}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
