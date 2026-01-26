# MCP Server

## Overview

PromptObjects exposes an MCP (Model Context Protocol) server for external clients like Claude Desktop, custom integrations, and other MCP-compatible tools.

The **Ruby TUI** remains the primary interface using Charm gems directly (Bubble Tea, Lipgloss, Glamour).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Ruby TUI (Primary Interface)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ Bubble Tea  │  │  Lipgloss   │  │   Glamour   │              │
│  │ (TUI frame) │  │  (styling)  │  │ (markdown)  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                           │                                      │
│              PromptObjects Engine                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Registry   │  │ MessageBus  │  │ HumanQueue  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                           │                                      │
│                    LLM Client (ruby_llm gem)                     │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ (also exposed via)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    MCP Server (for external clients)             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Tools     │  │  Resources  │  │   Prompts   │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                           │                                      │
│                    JSON-RPC over stdio                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        Claude Desktop   Custom Tools   Other MCP Clients
```

## Use Cases for MCP

1. **Claude Desktop Integration**: Let Claude interact with your prompt objects
2. **IDE Extensions**: Build VS Code or other IDE integrations
3. **Custom Workflows**: Integrate PromptObjects into automation pipelines
4. **Remote Access**: Expose over HTTP/SSE for web clients (future)

## MCP Server Design

### Tools

See [mcp-tools.md](./mcp-tools.md) for full reference.

**Core tools:**
- `list_prompt_objects` - List all POs with state
- `send_message` - Send message to a PO
- `get_conversation` - Get chat history
- `inspect_po` - Detailed PO info
- `get_pending_requests` - Human requests queue
- `respond_to_request` - Answer human requests

### Resources

```ruby
resource "po://{name}/config"   # PO configuration
resource "po://{name}/prompt"   # Raw markdown body
resource "bus://messages"       # Recent bus entries
```

### Notifications (Server → Client)

MCP supports server-initiated notifications:

```ruby
# When a PO calls ask_human
notify "human_request_added", { request_id: "...", capability: "...", question: "..." }

# When message bus has new entry
notify "bus_message", { from: "...", to: "...", message: "..." }
```

## Running

### Ruby TUI (Primary)

```bash
bundle exec ruby exe/poop_tui
```

### MCP Server (For External Clients)

```bash
# Stdio transport
bundle exec ruby exe/poop_mcp

# With custom objects directory
PROMPT_OBJECTS_DIR=/path/to/objects bundle exec ruby exe/poop_mcp
```

### Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "prompt-objects": {
      "command": "ruby",
      "args": ["/path/to/prompt-objects/exe/poop_mcp"],
      "env": {
        "PROMPT_OBJECTS_DIR": "/path/to/objects"
      }
    }
  }
}
```

## Implementation Status

- [x] **Phase 7.1**: Core MCP server with essential tools
- [ ] **Phase 7.2**: Resources (po://, bus://)
- [ ] **Phase 7.3**: Notifications for real-time updates
- [ ] **Phase 7.4**: HTTP/SSE transport for web clients

## Benefits

1. **Universal Access**: Any MCP client can interact with PromptObjects
2. **Clean Separation**: MCP for external tools, Ruby TUI for daily use
3. **No FFI Issues**: MCP uses simple JSON-RPC over stdio
4. **Future-Proof**: MCP is becoming a standard for AI tool integration

## References

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk)
- [MCP: An Accidentally Universal Plugin](https://worksonmymachine.ai/p/mcp-an-accidentally-universal-plugin)
