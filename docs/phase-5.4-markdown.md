# Phase 5.4: Markdown Rendering for PO Output

## Problem

LLM outputs typically contain markdown formatting (headers, bold, italic, code blocks, lists). Currently, the TUI displays raw markdown text without rendering, making output harder to read.

## Current State

- Glamour gem is available but has Go FFI stability issues
- Raw markdown is displayed as-is in conversation panel
- No syntax highlighting for code blocks

## Goals

1. Render markdown formatting in assistant messages
2. Support common markdown elements:
   - Headers (# ## ###)
   - Bold (**text**) and italic (*text*)
   - Code spans (`code`) and code blocks (```)
   - Bullet lists (- item)
   - Numbered lists (1. item)
3. Maintain word wrap within terminal width
4. Fallback gracefully if rendering fails

## Options

### Option A: Pure Ruby ANSI Markdown Renderer

Build a simple markdown-to-ANSI renderer in Ruby without external dependencies.

**Pros:**
- No Go/FFI dependencies
- Full control over output
- Can integrate with existing Styles module

**Cons:**
- More work to implement
- May not handle all edge cases

**Implementation:**

**File**: `lib/prompt_objects/ui/markdown_renderer.rb`

```ruby
class MarkdownRenderer
  def render(text, width:)
    lines = []
    text.each_line do |line|
      lines.concat(render_line(line, width))
    end
    lines
  end

  private

  def render_line(line, width)
    case line
    when /^###\s+(.+)/  # H3
      [Styles.h3.render($1)]
    when /^##\s+(.+)/   # H2
      [Styles.h2.render($1)]
    when /^#\s+(.+)/    # H1
      [Styles.h1.render($1)]
    when /^```(\w*)/    # Code block start
      @in_code_block = true
      @code_lang = $1
      []
    when /^```$/        # Code block end
      @in_code_block = false
      []
    when /^[-*]\s+(.+)/ # Bullet list
      render_list_item($1, width, "•")
    when /^\d+\.\s+(.+)/ # Numbered list
      render_list_item($1, width, "#{$1}.")
    else
      if @in_code_block
        [Styles.code.render("  #{line.chomp}")]
      else
        render_inline(line, width)
      end
    end
  end

  def render_inline(text, width)
    # Handle **bold**, *italic*, `code`
    result = text
      .gsub(/\*\*(.+?)\*\*/) { Styles.bold.render($1) }
      .gsub(/\*(.+?)\*/) { Styles.italic.render($1) }
      .gsub(/`([^`]+)`/) { Styles.code_span.render($1) }
    wrap_text(result, width)
  end
end
```

### Option B: Use TTY-Markdown Gem

Use the `tty-markdown` gem which is pure Ruby.

**Pros:**
- Battle-tested implementation
- Handles edge cases

**Cons:**
- Additional dependency
- May have styling conflicts

### Option C: Wait for Glamour FFI Fix

Continue using Glamour when stable, with fallback to raw text.

**Pros:**
- Glamour handles all markdown parsing
- Rich rendering with syntax highlighting

**Cons:**
- Unknown timeline for FFI stability
- Runtime crashes possible

## Recommended Approach

**Option A: Pure Ruby ANSI Markdown Renderer**

Reasons:
1. No additional dependencies beyond what we have
2. Full control over styling to match existing TUI theme
3. Can start simple and add features incrementally
4. Integrates naturally with existing Styles module

## Implementation Steps

### Step 1: Create MarkdownRenderer Class

1. Create `lib/prompt_objects/ui/markdown_renderer.rb`
2. Implement basic block parsing (headers, lists, code blocks)
3. Implement inline parsing (bold, italic, code spans)
4. Add word wrapping support

### Step 2: Add Markdown Styles

Update `lib/prompt_objects/ui/styles.rb`:

```ruby
module Styles
  def self.h1
    Lipgloss.style(bold: true, foreground: "#FFFFFF")
  end

  def self.h2
    Lipgloss.style(bold: true, foreground: "#AAAAFF")
  end

  def self.h3
    Lipgloss.style(bold: true, foreground: "#88AAFF")
  end

  def self.bold
    Lipgloss.style(bold: true)
  end

  def self.italic
    Lipgloss.style(italic: true)
  end

  def self.code_span
    Lipgloss.style(foreground: "#FF8888", background: "#333333")
  end

  def self.code_block
    Lipgloss.style(foreground: "#AAFFAA", background: "#1A1A1A")
  end
end
```

### Step 3: Integrate with Conversation

Update `lib/prompt_objects/ui/models/conversation.rb`:

```ruby
def format_message(msg, width)
  case msg[:role]
  when :assistant
    content = msg[:content].to_s
    rendered = MarkdownRenderer.new.render(content, width: width - prefix_len)
    # ... format with prefix
  end
end
```

### Step 4: Handle Edge Cases

- Nested formatting (**bold *and italic***)
- Multi-line code blocks
- Links (display text, optionally show URL)
- Horizontal rules

## Testing

1. Test with various markdown inputs
2. Verify word wrap works with ANSI codes
3. Test code block display
4. Test list rendering at different widths

## Future Enhancements

- Syntax highlighting for code blocks (language-aware)
- Table rendering
- Image placeholders (show alt text)
- Link handling (clickable in supporting terminals)
