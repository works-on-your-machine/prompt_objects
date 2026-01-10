# Markdown Rendering

## Status: Done (via charm-native)

With charm-native providing Glamour without FFI crashes, we can use Glamour directly for markdown rendering.

## Solution

Use Glamour via charm-native with explicit style (not "auto"):

```ruby
Glamour.render(markdown, style: "dark", width: terminal_width)
```

**Key insight**: `style: "auto"` doesn't work in non-TTY contexts. Use `"dark"`, `"light"`, or `"dracula"` explicitly.

## Features Available

Glamour provides:
- Headers (styled and colored)
- Bold and italic text
- Code blocks with **syntax highlighting** (language-aware)
- Bullet and numbered lists
- Blockquotes
- Links
- Word wrapping to specified width

## Integration

Update conversation panel to render assistant messages through Glamour:

```ruby
# In conversation.rb
def render_assistant_message(content, width)
  Glamour.render(content, style: "dark", width: width)
end
```

## Style Options

| Style | Description |
|-------|-------------|
| `dark` | Dark terminal background (recommended) |
| `light` | Light terminal background |
| `dracula` | Dracula color scheme |
| `notty` | Plain text, no ANSI codes |
| `auto` | Detect TTY (unreliable in subprocess) |

## Previous Options (No Longer Needed)

The following options were considered before charm-native was available:

- **Option A: Pure Ruby ANSI Renderer** - Would require significant implementation work
- **Option B: TTY-Markdown gem** - Additional dependency with potential styling conflicts
- **Option C: Glamour** ✓ - Now works via charm-native

## Implementation Steps

1. ~~Wait for charm-native~~ ✓ Done
2. [ ] Integrate Glamour into conversation panel
3. [ ] Add style configuration (allow user to choose dark/light)
4. [ ] Handle edge cases (very wide content, nested code blocks)

## Testing

```ruby
require_relative 'lib/prompt_objects/charm'

md = <<~MD
# Hello World

This is **bold** and *italic*.

```ruby
def hello
  puts 'hi'
end
```
MD

puts Glamour.render(md, style: "dark", width: 60)
```
