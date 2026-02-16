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
Bubble Tea app with vim-like interface. Deprioritized in favor of web UI.
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
Smalltalk-like "images" — isolated, versioned runtime environments.
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
- Session explorer modal (all POs, all sessions) — E key
- Session source tracking (tui, mcp, api, web)
- Full-text search across sessions (SQLite FTS5)
- Export/import sessions (JSON, Markdown)
- Session commands (/sessions, /session new|rename|switch|export|info)
- See: [archive/completed/session-management.md](archive/completed/session-management.md)

### Web Server Infrastructure
Falcon-based web server and React frontend foundation.
- Falcon server with WebSocket support
- WebSocketHandler integrated with MessageBus
- React + Zustand + Vite frontend
- End-to-end streaming: message → LLM → WebSocket → UI
- See: [archive/completed/web-server-infrastructure.md](archive/completed/web-server-infrastructure.md)

### Custom Primitive Auto-Loading
Primitives placed in env/primitives/ now load automatically on startup.
- Fixed bug where custom primitives were not being discovered
- Primitives register in the capability registry at boot

### CLI Interface & Persistent Event Log
HTTP-hub CLI and full-fidelity event persistence.
- Message bus stores full messages (truncate only at display time)
- Persistent SQLite event log for all message bus activity
- REST message endpoint for CLI and scripting
- CLI `message` and `events` commands
- Server discovery via .server file
- See: [archive/completed/cli-and-event-log.md](archive/completed/cli-and-event-log.md)

### ARC-AGI-1 Template
Environment template for ARC-AGI puzzle solving.
- Solver and data_manager Prompt Objects
- 8 grid manipulation primitives
- Template available via environment wizard

### Alternate Model Support
Multi-provider LLM support beyond OpenAI.
- Ollama adapter with dynamic model discovery
- OpenRouter adapter
- Model hot-swapping via web UI
- See: [archive/completed/alternate_models.md](archive/completed/alternate_models.md)

### Token Usage & Cost Tracking
Per-session and delegation-tree token usage.
- Extract usage from LLM responses
- Per-model pricing table
- Usage panel in web UI (right-click thread)
- See: [archive/completed/token_usage_tracking.md](archive/completed/token_usage_tracking.md)

### Thread Export
Export conversation threads including full delegation chains.
- Markdown and JSON export formats
- Delegation sub-threads render inline after triggering tool call
- REST API endpoint and WebSocket handler
- Right-click context menu in web UI
- See: [archive/completed/thread_export.md](archive/completed/thread_export.md)

### Thread Explorer
Standalone HTML visualizer for conversation thread exports.
- Sequence diagram (swim lanes), timeline, and detail views
- Token cost bar, search, per-PO filtering
- CLI: `prompt_objects explore <env>`

### Spatial Canvas (v0.4.0)
Three.js 2D visualization of POs working together.
- PO nodes as glowing hexagons, tool call diamonds, message arcs with particles
- Force-directed layout
- Click-to-inspect panels
- Delegation glow and status broadcasting
- `/canvas` route alongside dashboard
- See: [archive/completed/spatial-canvas.md](archive/completed/spatial-canvas.md)

### Frontend Redesign — Smalltalk System Browser (v0.5.0)
Complete web UI overhaul replacing chat-app style with multi-pane object browser.
- Warm charcoal + amber palette with Geist fonts
- SystemBar, ObjectList, Inspector (MethodList + SourcePane), Workspace, Transcript
- Collapsible inspector top pane with PaneSlot component
- All panels resizable via drag handles
- Centralized PO serialization (eliminated inconsistent data as a class of bug)
- See: [archive/completed/updated-frontend-design.md](archive/completed/updated-frontend-design.md)

### Charm Native Integration (FFI Stability Fix)
Fixed FFI crashes by using charm-native as single Go runtime for all Charm gems.
- See: [archive/drafts/charm-forks.md](archive/drafts/charm-forks.md)

---

## Ready

### Shared Environment Data
Thread-scoped key-value store for PO delegation chains to share working memory.
- `store_env_data`, `get_env_data`, `list_env_data`, `update_env_data`, `delete_env_data`
- Scoped to root delegation thread (not global)
- Entries have `key`, `short_description`, `value` — lightweight manifest for LLM discoverability
- SQLite storage in existing session database
- See: [epics/shared-environment-data.md](epics/shared-environment-data.md)

