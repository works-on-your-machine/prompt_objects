import type { PromptObject } from '../types'
import { MarkdownMessage } from './MarkdownMessage'

interface PromptPanelProps {
  po: PromptObject
}

export function PromptPanel({ po }: PromptPanelProps) {
  const prompt = po.prompt || ''
  const config = po.config || {}

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
        <h3 className="text-lg font-medium text-white mb-3">Prompt</h3>
        <div className="bg-po-bg rounded-lg border border-po-border p-4">
          {prompt ? (
            <div className="prose prose-invert max-w-none">
              <MarkdownMessage content={prompt} />
            </div>
          ) : (
            <p className="text-gray-500 italic">No prompt defined</p>
          )}
        </div>
      </div>

      {/* Raw source toggle */}
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
    </div>
  )
}
