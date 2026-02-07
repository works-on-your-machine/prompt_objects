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
- See: [archive/completed/mcp-tools.md](archive/completed/mcp-tools.md)

### Environments
Smalltalk-like "images" - isolated, versioned runtime environments.
- Git-backed versioning
- SQLite session storage (gitignored)
- Templates + first-run wizard
- Export/import bundles (.poenv)
- Archive + rich metadata
- Dev mode (--dev flag)
- See: [archive/completed/environments.md](archive/completed/environments.md)

### Sessions
Multiple named conversation sessions per PO.
- Session picker modal (S key)
- Create, rename, delete sessions
- Session switching
- Session name in panel title
- See: [archive/completed/sessions.md](archive/completed/sessions.md)

### Primitive Management
Enable POs to create and request their own primitives.
- `list_primitives`: List stdlib/custom/active primitives
- `add_primitive`: Add stdlib primitives to PO
- `create_primitive`: Write new Ruby code as primitive
- `verify_primitive`: Test primitives with sample inputs
- `modify_primitive`: Update existing primitive code
- `request_primitive`: Ask human to create/approve primitives
- See: [archive/completed/primitive-management.md](archive/completed/primitive-management.md)

### Session Management (Enhanced)
Environment-wide session exploration beyond per-PO picker.
- Session explorer modal (all POs, all sessions) - E key
- Session source tracking (tui, mcp, api, web)
- Full-text search across sessions (SQLite FTS5)
- Export/import sessions (JSON, Markdown)
- Session commands (/sessions, /session new|rename|switch|export|info)
- See: [archive/completed/session-management.md](archive/completed/session-management.md)

### Charm Native Integration (FFI Stability Fix)
Fixed FFI crashes by using charm-native as single Go runtime for all Charm gems.
- Root cause: Multiple Go runtimes conflict when loading bubbletea + lipgloss + glamour
- Solution: Use Spencer's charm-native gem + Ruby shims for Model/Runner/Commands
- Built charm-native Go archive and C extension locally
- Created vendor/charm_shim/ with Ruby compatibility code (Messages, Commands, Model, Runner)
- All Charm functionality works with single Go runtime - no more crashes
- See: [archive/tui-epics/charm-forks.md](archive/tui-epics/charm-forks.md) (archived)

### Web Server Infrastructure
Falcon-based web server and React frontend foundation.
- Falcon server with WebSocket support
- WebSocketHandler integrated with MessageBus
- React + Zustand + Vite frontend
- End-to-end streaming: message → LLM → WebSocket → UI
- See: [archive/completed/web-server-infrastructure.md](archive/completed/web-server-infrastructure.md)
- Design doc: [web-server-design.md](web-server-design.md)

### Custom Primitive Auto-Loading
Primitives placed in env/primitives/ now load automatically on startup.
- Fixed bug where custom primitives were not being discovered
- Primitives register in the capability registry at boot

### CLI Interface & Persistent Event Log (Phases 1-4)
HTTP-hub CLI and full-fidelity event persistence.
- Message bus stores full messages (truncate only at display time)
- Persistent SQLite event log for all message bus activity
- REST message endpoint for CLI and scripting
- CLI `message` and `events` commands
- Server discovery via .server file
- See: [cli-and-event-log.md](cli-and-event-log.md)

### ARC-AGI-1 Template
Environment template for ARC-AGI puzzle solving.
- Solver and data_manager Prompt Objects
- 8 grid manipulation primitives
- Template available via environment wizard

---

## In Progress

*Nothing currently in progress.*

---

## Ready

### Web UI Complete
Full web interface — dashboard, chat, and real-time panels are shipped; remaining tabs and event history still to build.
- **Done**: Dashboard with PO cards, chat interface, threads sidebar, message bus panel, split view
- **Remaining**: Capabilities tab, Edit tab (Monaco editor), Sessions tab (full view), event history/search in bus panel
- See: [epics/web-ui-complete.md](epics/web-ui-complete.md)