### Universal Capability Cleanup
Consolidate 14 universal capabilities down to 9 by merging overlapping primitive management tools.
- Absorb `create_primitive` → `create_capability`, `add_primitive` → `add_capability`, etc.
- Extract shared syntax validation and code generation into `PrimitiveSupport` module
- Fix `delete_primitive` bug (unqualified constant reference)
- See: [epics/universal-capability-cleanup.md](epics/universal-capability-cleanup.md)

### Parallel Tool Calling
Concurrent execution of tool calls within a single PO turn.
- All tool calls in a turn run in parallel via Async::Barrier
- Server already broadcasts po_delegation_started/completed events
- Remaining: context isolation refactor, Async::Barrier execution, batch events
- See: [epics/parallel-tool-calling.md](epics/parallel-tool-calling.md)
- Stories: [epics/parallel-tool-calling-stories.md](epics/parallel-tool-calling-stories.md)

### Message Provenance
Delegation context — informing delegated POs about who called them and why.
- Base system prompt expansion
- Delegation preamble with caller context
- See: [epics/message-provenance.md](epics/message-provenance.md)

---

## Backlog

### TUI Maintenance (Low Priority)
The TUI still works via `prompt_objects tui`. Not actively developed but maintained.
- Existing TUI design docs archived to [archive/drafts/](archive/drafts/)
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

### Connectors — Reactive Multi-Interface Runtime
Daemon architecture with IPC sockets, event stream pub/sub, PO-spawned HTTP servers.
- TUI and web as clients to a long-running daemon
- POs can spawn their own interfaces
- See: [ideas/connectors.md](ideas/connectors.md)

### Web Distribution
Deploying PO environments as live web apps.
- See: [ideas/web-distribution.md](ideas/web-distribution.md)

### Watcher PO & Reactive Patterns
Reactive coordination using a PO that watches for changes.
- See: [ideas/watcher-po-and-reactive-patterns.md](ideas/watcher-po-and-reactive-patterns.md)

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
| Shared Environment Data | [epics/shared-environment-data.md](epics/shared-environment-data.md) | Ready |
| Universal Capability Cleanup | [epics/universal-capability-cleanup.md](epics/universal-capability-cleanup.md) | Ready |
| Parallel Tool Calling | [epics/parallel-tool-calling.md](epics/parallel-tool-calling.md) | Ready |
| Message Provenance | [epics/message-provenance.md](epics/message-provenance.md) | Ready |

### Completed Epics

| Epic | File |
|------|------|
| Frontend Redesign (v0.5.0) | [archive/completed/updated-frontend-design.md](archive/completed/updated-frontend-design.md) |
| Spatial Canvas (v0.4.0) | [archive/completed/spatial-canvas.md](archive/completed/spatial-canvas.md) |
| Thread Export | [archive/completed/thread_export.md](archive/completed/thread_export.md) |
| Thread Explorer | — |
| Token Usage & Cost Tracking | [archive/completed/token_usage_tracking.md](archive/completed/token_usage_tracking.md) |
| Alternate Model Support | [archive/completed/alternate_models.md](archive/completed/alternate_models.md) |
| CLI & Event Log | [archive/completed/cli-and-event-log.md](archive/completed/cli-and-event-log.md) |
| Web Server Infrastructure | [archive/completed/web-server-infrastructure.md](archive/completed/web-server-infrastructure.md) |
| Web UI Complete | [archive/completed/web-ui-complete.md](archive/completed/web-ui-complete.md) |
| Environments | [archive/completed/environments.md](archive/completed/environments.md) |
| Sessions | [archive/completed/sessions.md](archive/completed/sessions.md) |
| Session Management | [archive/completed/session-management.md](archive/completed/session-management.md) |
| MCP Server & Tools | [archive/completed/mcp-server.md](archive/completed/mcp-server.md) |
| Primitive Management | [archive/completed/primitive-management.md](archive/completed/primitive-management.md) |
| Web Server Design | [archive/completed/web-server-design.md](archive/completed/web-server-design.md) |

### Ideas & Drafts

| Document | File |
|----------|------|
| Connectors | [ideas/connectors.md](ideas/connectors.md) |
| Web Distribution | [ideas/web-distribution.md](ideas/web-distribution.md) |
| Watcher PO & Reactive Patterns | [ideas/watcher-po-and-reactive-patterns.md](ideas/watcher-po-and-reactive-patterns.md) |
| Long-term State Thoughts | [ideas/long_term_state_thoughts.md](ideas/long_term_state_thoughts.md) |
| Environment Data (early draft) | [archive/drafts/environment-data.md](archive/drafts/environment-data.md) |
| TUI designs | [archive/drafts/](archive/drafts/) (4 docs) |
