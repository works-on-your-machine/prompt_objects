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

### Charm-Native (FFI Stability Fix)
Fix FFI crashes by using consolidated native extension.
- Root cause: Multiple Go runtimes conflict
- Solution: Spencer's forked gems using charm-native
- **Status**: Waiting for Spencer to share his forks
- Minimal code changes expected (just Gemfile)
- See: [epics/charm-native-migration.md](epics/charm-native-migration.md)

### Primitive Management
Enable POs to create and request their own primitives.
- `add_primitive`: Add stdlib primitives to PO
- `create_primitive`: Write new Ruby code as primitive
- `request_primitive`: Ask human to create/approve primitives
- Human approval workflow (approve/suggest as PO/reject)
- See: [epics/primitive-management.md](epics/primitive-management.md)

### Environment Data (Stigmergy)
Shared data space for loose-coupled PO coordination.
- `place_data`: Put data into environment
- `watch_data`: Subscribe to data patterns
- `query_data`: Read existing data
- POs react to data, not direct messages
- Foundation for external integrations (email, webhooks, cron)
- See: [epics/environment-data.md](epics/environment-data.md)

### Markdown Rendering
Render LLM markdown output with proper formatting.
- Options: Pure Ruby ANSI, TTY-Markdown, or Glamour FFI
- See: [epics/markdown-rendering.md](epics/markdown-rendering.md)

### Dashboard & Mouse Support
Grid view and mouse interaction.
- Click to select PO
- Scroll wheel support
- Dashboard grid view with PO cards
- Search/filter POs
- See: [epics/dashboard-and-mouse.md](epics/dashboard-and-mouse.md)

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
| Charm-Native Migration | [epics/charm-native-migration.md](epics/charm-native-migration.md) | Ready |
| Primitive Management | [epics/primitive-management.md](epics/primitive-management.md) | Ready |
| Environment Data | [epics/environment-data.md](epics/environment-data.md) | Ready |
| Markdown Rendering | [epics/markdown-rendering.md](epics/markdown-rendering.md) | Ready |
| Dashboard & Mouse | [epics/dashboard-and-mouse.md](epics/dashboard-and-mouse.md) | Ready |
