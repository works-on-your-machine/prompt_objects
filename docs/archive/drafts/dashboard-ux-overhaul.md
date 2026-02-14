> **ARCHIVED**: This epic was for the Charm-based TUI interface. The project has pivoted to a web-based interface (see docs/web-server-design.md and docs/epics/web-*.md). This file is preserved for historical reference.

---

# Dashboard UX Overhaul

## Vision

Transform the TUI from a flat, conversation-centric interface to a **PO-centric dashboard** where Prompt Objects are first-class citizens. The chat view only appears when actively interacting with a specific session.

Think of it like a Smalltalk image browser: you see the living system with all its objects, their states, and activity. You drill into an object to inspect or interact with it.

---

## Current vs Proposed

### Current (Flat, Chat-Centric)

```
┌─────────────────────────────────────────────────────────────┐
│ PromptObjects [env]                                         │
├─────────────────────────────────────────────────────────────┤
│ [●greeter] [○helper] [○writer]   ← POs as tabs              │
├─────────────────────────────────────────────────────────────┤
│ Conversation               │ Message Log                    │
│ ────────────               │ ───────────                    │
│ You: hello                 │ human → greeter                │
│ greeter: Hi!               │ greeter → human                │
├─────────────────────────────────────────────────────────────┤
│ > [input always visible]                                    │
└─────────────────────────────────────────────────────────────┘
```

**Problems:**
- Chat dominates the view even when not actively chatting
- POs are just "tabs" with no visibility into their state
- Sessions hidden behind modal (S key)
- No visibility into cross-PO activity
- Can't see which POs have pending human requests
- No indication of tool calls or working state

### Proposed (Hierarchical, PO-Centric)

```
Dashboard → PO Detail → Session Chat
    ↑____________↑___________↑
         (back navigation)
```

---

## Screen Designs

### Screen 1: Dashboard (Home)

The primary view. Shows all POs as cards with live status indicators.

```
┌─────────────────────────────────────────────────────────────┐
│ PromptObjects [dev_demo]                         [?] [⚙]   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────┐  ┌─────────────────┐  ┌────────────┐ │
│   │    greeter      │  │     helper      │  │   writer   │ │
│   │   ───────────   │  │   ───────────   │  │ ────────── │ │
│   │   ○ idle        │  │   ◐ working     │  │  ○ idle    │ │
│   │                 │  │   ▶ read_file   │  │            │ │
│   │   Sessions: 3   │  │   Sessions: 1   │  │ Sessions: 2│ │
│   │   [!] 1 waiting │  │                 │  │            │ │
│   └─────────────────┘  └─────────────────┘  └────────────┘ │
│                                                             │
│   ┌─────────────────┐  ┌─────────────────┐                 │
│   │   analyzer      │  │   dashboard     │                 │
│   │   ───────────   │  │   ───────────   │                 │
│   │   ○ idle        │  │   ○ idle        │                 │
│   │                 │  │   🌐 :8080      │                 │
│   │   Sessions: 0   │  │   Sessions: 1   │                 │
│   └─────────────────┘  └─────────────────┘                 │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Activity                                                    │
│  greeter → human: "Hi there!"                      2m ago  │
│  helper: ▶ read_file("/tmp/data.txt")              1m ago  │
│  writer: ✓ finished                                5m ago  │
└─────────────────────────────────────────────────────────────┘

Keys: ↑↓←→/hjkl navigate  Enter select  n new PO  ? help  q quit
```

**PO Card Indicators:**
| Indicator | Meaning |
|-----------|---------|
| `○ idle` | Not currently processing |
| `◐ working` | Processing a message |
| `● active` | Has active session (user is in it) |
| `▶ tool_name` | Currently calling a tool |
| `[!] N waiting` | Has N pending human requests |
| `🌐 :port` | Has spawned HTTP server |
| `Sessions: N` | Number of sessions |

**Activity Feed:**
- Shows recent inter-PO messages and tool calls
- Color-coded by type (message, tool call, completion)
- Scrollable, limited to last N entries
- Clicking an entry navigates to that PO/session

---

### Screen 2: PO Detail

Shown when a PO card is selected. Lists all sessions for this PO.

```
┌─────────────────────────────────────────────────────────────┐
│ ← Dashboard              greeter                    [I] [e]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  A friendly greeter who helps with file operations          │
│                                                             │
│  Capabilities: read_file, list_files, ask_human             │
│  State: ○ idle                                              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  Sessions                                    [+ New Session]│
│  ─────────                                                  │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐│
│  │ ● Morning Chat                             [TUI]       ││
│  │   3 messages • Last: "Hi there!" 2m ago               ││
│  └────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌────────────────────────────────────────────────────────┐│
│  │   Claude Desktop Session                   [MCP] 🔴    ││
│  │   12 messages • Last: "Done!" 1h ago      (live)      ││
│  └────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌────────────────────────────────────────────────────────┐│
│  │   API Test                                 [API]       ││
│  │   5 messages • yesterday                              ││
│  └────────────────────────────────────────────────────────┘│
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ [!] Pending Request                                         │
│ "Should I delete the temporary files?"                      │
│ [y] Yes  [n] No  [r] Respond...                            │
└─────────────────────────────────────────────────────────────┘

Keys: Esc/← back  ↑↓ navigate  Enter open  n new  d delete  I inspect  e edit
```

