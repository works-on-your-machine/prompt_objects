# Web UI Complete

**Status**: Backlog
**Priority**: High
**Depends on**: [web-server-infrastructure.md](web-server-infrastructure.md)
**Design doc**: [web-server-design.md](../web-server-design.md)

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

- [ ] Dashboard component
  - [ ] Grid layout for PO cards
  - [ ] POCard component with:
    - [ ] Name and description
    - [ ] Status indicator (idle/busy/waiting)
    - [ ] Notification badge (count)
    - [ ] Session count
  - [ ] Click card to navigate to detail
- [ ] PO Detail component
  - [ ] Back navigation to dashboard
  - [ ] PO name in header
  - [ ] Tab bar (Chat, Sessions, Capabilities, Edit)
  - [ ] Tab content area
- [ ] Chat tab (from Phase 2, refined)
  - [ ] Message list with proper styling
  - [ ] Streaming message component
  - [ ] Input with submit button
  - [ ] Auto-scroll on new messages
- [ ] Message bus sidebar
  - [ ] Toggle button in header
  - [ ] Collapsible right panel
  - [ ] List of recent bus messages
  - [ ] From → To with timestamp
  - [ ] Auto-scroll, keep last N messages
- [ ] Routing/navigation state in Zustand

### Exit Criteria

- Can see all POs on dashboard
- Can click into any PO
- Can chat with PO, see streaming
- Can toggle message bus sidebar
- Can navigate back to dashboard

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
