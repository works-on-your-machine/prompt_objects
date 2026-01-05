# PromptObjects Roadmap

## Architecture

PromptObjects is a unified Ruby project with:
- **Core Framework**: PromptObject, Capability, Registry, MessageBus
- **Ruby TUI**: Bubble Tea + Lipgloss + Glamour (Charm gems)
- **MCP Server**: For external clients (Claude Desktop, etc.)

## Completed

### Phase 1-4: Core Framework
- PromptObject class with LLM integration
- Registry and capability resolution
- Message bus for inter-PO communication
- Primitives: read_file, list_files, write_file, http_get
- Universal capabilities: ask_human, think, add_capability, create_capability

### Phase 5.1-5.2: Ruby TUI Foundation
- Bubble Tea app architecture (Model-View-Update)
- Lipgloss styling system
- Capability bar with PO selection
- Conversation panel with chat history
- Input component with vim-like modes (NORMAL/INSERT)
- Message log panel

### Phase 5.3: Notifications & Request Responder
- Notification panel showing pending human requests
- Request responder modal for answering questions
- Integration with HumanQueue
- Capability bar badges showing pending counts

### Phase 7.1: MCP Server
- Model Context Protocol server over stdio
- Tools: list_prompt_objects, send_message, get_conversation, etc.
- Resources: po://, bus://
- See [mcp-tools.md](./mcp-tools.md) for full reference

## In Progress

### Bug Fixes
- [x] Conversation isolation between POs
- [x] Coordinator delegation (LLM hedging fix)
- [x] Track message sender (human vs delegated)
- [ ] Charm gem FFI stability (ongoing)

## Planned (In Order)

### Phase 8: Environments (Next)
Smalltalk-like "images" - isolated, versioned runtime environments.

See [phase-8-environments.md](./phase-8-environments.md)

**Key Features:**
- Environments are git repos (built-in versioning)
- Sessions in SQLite (gitignored, private)
- Templates for first-run setup
- Sandbox for imported custom primitives
- Archive-first deletion

**Sub-phases:**
- 8.1: Core structure + git integration ✓
- 8.2: Templates + first-run wizard ✓
- 8.3: SQLite session storage ✓
- 8.4: Export/import bundles ✓
- 8.5: Archive + rich metadata ✓
- 8.6: Dev mode (--dev flag)
- 8.7: Onboarding UI polish (non-blocking)

### Phase 6: Multiple Sessions
Named conversation sessions per PO (builds on Phase 8 storage).

See [phase-6-sessions.md](./phase-6-sessions.md)

**Features:**
- Session picker modal (`S` key)
- Session switching and management
- Per-environment session storage

### Phase 5.4: Markdown Rendering
Render LLM markdown output with proper formatting.

See [phase-5.4-markdown.md](./phase-5.4-markdown.md)

**Options:**
- Pure Ruby ANSI renderer (no FFI)
- TTY-Markdown gem
- Wait for Glamour FFI fixes (working with charm-ruby team)

### Phase 5.5-5.6: Mouse Support & Dashboard
Mouse interaction and grid view for POs.

See [phase-5.5-dashboard.md](./phase-5.5-dashboard.md)

**Features:**
- Click to select PO, scroll wheel support
- Dashboard grid view with PO cards
- Search/filter POs

### Future Ideas

- **Streaming responses**: Token-by-token LLM output
- **PO creation from TUI**: Create new POs without editing files
- **Themes**: Dark/light mode, custom color schemes
- **Environment marketplace**: Share environments publicly
- **Team environments**: Access control and collaboration

## File Structure

```
lib/prompt_objects/
├── capability.rb           # Base capability class
├── prompt_object.rb        # LLM-backed capability
├── registry.rb             # Capability registry
├── message_bus.rb          # Inter-PO communication
├── human_queue.rb          # Pending human requests
├── environment.rb          # Runtime environment
├── loader.rb               # Markdown file loader
├── llm/
│   ├── openai_adapter.rb   # OpenAI API client
│   └── response.rb         # Normalized LLM response
├── primitives/             # Built-in primitives
├── universal/              # Universal capabilities
├── mcp/
│   ├── server.rb           # MCP server
│   └── tools/              # MCP tool implementations
└── ui/
    ├── app.rb              # Main Bubble Tea app
    ├── styles.rb           # Lipgloss styles
    └── models/             # UI components
        ├── capability_bar.rb
        ├── conversation.rb
        ├── input.rb
        ├── message_log.rb
        ├── notification_panel.rb
        ├── request_responder.rb
        └── po_inspector.rb
```

## Running

```bash
# Ruby TUI
bundle exec ruby exe/prompt_objects_tui

# MCP Server (for Claude Desktop, etc.)
bundle exec ruby exe/prompt_objects_mcp

# REPL (legacy)
bundle exec ruby exe/prompt_objects
```
