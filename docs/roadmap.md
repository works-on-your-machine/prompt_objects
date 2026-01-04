# PromptObjects Backend Roadmap

## Completed

### Phase 1-4: Core Framework
- PromptObject class with LLM integration
- Registry and capability resolution
- Message bus for inter-PO communication
- Primitives: read_file, list_files, write_file, http_get
- Universal capabilities: ask_human, think, add_capability

### Phase 5: Ruby TUI (Legacy)
- Bubble Tea Ruby TUI (has FFI issues with Charm gems)
- Conversation panel, capability bar
- Notification system for human requests
- **Status**: Replaced by Go TUI in Phase 7

### Phase 7.1: MCP Server
- Model Context Protocol server over stdio
- Tools: list_prompt_objects, send_message, get_conversation, etc.
- Resources: po://, bus://
- See [mcp-tools.md](./mcp-tools.md) for full reference

## Planned

### Phase 6: Multiple Sessions
Named conversation sessions per PO.

**Backend features needed:**
- Session storage (file-based or in-memory)
- Session switching API
- Session listing and management

See [phase-6-sessions.md](./phase-6-sessions.md)

### Streaming Responses
Send LLM tokens as MCP notifications for real-time display.

**Implementation:**
- Add streaming support to LLM adapter
- Send `token` notifications as they arrive
- TUI subscribes and updates display

### PO Management via MCP
Create, edit, delete POs from clients.

**New tools:**
- `create_po` - Create new PO from name + prompt
- `update_po` - Update PO configuration
- `delete_po` - Remove a PO

## Related Projects

- [prompt-objects-tui](../prompt-objects-tui/) - Go TUI frontend
