# PromptObjects Epics

This file tracks all epics (major features) for PromptObjects, ordered by priority.
Reorder items to change priority. Insert new epics as needed.

## Status Legend

| Status | Meaning |
|--------|---------|
| **Done** | Completed and shipped |
| **In Progress** | Currently being worked on |
| **Ready** | Spec complete, ready to implement |
| **Backlog** | Planned but not yet specced |
| **Idea** | Future possibility, not committed |

---

## Done

### Core Framework
The foundation: PromptObjects, capabilities, registry, message bus.
- PromptObject class with LLM integration
- Registry and capability resolution
- Message bus for inter-PO communication
- Primitives: read_file, list_files, write_file, http_get
- Universal capabilities: ask_human, think, add_capability, create_capability

### TUI Foundation
Bubble Tea app with vim-like interface.
- Model-View-Update architecture
- Lipgloss styling system
- Capability bar with PO selection
- Conversation panel with chat history
- Input component (NORMAL/INSERT modes)
- Message log panel

### Notifications & Requests
Human-in-the-loop interaction.
- Notification panel for pending requests
- Request responder modal
- HumanQueue integration
- Capability bar badges

### MCP Server
Model Context Protocol for external clients.
- Stdio transport
- Tools: list_prompt_objects, send_message, get_conversation
- Resources: po://, bus://
- See: [epics/mcp-tools.md](epics/mcp-tools.md)

### Environments
Smalltalk-like "images" - isolated, versioned runtime environments.
- Git-backed versioning
- SQLite session storage (gitignored)
- Templates + first-run wizard
- Export/import bundles (.poenv)
- Archive + rich metadata
- Dev mode (--dev flag)
- See: [epics/environments.md](epics/environments.md)

### Sessions
Multiple named conversation sessions per PO.
- Session picker modal (S key)
- Create, rename, delete sessions
- Session switching
- Session name in panel title
- See: [epics/sessions.md](epics/sessions.md)

### Primitive Management
Enable POs to create and request their own primitives.
- `list_primitives`: List stdlib/custom/active primitives
- `add_primitive`: Add stdlib primitives to PO
- `create_primitive`: Write new Ruby code as primitive
- `verify_primitive`: Test primitives with sample inputs
- `modify_primitive`: Update existing primitive code
- `request_primitive`: Ask human to create/approve primitives
- See: [epics/primitive-management.md](epics/primitive-management.md)

### Session Management (Enhanced)
Environment-wide session exploration beyond per-PO picker.
- Session explorer modal (all POs, all sessions) - E key
- Session source tracking (tui, mcp, api, web)
- Full-text search across sessions (SQLite FTS5)
- Export/import sessions (JSON, Markdown)
- Session commands (/sessions, /session new|rename|switch|export|info)
- See: [epics/session-management.md](epics/session-management.md)

### Charm Native Integration (FFI Stability Fix)
Fixed FFI crashes by using charm-native as single Go runtime for all Charm gems.
- Root cause: Multiple Go runtimes conflict when loading bubbletea + lipgloss + glamour
- Solution: Use Spencer's charm-native gem + Ruby shims for Model/Runner/Commands
- Built charm-native Go archive and C extension locally
- Created vendor/charm_shim/ with Ruby compatibility code (Messages, Commands, Model, Runner)
- All Charm functionality works with single Go runtime - no more crashes
- See: [epics/charm-forks.md](epics/charm-forks.md)

---

## In Progress

### Onboarding UI Polish
Visual refinements for picker/wizard screens. Non-blocking.
- [ ] Center alignment consistency
- [ ] Box drawing alignment
- [ ] Consistent spacing/padding
- [ ] Loading states/spinners
- [ ] Keyboard shortcut hints

---

## Ready

### Environment Data (Stigmergy)
Shared data space for loose-coupled PO coordination.
- `place_data`: Put data into environment
- `watch_data`: Subscribe to data patterns
- `query_data`: Read existing data
- POs react to data, not direct messages
- Foundation for external integrations (email, webhooks, cron)
- See: [epics/environment-data.md](epics/environment-data.md)


### Dashboard UX Overhaul
Transform TUI from flat chat-centric to hierarchical PO-centric dashboard.
- Dashboard → PO Detail → Session Chat navigation
- PO cards with live indicators (state, tools, pending requests)
- Activity feed showing cross-PO messages and tool calls
- Session list per PO with source indicators (TUI/MCP/API)
- Chat only visible when in specific session
- Mouse + keyboard navigation
- **Requires**: ~~charm-native (markdown)~~, Event Stream (live updates)
- See: [epics/dashboard-ux-overhaul.md](epics/dashboard-ux-overhaul.md)

### Connectors: Reactive Multi-Interface Runtime
Daemon architecture for true reactive multi-interface access (Smalltalk image model).
- [x] Phase 0: MCP connector with session source tracking (temporary polling)
- [x] Phase 0: TUI live updates when MCP sessions are active
- [x] Phase 0: SQLite WAL mode for concurrent access
- [ ] Phase 1: Event stream foundation (internal pub/sub)
- [ ] Phase 2: IPC protocol & daemon process
- [ ] Phase 3: TUI as IPC client (daemon mode)
- [ ] Phase 4: HTTP/REST API connector with WebSocket events
- [ ] Phase 5: PO-spawned interfaces (POs can create their own HTTP servers)
- See: [epics/connectors.md](epics/connectors.md)

---

## Backlog

### Streaming Responses
Token-by-token LLM output display.
- Progressive rendering in conversation panel
- Typing indicator
- Cancel mid-stream

### PO Creation from TUI
Create new POs without editing files.
- New PO wizard modal
- Template selection
- Capability configuration
- Save to environment

### Themes
Dark/light mode and custom color schemes.
- Theme configuration in manifest
- Built-in themes
- Custom color definitions

---

## Ideas

### Environment Marketplace
Share environments publicly.
- Publishing workflow
- Discovery/search
- Trust verification for primitives

### Team Environments
Collaboration features.
- Access control
- Shared sessions
- Real-time sync

### PO Composition
Advanced PO relationships.
- PO inheritance
- Capability mixing
- Dynamic delegation rules

### Analytics Dashboard
Usage insights.
- Token usage tracking
- Response time metrics
- Session analytics
- Cost estimation

### Voice Interface
Speech interaction.
- Voice input
- Text-to-speech output
- Wake word activation

---

## Epic File Index

| Epic | File | Status |
|------|------|--------|
| Environments | [epics/environments.md](epics/environments.md) | Done |
| Sessions | [epics/sessions.md](epics/sessions.md) | Done |
| MCP Server | [epics/mcp-server.md](epics/mcp-server.md) | Done |
| MCP Tools Reference | [epics/mcp-tools.md](epics/mcp-tools.md) | Done |
| Charm Native Integration | [epics/charm-forks.md](epics/charm-forks.md) | Done |
| Primitive Management | [epics/primitive-management.md](epics/primitive-management.md) | Done |
| Environment Data | [epics/environment-data.md](epics/environment-data.md) | Ready |
| Markdown Rendering | [epics/markdown-rendering.md](epics/markdown-rendering.md) | Done (via charm-native) |
| Dashboard UX Overhaul | [epics/dashboard-ux-overhaul.md](epics/dashboard-ux-overhaul.md) | Ready |
| Session Management | [epics/session-management.md](epics/session-management.md) | Done |
| Connectors | [epics/connectors.md](epics/connectors.md) | Ready |