### Web Distribution
CLI integration and gem packaging for the web interface.
- `prompt_objects serve` command
- Frontend assets bundled with gem
- Export/import .poenv bundles
- See: [epics/web-distribution.md](epics/web-distribution.md)

### Environment Data (Stigmergy)
Shared data space for loose-coupled PO coordination.
- `place_data`: Put data into environment
- `watch_data`: Subscribe to data patterns
- `query_data`: Read existing data
- POs react to data, not direct messages
- Foundation for external integrations (email, webhooks, cron)
- See: [epics/environment-data.md](epics/environment-data.md)

### CLI & Event Log Phases 5-6
Remaining phases from the CLI & Event Log epic.
- Phase 5: Embedded MCP — run MCP server inside the web server process
- Phase 6: Web UI event history — event log viewer, search, and filtering in the web interface
- See: [cli-and-event-log.md](cli-and-event-log.md)

---

## Backlog

### TUI Maintenance (Low Priority)
The TUI still works via `prompt_objects tui`. Not actively developed but maintained.
- Existing TUI epics archived to [archive/tui-epics/](archive/tui-epics/)
- Bug fixes only, no new features

### Themes (Web)
Dark/light mode and custom color schemes for web UI.
- Theme toggle in header
- System preference detection
- Custom color schemes in manifest

### Streaming Cancel
Ability to cancel LLM generation mid-stream.
- Cancel button appears during streaming
- Server-side cancellation
- Clean UI state on cancel

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

### Active Epics

| Epic | File | Status |
|------|------|--------|
| **Web UI Complete** | [epics/web-ui-complete.md](epics/web-ui-complete.md) | Ready |
| **Web Distribution** | [epics/web-distribution.md](epics/web-distribution.md) | Ready |
| Environment Data (Stigmergy) | [epics/environment-data.md](epics/environment-data.md) | Ready |
| CLI & Event Log Phases 5-6 | [cli-and-event-log.md](cli-and-event-log.md) | Ready |
| Connectors | [epics/connectors.md](epics/connectors.md) | Partially superseded by web server + CLI |

### Completed Epics

| Epic | File | Status |
|------|------|--------|
| Web Server Infrastructure | [archive/completed/web-server-infrastructure.md](archive/completed/web-server-infrastructure.md) | Done |
| CLI & Event Log (Phases 1-4) | [cli-and-event-log.md](cli-and-event-log.md) | Done |
| ARC-AGI-1 Template | — | Done |
| Custom Primitive Auto-Loading | — | Done |
| Environments | [archive/completed/environments.md](archive/completed/environments.md) | Done |
| Sessions | [archive/completed/sessions.md](archive/completed/sessions.md) | Done |
| MCP Server | [archive/completed/mcp-server.md](archive/completed/mcp-server.md) | Done |
| MCP Tools Reference | [archive/completed/mcp-tools.md](archive/completed/mcp-tools.md) | Done |
| Primitive Management | [archive/completed/primitive-management.md](archive/completed/primitive-management.md) | Done |
| Session Management | [archive/completed/session-management.md](archive/completed/session-management.md) | Done |

### Archived (TUI-specific)

| Epic | File | Notes |
|------|------|-------|
| Charm Native Integration | [archive/tui-epics/charm-forks.md](archive/tui-epics/charm-forks.md) | Still works, not actively developed |
| Markdown Rendering | [archive/tui-epics/markdown-rendering.md](archive/tui-epics/markdown-rendering.md) | Glamour integration for TUI |
| Dashboard UX Overhaul | [archive/tui-epics/dashboard-ux-overhaul.md](archive/tui-epics/dashboard-ux-overhaul.md) | Superseded by web UI |
| Dashboard and Mouse | [archive/tui-epics/dashboard-and-mouse.md](archive/tui-epics/dashboard-and-mouse.md) | TUI mouse support |

### Design Documents

| Document | File |
|----------|------|
| Web Server Design | [web-server-design.md](web-server-design.md) |