**Session Row Indicators:**
| Indicator | Meaning |
|-----------|---------|
| `●` | Currently active (you're in it) |
| `[TUI]` | Created from TUI |
| `[MCP]` | Created from MCP (Claude Desktop, etc) |
| `[API]` | Created from HTTP API |
| `🔴 (live)` | Recently active from another interface |

**Pending Requests:**
- Shows any `ask_human` requests waiting for this PO
- Can respond directly from this screen
- Badge count shown on PO card in dashboard

---

### Screen 3: Session Chat

The conversation view. Only shown when you select a specific session.

```
┌─────────────────────────────────────────────────────────────┐
│ ← greeter            Morning Chat              [x] [···]   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────────────────────────────────────────────┐│
│  │ You                                           2m ago   ││
│  │ ─────────────────────────────────────────────────────  ││
│  │ hello                                                  ││
│  └────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌────────────────────────────────────────────────────────┐│
│  │ greeter                                       2m ago   ││
│  │ ─────────────────────────────────────────────────────  ││
│  │ Hi there! How can I help you today?                    ││
│  │                                                        ││
│  │ I can help you with:                                   ││
│  │ • **Reading files** from your system                   ││
│  │ • **Listing directories**                              ││
│  │ • Answering questions about file contents              ││
│  └────────────────────────────────────────────────────────┘│
│                                                             │
│                              ◐ greeter is thinking...      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ > Type a message...                                    [⏎] │
└─────────────────────────────────────────────────────────────┘

Keys: Esc/← back  i insert mode  ↑↓ scroll  x export  ? help
```

**Chat Features:**
- Messages rendered with markdown (requires charm-native fix)
- Timestamps on each message
- Tool calls shown inline (expandable)
- Working indicator when PO is processing
- Auto-scroll to bottom on new messages
- Input only active when in this view

---

## Navigation Model

```
┌─────────────────────────────────────────────────────────────┐
│                        Dashboard                            │
│                    (PO cards + activity)                    │
│                            │                                │
│                     Enter / click                           │
│                            ▼                                │
│   ┌─────────────────────────────────────────────────────┐  │
│   │                    PO Detail                         │  │
│   │              (sessions + pending)                    │  │
│   │                        │                             │  │
│   │                 Enter / click                        │  │
│   │                        ▼                             │  │
│   │   ┌─────────────────────────────────────────────┐   │  │
│   │   │              Session Chat                    │   │  │
│   │   │           (conversation + input)             │   │  │
│   │   └─────────────────────────────────────────────┘   │  │
│   │                        │                             │  │
│   │                   Esc / ←                            │  │
│   │                        ▼                             │  │
│   │                  (back to PO Detail)                 │  │
│   └─────────────────────────────────────────────────────┘  │
│                            │                                │
│                       Esc / ←                               │
│                            ▼                                │
│                   (back to Dashboard)                       │
└─────────────────────────────────────────────────────────────┘
```

**Keyboard Navigation:**
| Key | Dashboard | PO Detail | Session Chat |
|-----|-----------|-----------|--------------|
| `↑↓←→` / `hjkl` | Navigate cards | Navigate sessions | Scroll history |
| `Enter` | Open PO | Open session | (n/a) |
| `Esc` / `←` | Quit | Back to dashboard | Back to PO |
| `i` | (n/a) | (n/a) | Insert mode |
| `n` | New PO | New session | (n/a) |
| `I` | Inspect selected | Inspect PO | (n/a) |
| `e` | Edit selected | Edit PO | (n/a) |
| `d` | (n/a) | Delete session | (n/a) |
| `?` | Help | Help | Help |
| `q` | Quit | Quit | Quit |

**Mouse Support:**
- Click PO card → Open PO detail
- Click session → Open session chat
- Click activity item → Navigate to source
- Click back arrow → Navigate back
- Scroll wheel → Scroll lists/chat

---

## State Management

### Screen State

```ruby
module PromptObjects
  module UI
    class App
      # Screen stack for navigation
      SCREEN_DASHBOARD = :dashboard
      SCREEN_PO_DETAIL = :po_detail
      SCREEN_SESSION_CHAT = :session_chat

      def initialize
        @screen_stack = [SCREEN_DASHBOARD]
        @selected_po = nil      # For PO detail/chat
        @selected_session = nil # For chat
      end

      def push_screen(screen, **context)
        @screen_stack.push(screen)
        case screen
        when SCREEN_PO_DETAIL
          @selected_po = context[:po]
        when SCREEN_SESSION_CHAT
          @selected_session = context[:session]
        end
      end

      def pop_screen
        @screen_stack.pop
        case current_screen
        when SCREEN_DASHBOARD
          @selected_po = nil
          @selected_session = nil
        when SCREEN_PO_DETAIL
          @selected_session = nil
        end
      end

      def current_screen
        @screen_stack.last
      end
    end
  end
end
```

### Sub-Models

```
lib/prompt_objects/ui/
├── app.rb                    # Main app, screen routing
├── screens/
│   ├── dashboard.rb          # Dashboard screen
│   ├── po_detail.rb          # PO detail screen
│   └── session_chat.rb       # Chat screen
├── components/
│   ├── po_card.rb            # PO card widget
│   ├── session_row.rb        # Session list item
│   ├── activity_feed.rb      # Activity feed widget
│   ├── message_bubble.rb     # Chat message
│   ├── chat_input.rb         # Input component
│   └── pending_request.rb    # Human request widget
└── styles.rb                 # Lipgloss styles
```

---

## Live Updates

With the daemon/event stream architecture:

```ruby
# Dashboard subscribes to all events
@env.event_stream.subscribe do |event|
  case event
  when Events::POStateChanged
    # Update PO card indicator
    refresh_po_card(event.po_name)

  when Events::MessageAdded
    # Update activity feed
    add_activity_entry(event)
    # Update session in PO detail if visible
    refresh_session_row(event.session_id) if showing_po_detail?

  when Events::HumanRequestQueued
    # Update PO card badge
    refresh_po_card(event.from_po)
    # Show in PO detail if visible
    refresh_pending_requests if showing_po_detail?

  when Events::ToolCallStarted
    # Show tool indicator on PO card
    show_tool_indicator(event.po_name, event.tool_name)
  end
end
```

---

## Implementation Phases

### Phase 1: Screen Infrastructure
- [ ] Screen stack navigation model
- [ ] Dashboard screen skeleton
- [ ] PO Detail screen skeleton
- [ ] Session Chat screen (migrate existing conversation)
- [ ] Back navigation (Esc / ←)

### Phase 2: Dashboard
- [ ] PO card component with indicators
- [ ] Grid layout for cards
- [ ] Card selection (keyboard + mouse)
- [ ] Activity feed component
- [ ] Navigate to PO detail on Enter

### Phase 3: PO Detail
- [ ] Session list component
- [ ] Session row with source indicators
- [ ] New session action
- [ ] Delete session action
- [ ] Pending requests display
- [ ] Navigate to chat on Enter

### Phase 4: Session Chat Polish
- [ ] Migrate existing conversation component
- [ ] Message bubbles with timestamps
- [ ] Markdown rendering (requires charm-native)
- [ ] Tool call display (inline, expandable)
- [ ] Working/typing indicator
- [ ] Auto-scroll

### Phase 5: Live Updates
- [ ] Wire event stream to dashboard
- [ ] PO state indicators update live
- [ ] Activity feed updates live
- [ ] Session "live" indicator for MCP/API activity
- [ ] Pending request badges

### Phase 6: Mouse Support
- [ ] Click handlers for cards
- [ ] Click handlers for sessions
- [ ] Click handlers for activity items
- [ ] Scroll wheel support
- [ ] Back button click

---

## Dependencies

| Dependency | Required For | Status |
|------------|--------------|--------|
| **charm-native** | Markdown rendering in chat | Blocked (need forks) |
| **Event Stream** | Live updates | Not started (Connectors Phase 1) |
| **Mouse support** | Click navigation | Bubbles gem supports it |

---

## Migration Strategy

1. **Keep existing UI working** during development
2. **Feature flag** for new dashboard (`--new-ui` or config)
3. **Incremental migration** - one screen at a time
4. **Parallel testing** - run both UIs, compare behavior
5. **Deprecate old UI** once new is stable

---

## Open Questions

1. **PO card size**: Fixed or responsive to content?
2. **Max cards per row**: 3? 4? Auto based on terminal width?
3. **Activity feed height**: Fixed or configurable?
4. **Session sort order**: By recency? By source? Configurable?
5. **Keyboard vs mouse primary**: Both equal, or keyboard-first?

---

## Success Criteria

- [ ] Dashboard shows all POs with live status
- [ ] Can navigate PO → sessions → chat with keyboard
- [ ] Can navigate with mouse clicks
- [ ] Activity feed shows real-time updates
- [ ] Pending human requests visible from dashboard
- [ ] MCP sessions show "live" indicator
- [ ] Tool calls visible on PO cards
- [ ] Chat messages render markdown properly
- [ ] Navigation feels snappy (<100ms transitions)
