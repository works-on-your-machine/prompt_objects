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
                className="bg-po-surface-2 px-1 py-0.5 rounded text-po-accent font-mono text-[0.9em]"
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
            return <p className="mb-2 last:mb-0">{children}</p>
          },
          // Styled lists
          ul({ children }) {
            return <ul className="list-disc list-inside mb-2 space-y-0.5">{children}</ul>
          },
          ol({ children }) {
            return <ol className="list-decimal list-inside mb-2 space-y-0.5">{children}</ol>
          },
          // Styled headings
          h1({ children }) {
            return <h1 className="text-base font-bold mb-1.5 mt-3 first:mt-0 text-po-text-primary">{children}</h1>
          },
          h2({ children }) {
            return <h2 className="text-sm font-bold mb-1.5 mt-2 first:mt-0 text-po-text-primary">{children}</h2>
          },
          h3({ children }) {
            return <h3 className="text-xs font-bold mb-1 mt-1.5 first:mt-0 text-po-text-primary">{children}</h3>
          },
          // Styled blockquotes
          blockquote({ children }) {
            return (
              <blockquote className="border-l-2 border-po-accent pl-3 my-2 text-po-text-secondary italic">
                {children}
              </blockquote>
            )
          },
          // Styled tables
          table({ children }) {
            return (
              <div className="overflow-x-auto my-2">
                <table className="min-w-full border border-po-border text-xs">{children}</table>
              </div>
            )
          },
          th({ children }) {
            return (
              <th className="border border-po-border bg-po-surface-2 px-2 py-1 text-left font-medium text-po-text-primary">
                {children}
              </th>
            )
          },
          td({ children }) {
            return (
              <td className="border border-po-border px-2 py-1 text-po-text-secondary">{children}</td>
            )
          },
          // Horizontal rule
          hr() {
            return <hr className="border-po-border my-3" />
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
    <div className="relative group my-2">
      {/* Language label and copy button */}
      <div className="flex items-center justify-between bg-po-surface-2 px-2.5 py-1 rounded-t border border-b-0 border-po-border">
        <span className="text-2xs text-po-text-ghost font-mono">
          {language || 'text'}
        </span>
        <button
          onClick={handleCopy}
          className="text-2xs text-po-text-ghost hover:text-po-text-primary transition-colors duration-150"
        >
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      {/* Code with syntax highlighting */}
      <SyntaxHighlighter
        style={oneDark}
        language={language || 'text'}
        PreTag="div"
        customStyle={{
          margin: 0,
          borderRadius: '0 0 0.25rem 0.25rem',
          border: '1px solid #3d3a37',
          borderTop: 'none',
          fontSize: '11px',
          background: '#222120',
        }}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  )
}
