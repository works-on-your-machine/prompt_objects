# Thread Export: Full Delegation Chain as Markdown

## Goal

Export a complete thread — including all cross-PO delegation sub-threads — as a single markdown file that shows every PO involved, every tool call with parameters, every tool result, and the delegation flow between POs.

## Current State

**Already implemented (single session):**
- `store.export_session_markdown(session_id)` — exports one session with messages, tool calls in `<details>` blocks
- `store.export_session_json(session_id)` — same as JSON
- `store.export_all_sessions(po_name:, format:)` — all sessions for one PO

**Already implemented (delegation tracking):**
- `parent_session_id`, `parent_po`, `parent_message_id` fields in sessions table
- `store.get_thread_tree(session_id)` — recursive tree of all child threads
- `store.get_thread_lineage(session_id)` — path from root to current
- `store.get_child_threads(session_id)` — direct children

**What's missing:**
- No method to export a full tree (root + all descendants across POs)
- No way to trigger export from the web UI
- No stitching of cross-PO threads into one coherent document

## Design

### How Delegation Chains Work

```
PO: solver (session S1)
  User: "Read /tmp/test.txt and summarize"
  Assistant: [tool_call: reader] ← calls reader PO
    PO: reader (session S2, parent=S1, parent_po=solver)
      User: {"message": "Read /tmp/test.txt"}  ← from solver
      Assistant: [tool_call: read_file] ← calls primitive
      Tool: [result: "file contents..."]
      Assistant: "The file contains..."
  Tool: [result: "The file contains..."] ← back in solver
  Assistant: "Here's the summary..."
```

The export should show this nesting with clear PO attribution.

### Phase 1: Backend — `export_thread_tree`

**File:** `lib/prompt_objects/session/store.rb`

```ruby
# Export a full thread tree as a single markdown document.
# Follows all delegation sub-threads recursively.
# @param session_id [String] Root session ID
# @return [String] Markdown content
def export_thread_tree_markdown(session_id)
  tree = get_thread_tree(session_id)
  return nil unless tree

  lines = []
  lines << "# Thread Export"
  lines << ""
  lines << "- **Root PO**: #{tree[:session][:po_name]}"
  lines << "- **Started**: #{tree[:session][:created_at]&.strftime('%Y-%m-%d %H:%M')}"
  lines << "- **Exported**: #{Time.now.strftime('%Y-%m-%d %H:%M')}"
  lines << ""
  lines << "---"
  lines << ""

  render_thread_node(tree, lines, depth: 0)
  lines.join("\n")
end

private

def render_thread_node(node, lines, depth:)
  session = node[:session]
  messages = get_messages(session[:id])
  indent = "  " * depth
  po_name = session[:po_name]

  # Thread header
  if depth == 0
    lines << "## #{po_name}"
  else
    type_label = session[:thread_type] == "delegation" ? "Delegation" : session[:thread_type].capitalize
    lines << ""
    lines << "#{indent}### #{type_label} → #{po_name}"
    lines << "#{indent}*Created by #{session[:parent_po]}*"
  end
  lines << ""

  # Messages
  messages.each do |msg|
    case msg[:role]
    when :user
      from = msg[:from_po] || "human"
      lines << "#{indent}**#{from}:**"
      lines << ""
      lines << "#{indent}#{msg[:content]}"
      lines << ""
    when :assistant
      lines << "#{indent}**#{po_name}:**"
      lines << ""
      if msg[:content]
        msg[:content].each_line { |l| lines << "#{indent}#{l.rstrip}" }
        lines << ""
      end
      if msg[:tool_calls]
        msg[:tool_calls].each do |tc|
          tc_name = tc[:name] || tc["name"]
          tc_args = tc[:arguments] || tc["arguments"] || {}
          lines << "#{indent}<details>"
          lines << "#{indent}<summary>Tool call: <code>#{tc_name}</code></summary>"
          lines << ""
          lines << "#{indent}```json"
          JSON.pretty_generate(tc_args).each_line { |l| lines << "#{indent}#{l.rstrip}" }
          lines << "#{indent}```"
          lines << "#{indent}</details>"
          lines << ""
        end
      end
    when :tool
      results = msg[:tool_results] || msg[:results] || []
      results.each do |r|
        r_name = r[:name] || r["name"] || "tool"
        r_content = r[:content] || r["content"] || ""
        lines << "#{indent}<details>"
        lines << "#{indent}<summary>Result from <code>#{r_name}</code></summary>"
        lines << ""
        lines << "#{indent}```"
        # Truncate very long results
        display = r_content.to_s.length > 2000 ? r_content.to_s[0, 2000] + "\n... (truncated)" : r_content.to_s
        display.each_line { |l| lines << "#{indent}#{l.rstrip}" }
        lines << "#{indent}```"
        lines << "#{indent}</details>"
        lines << ""
      end
    end
  end

  # Recurse into children (delegation sub-threads)
  (node[:children] || []).each do |child|
    render_thread_node(child, lines, depth: depth + 1)
  end
