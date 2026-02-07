# Web UI Complete

**Status**: In Progress
**Priority**: High
**Depends on**: [web-server-infrastructure.md](web-server-infrastructure.md) (Complete)
**Design doc**: [web-server-design.md](../web-server-design.md)

## Implementation Status

### Done
- Dashboard with PO cards grid (status indicators, session counts)
- PO detail view with chat tab
- Chat with markdown rendering, syntax highlighting, streaming
- Split view layout (dashboard sidebar while chatting)
- Collapsible message bus sidebar (shows summary, sends both summary and full content)
- Threads/sessions sidebar for session management
- LLM provider switching
- Prompt editing (inline, persisted to file)
- Real-time tool call chain display
- Capabilities panel showing declared + universal capabilities with parameters
- Notification system for ask_human requests

### Remaining
- Capabilities tab (dedicated view for capability inspection)
- Edit tab (Monaco editor for full PO markdown editing)
- Sessions tab (full session management beyond the threads sidebar)
- Event history panel (browse persistent events from SQLite, search across events)
- Full message inspection (click to expand in bus panel)

---

## Overview

Build the complete web UI: dashboard with PO cards, detail view with tabs, message bus sidebar, and notifications. This epic brings the web interface to feature parity with core TUI workflows.

## Goals

- Dashboard view with PO cards showing status, notifications, sessions
- PO detail view with tabbed sections (Chat, Sessions, Capabilities, Edit)
- Collapsible message bus sidebar
- Global + per-PO notification handling
- Full navigation between views

## Non-Goals

- Visual canvas/graph (deferred)
- Dynamic PO-generated views (deferred)
- Mobile-first responsive design

---

## Phase 3: Dashboard + Detail Navigation

### Tasks

- [x] Dashboard component
  - [x] Grid layout for PO cards
  - [x] POCard component with:
    - [x] Name and description
    - [x] Status indicator (idle/busy/waiting)
    - [x] Notification badge (count)
    - [x] Session count
  - [x] Click card to navigate to detail
- [x] PO Detail component
  - [x] Back navigation to dashboard
  - [x] PO name in header
  - [x] Tab bar (Chat, Sessions, Capabilities, Edit)
  - [x] Tab content area
- [x] Chat tab
  - [x] Message list with markdown rendering
  - [x] Syntax-highlighted code blocks with copy button
  - [x] Streaming message component
  - [x] Input with submit button
  - [x] Auto-scroll on new messages
- [x] Message bus sidebar
  - [x] Toggle button in header
  - [x] Collapsible right panel
  - [x] List of recent bus messages
  - [x] From → To with timestamp
  - [x] Auto-scroll, keep last N messages
- [x] Split view layout
  - [x] See PO list sidebar while chatting
  - [x] Toggle sidebar on/off
  - [x] Compact list view with status indicators
- [x] Routing/navigation state in Zustand

### Exit Criteria

- [x] Can see all POs on dashboard
- [x] Can click into any PO
- [x] Can chat with PO, see markdown-rendered responses
- [x] Can toggle message bus sidebar
- [x] Can navigate back to dashboard
- [x] Can see PO sidebar while chatting (split view)

---

## Phase 4: Feature Completion

### Tasks

- [ ] Sessions tab
  - [ ] List all sessions for current PO
  - [ ] Session name, message count, last activity
  - [ ] Switch session (click)
  - [ ] Create new session (button + modal/form)
  - [ ] Rename session (inline edit or modal)
  - [ ] Delete session (with confirmation)
- [ ] Capabilities tab
  - [ ] List capabilities PO has access to
  - [ ] Capability name and description
  - [ ] (Future: add/remove capabilities)
- [ ] Edit tab
  - [ ] Monaco editor for PO markdown
  - [ ] Syntax highlighting for YAML frontmatter + markdown
  - [ ] Save button (calls API to update PO file)
  - [ ] Unsaved changes indicator
- [ ] Notifications
  - [ ] Global notification badge in header
  - [ ] Click badge to see notification list (dropdown or modal)
  - [ ] Per-PO notifications in detail view
  - [ ] Response modal for human-in-the-loop
    - [ ] Show request message
    - [ ] Option buttons or text input
    - [ ] Submit response via WebSocket
- [ ] File watching (optional)
  - [ ] When PO file changes on disk, push update via WebSocket
  - [ ] UI reflects changes without refresh

### Exit Criteria

- Full session management works
- Can view PO capabilities
- Can edit PO markdown and save
- Can respond to human-in-the-loop notifications
- Feature parity with TUI for core workflows

---

## UI Structure Reference

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Header: Environment name                      [Notifications] [Bus ☰] │
├────────────────────────────────────────────────┬────────────────────────┤
│                                                │                        │
│  Dashboard (main area)                         │  Message Bus           │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐          │  (collapsible)         │
│  │ reader  │ │ greeter │ │ coord   │          │                        │
│  │ ● idle  │ │ ◐ busy  │ │ ○ wait  │          │  12:01 reader→list_... │
│  │ 🔔 2    │ │         │ │ 🔔 1    │          │  12:00 coord→reader    │
│  │ 3 sess  │ │ 1 sess  │ │ 2 sess  │          │                        │
│  └─────────┘ └─────────┘ └─────────┘          │                        │
│                                                │                        │
└────────────────────────────────────────────────┴────────────────────────┘

PO Detail View:
┌─────────────────────────────────────────────────────────────────────────┐
│  ← Back          reader                                    [Bus ☰]     │
├─────────────────────────────────────────────────────────────────────────┤
│  [Chat] [Sessions] [Capabilities] [Edit]                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Chat tab content:                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ User: What files are here?                                       │   │
│  │ reader: Let me check... [list_files]                            │   │
│  │ reader: I found: src/, lib/, test/                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Type a message...                                    [Send]     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Checklist

### Layout
- [ ] Header
- [ ] MainLayout (dashboard + sidebar structure)
- [ ] BusSidebar

### Dashboard
- [ ] Dashboard
- [ ] POCard

### PODetail
- [ ] PODetail (container)
- [ ] TabBar
- [ ] ChatTab
- [ ] SessionsTab
- [ ] CapabilitiesTab
- [ ] EditTab

### Chat
- [ ] MessageList
- [ ] Message
- [ ] StreamingMessage
- [ ] ChatInput

### MessageBus
- [ ] BusLog
- [ ] BusMessage

### Notifications
- [ ] NotificationBadge
- [ ] NotificationList
- [ ] NotificationModal

### Sessions
- [ ] SessionList
- [ ] SessionItem
- [ ] CreateSessionModal

---

## Technical Notes

### Monaco Editor Setup

```typescript
import Editor from '@monaco-editor/react'

<Editor
  height="100%"
  defaultLanguage="markdown"
  value={poMarkdown}
  onChange={handleChange}
  options={{
    minimap: { enabled: false },
    wordWrap: 'on'
  }}
/>
```

### Tab State

Tab state lives in Zustand, not URL routing (for simplicity):

```typescript
interface Store {
  selectedPO: string | null
  activeTab: 'chat' | 'sessions' | 'capabilities' | 'edit'
  setActiveTab: (tab: Store['activeTab']) => void
}
```

### Notification Response Flow

```
User clicks notification →
  NotificationModal opens →
    User selects option or types response →
      sendNotificationResponse(id, response) →
        WebSocket sends to server →
          Server resumes waiting PO fiber →
            PO continues execution
```

---

## Related

- [web-server-infrastructure.md](web-server-infrastructure.md) - Previous epic
- [web-distribution.md](web-distribution.md) - Next epic
- [web-server-design.md](../web-server-design.md) - Full design document
