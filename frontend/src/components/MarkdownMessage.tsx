import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter'
import { oneDark } from 'react-syntax-highlighter/dist/esm/styles/prism'
import { useState } from 'react'

interface MarkdownMessageProps {
  content: string
  className?: string
}

export function MarkdownMessage({ content, className = '' }: MarkdownMessageProps) {
  return (
    <div className={`markdown-content ${className}`}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          // Code blocks with syntax highlighting
          code({ className, children, ...props }) {
            const match = /language-(\w+)/.exec(className || '')
            const language = match ? match[1] : ''
            const codeString = String(children).replace(/\n$/, '')
            const isBlock = codeString.includes('\n') || match

            if (isBlock) {
              return (
                <CodeBlock language={language} code={codeString} />
              )
            }

            return (
              <code
                className="bg-po-bg px-1.5 py-0.5 rounded text-po-accent font-mono text-sm"
                {...props}
              >
                {children}
              </code>
            )
          },
          // Styled links
          a({ href, children }) {
            return (
              <a
                href={href}
                target="_blank"
                rel="noopener noreferrer"
                className="text-po-accent hover:underline"
              >
                {children}
              </a>
            )
          },
          // Styled paragraphs
          p({ children }) {
            return <p className="mb-3 last:mb-0">{children}</p>
          },
          // Styled lists
          ul({ children }) {
            return <ul className="list-disc list-inside mb-3 space-y-1">{children}</ul>
          },
          ol({ children }) {
            return <ol className="list-decimal list-inside mb-3 space-y-1">{children}</ol>
          },
          // Styled headings
          h1({ children }) {
            return <h1 className="text-xl font-bold mb-2 mt-4 first:mt-0">{children}</h1>
          },
          h2({ children }) {
            return <h2 className="text-lg font-bold mb-2 mt-3 first:mt-0">{children}</h2>
          },
          h3({ children }) {
            return <h3 className="text-base font-bold mb-2 mt-2 first:mt-0">{children}</h3>
          },
          // Styled blockquotes
          blockquote({ children }) {
            return (
              <blockquote className="border-l-4 border-po-accent pl-4 my-3 text-gray-400 italic">
                {children}
              </blockquote>
            )
          },
          // Styled tables
          table({ children }) {
            return (
              <div className="overflow-x-auto my-3">
                <table className="min-w-full border border-po-border">{children}</table>
              </div>
            )
          },
          th({ children }) {
            return (
              <th className="border border-po-border bg-po-bg px-3 py-2 text-left font-medium">
                {children}
              </th>
            )
          },
          td({ children }) {
            return (
              <td className="border border-po-border px-3 py-2">{children}</td>
            )
          },
          // Horizontal rule
          hr() {
            return <hr className="border-po-border my-4" />
          },
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  )
}

function CodeBlock({ language, code }: { language: string; code: string }) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="relative group my-3">
      {/* Language label and copy button */}
      <div className="flex items-center justify-between bg-po-bg/80 px-3 py-1 rounded-t border border-b-0 border-po-border">
        <span className="text-xs text-gray-500 font-mono">
          {language || 'text'}
        </span>
        <button
          onClick={handleCopy}
          className="text-xs text-gray-400 hover:text-white transition-colors"
        >
          {copied ? 'Copied!' : 'Copy'}
        </button>
      </div>
      {/* Code with syntax highlighting */}
      <SyntaxHighlighter
        style={oneDark}
        language={language || 'text'}
        PreTag="div"
        customStyle={{
          margin: 0,
          borderRadius: '0 0 0.375rem 0.375rem',
          border: '1px solid rgb(55, 65, 81)',
          borderTop: 'none',
        }}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  )
}