end
```

Also add JSON variant:

```ruby
def export_thread_tree_json(session_id)
  tree = get_thread_tree(session_id)
  return nil unless tree

  serialize_tree_for_export(tree)
end

def serialize_tree_for_export(node)
  session = node[:session]
  messages = get_messages(session[:id])

  {
    session: {
      id: session[:id],
      po_name: session[:po_name],
      name: session[:name],
      thread_type: session[:thread_type],
      parent_po: session[:parent_po],
      created_at: session[:created_at]&.iso8601,
    },
    messages: messages.map { |m|
      {
        role: m[:role].to_s,
        content: m[:content],
        from_po: m[:from_po],
        tool_calls: m[:tool_calls],
        tool_results: m[:tool_results],
        usage: m[:usage],  # if token tracking is implemented
        created_at: m[:created_at]&.iso8601
      }
    },
    children: (node[:children] || []).map { |c| serialize_tree_for_export(c) }
  }
end
```

### Phase 2: REST + WebSocket API

**File:** `lib/prompt_objects/server/api/routes.rb`

```
GET /api/sessions/:id/export?format=markdown → raw markdown text
GET /api/sessions/:id/export?format=json → JSON tree
```

**File:** `lib/prompt_objects/server/websocket_handler.rb`

```ruby
when "export_thread"
  handle_export_thread(message["payload"])

def handle_export_thread(payload)
  session_id = payload["session_id"]
  format = payload["format"] || "markdown"

  content = case format
            when "markdown"
              @runtime.session_store.export_thread_tree_markdown(session_id)
            when "json"
              JSON.pretty_generate(@runtime.session_store.export_thread_tree_json(session_id))
            end

  send_message(
    type: "thread_export",
    payload: { session_id: session_id, format: format, content: content }
  )
end
```

### Phase 3: Frontend — Context Menu + Download

**File:** `frontend/src/components/ThreadsSidebar.tsx`

Add "Export thread" to the context menu (shares the ContextMenu component from token tracking feature):

```tsx
{ label: 'Export as Markdown', onClick: () => exportThread(session.id, 'markdown') },
{ label: 'Export as JSON', onClick: () => exportThread(session.id, 'json') },
```

**File:** `frontend/src/hooks/useWebSocket.ts`

Handle `thread_export` response by triggering a browser download:

```tsx
case 'thread_export': {
  const { content, format } = message.payload
  const blob = new Blob([content], { type: format === 'json' ? 'application/json' : 'text/markdown' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `thread-export.${format === 'json' ? 'json' : 'md'}`
  a.click()
  URL.revokeObjectURL(url)
  break
}
```

## Example Output

```markdown
# Thread Export

- **Root PO**: solver
- **Started**: 2025-02-06 14:30
- **Exported**: 2025-02-06 15:45

---

## solver

**human:**

Read the file at /tmp/data.csv and tell me what patterns you see.

**solver:**

<details>
<summary>Tool call: <code>observer</code></summary>

```json
{
  "message": "Read and analyze the file at /tmp/data.csv"
}
```
</details>

  ### Delegation → observer
  *Created by solver*

  **solver:**

  Read and analyze the file at /tmp/data.csv

  **observer:**

  <details>
  <summary>Tool call: <code>read_file</code></summary>

  ```json
  {
    "path": "/tmp/data.csv"
  }
  ```
  </details>

  <details>
  <summary>Result from <code>read_file</code></summary>

  ```
  name,value,category
  alpha,42,A
  beta,17,B
  ...
  ```
  </details>

  **observer:**

  I found 3 columns and 100 rows. The data shows...

**solver:**

Based on the observer's analysis, here are the patterns...
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/prompt_objects/session/store.rb` | Add `export_thread_tree_markdown`, `export_thread_tree_json` |
| `lib/prompt_objects/server/api/routes.rb` | Add export REST endpoint |
| `lib/prompt_objects/server/websocket_handler.rb` | Add export WebSocket handler |
| `frontend/src/components/ThreadsSidebar.tsx` | Add export to context menu |
| `frontend/src/hooks/useWebSocket.ts` | Handle thread_export response |
| `test/unit/session/export_test.rb` | **Create** — test tree export with delegations |

## Testing

- Unit: Export single session (no children) produces valid markdown
- Unit: Export with delegation child threads shows nesting
- Unit: Export with multiple levels of delegation
- Unit: Tool calls and results are properly formatted
- Unit: Long tool results are truncated
- Integration: Export from web UI triggers download
