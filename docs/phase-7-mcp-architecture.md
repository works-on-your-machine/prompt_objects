# Phase 7: MCP Architecture - Ruby Server + Go TUI

## Motivation

The Charm Ruby gems (Bubble Tea, Lipgloss, Glamour) have Go FFI issues that prevent using multiple libraries together. Rather than working around these limitations, we adopt a cleaner architecture:

- **Ruby MCP Server**: PromptObjects engine exposed via Model Context Protocol
- **Go MCP Client + TUI**: Native Charm libraries for the terminal UI

This aligns with the "MCP as Universal Plugin" philosophy - by exposing PromptObjects via MCP, any MCP client can interact with your prompt objects (Claude Desktop, other tools, your APM app).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Go TUI (MCP Client)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ Bubble Tea  │  │  Lipgloss   │  │   Glamour   │              │
│  │ (TUI frame) │  │  (styling)  │  │ (markdown)  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                           │                                      │
│                    MCP Client SDK                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │ JSON-RPC over stdio
                            ▼
┌───────────────────────────┴─────────────────────────────────────┐
│                    Ruby MCP Server                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Tools     │  │  Resources  │  │   Prompts   │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                           │                                      │
│              PromptObjects Engine                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Registry   │  │ MessageBus  │  │ HumanQueue  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                           │                                      │
│                    LLM Adapter (OpenAI)                          │
└─────────────────────────────────────────────────────────────────┘
```

## Dependencies

### Ruby (MCP Server)
```ruby
# Gemfile
gem "mcp-ruby"  # Official Ruby SDK (github.com/modelcontextprotocol/ruby-sdk)
# OR
gem "fast-mcp"  # Alternative with nice Rails integration
```

### Go (MCP Client + TUI)
```go
// go.mod
require (
    github.com/modelcontextprotocol/go-sdk v0.x.x
    github.com/charmbracelet/bubbletea v1.x.x
    github.com/charmbracelet/lipgloss v1.x.x
    github.com/charmbracelet/glamour v0.x.x
)
```

## MCP Server Design (Ruby)

### Tools

```ruby
# Tools the TUI (or any MCP client) can call

tool "list_prompt_objects" do
  description "List all loaded prompt objects"
  # Returns: [{ name: "coordinator", description: "...", state: "idle" }, ...]
end

tool "send_message" do
  description "Send a message to a prompt object"
  parameter :po_name, type: :string, required: true
  parameter :message, type: :string, required: true
  # Returns: { response: "...", tool_calls: [...] }
end

tool "get_conversation" do
  description "Get conversation history for a prompt object"
  parameter :po_name, type: :string, required: true
  # Returns: [{ role: "user", content: "..." }, ...]
end

tool "respond_to_request" do
  description "Respond to a pending human request"
  parameter :request_id, type: :string, required: true
  parameter :response, type: :string, required: true
end

tool "get_pending_requests" do
  description "Get all pending human requests"
  # Returns: [{ id: "...", capability: "...", question: "...", age: "2m" }, ...]
end

tool "inspect_po" do
  description "Get detailed info about a prompt object"
  parameter :po_name, type: :string, required: true
  # Returns: { config: {...}, body: "...", capabilities: [...] }
end
```

### Resources

```ruby
# Resources for reading state

resource "po://{name}/config" do
  description "Configuration for a prompt object"
  # Returns YAML/JSON config
end

resource "po://{name}/prompt" do
  description "The markdown prompt body"
  # Returns raw markdown
end

resource "bus://messages" do
  description "Recent message bus entries"
  # Returns last N messages
end
```

### Notifications (Server → Client)

MCP supports server-initiated notifications:

```ruby
# When a PO calls ask_human
notify "human_request_added", { request_id: "...", capability: "...", question: "..." }

# When a PO responds
notify "po_response", { po_name: "...", message: "..." }

# When message bus has new entry
notify "bus_message", { from: "...", to: "...", message: "..." }
```

## Go TUI Design

### Structure

```
tui/
├── main.go              # Entry point, spawns Ruby MCP server
├── client/
│   └── mcp.go           # MCP client wrapper
├── models/
│   ├── app.go           # Main Bubble Tea model
│   ├── capability_bar.go
│   ├── conversation.go
│   ├── message_log.go
│   ├── notification.go
│   └── modals.go
├── views/
│   └── styles.go        # Lipgloss styles
└── messages/
    └── messages.go      # Custom Bubble Tea messages
```

### Main Flow

```go
func main() {
    // Start Ruby MCP server as subprocess
    cmd := exec.Command("ruby", "exe/prompt_objects_mcp")
    stdin, _ := cmd.StdinPipe()
    stdout, _ := cmd.StdoutPipe()
    cmd.Start()

    // Create MCP client
    client := mcp.NewClient(stdin, stdout)

    // Initialize Bubble Tea with MCP client
    app := NewApp(client)
    p := tea.NewProgram(app, tea.WithAltScreen())
    p.Run()
}
```

### Handling Notifications

```go
// Listen for MCP notifications in a goroutine
go func() {
    for notification := range client.Notifications() {
        switch notification.Method {
        case "human_request_added":
            program.Send(HumanRequestMsg{...})
        case "po_response":
            program.Send(POResponseMsg{...})
        case "bus_message":
            program.Send(BusMessageMsg{...})
        }
    }
}()
```

## Implementation Steps

### Phase 7.1: Ruby MCP Server (Core)

1. Add MCP SDK to Gemfile
2. Create `lib/prompt_objects/mcp/server.rb`
3. Implement core tools: `list_prompt_objects`, `send_message`, `get_conversation`
4. Create entry point: `exe/prompt_objects_mcp`
5. Test with MCP Inspector or Claude Desktop

### Phase 7.2: Go TUI Scaffold

1. Create `tui/` directory with Go module
2. Set up MCP client connection
3. Basic Bubble Tea app that lists POs (proves connection works)
4. Spawn Ruby subprocess

### Phase 7.3: Go TUI - Core UI

1. Port capability bar (native Lipgloss!)
2. Port conversation panel (with Glamour markdown!)
3. Port message log
4. Input handling

### Phase 7.4: Go TUI - Advanced Features

1. Notification panel
2. Request responder modal
3. PO Inspector modal
4. Keyboard shortcuts

### Phase 7.5: Polish & Integration

1. Error handling
2. Reconnection logic
3. Graceful shutdown
4. Binary distribution (single Go binary + Ruby server)

## Benefits

1. **Native Charm**: Full access to Bubble Tea, Lipgloss, Glamour without FFI issues
2. **Universal Access**: Any MCP client can use your PromptObjects
3. **Clean Separation**: UI logic in Go, business logic in Ruby
4. **Better Performance**: Go excels at TUI rendering
5. **Easier Distribution**: Go compiles to single binary

## Testing Strategy

1. Test Ruby MCP server independently with MCP Inspector
2. Test Go TUI with mock MCP server
3. Integration tests with both running

## Migration Path

1. Keep existing Ruby TUI as fallback (`exe/prompt_objects_tui`)
2. New Go TUI becomes primary (`exe/prompt_objects` or just `po`)
3. Eventually deprecate Ruby TUI

## Open Questions

1. Should we use `mcp-ruby` (official) or `fast-mcp` for the server?
2. Single binary distribution? (embed Ruby? or require Ruby runtime?)
3. Support HTTP transport for remote access later?

## References

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk)
- [Go SDK](https://github.com/modelcontextprotocol/go-sdk)
- [MCP: An Accidentally Universal Plugin](https://worksonmymachine.ai/p/mcp-an-accidentally-universal-plugin)
