# Session Management (Enhanced)

## Overview

Extend session capabilities beyond per-PO picker to include environment-wide session exploration, search, export/import, and cross-interface session tracking.

## Motivation

- **Global visibility**: See all sessions across all POs in an environment
- **Historical analysis**: Review past conversations from any interface (TUI, MCP, API)
- **Portability**: Export/import sessions for backup or sharing
- **Search**: Find sessions by content, date, or metadata
- **Multi-interface tracking**: Sessions created via MCP should be visible in TUI

## Current State

We have:
- Per-PO session picker (`S` key)
- SQLite session storage
- Create, rename, delete, switch sessions
- Session name in conversation panel title

## Planned Enhancements

### 1. Session Explorer Modal

Global view of all sessions across all POs in the environment.

```
┌─ Session Explorer ──────────────────────────────────────────┐
│                                                              │
│  Filter: [All POs ▼]  [All Sources ▼]  [Search: ________]   │
│                                                              │
│  PO             Session          Messages  Source   Updated  │
│  ─────────────────────────────────────────────────────────── │
│  coordinator    Planning task        24    tui      2m ago   │
│  coordinator    Debug session         8    mcp      1h ago   │
│  researcher     API investigation    15    tui      3h ago   │
│  coder          Refactoring          42    api      1d ago   │
│                                                              │
│  Total: 4 sessions, 89 messages                              │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ [Enter] View  [e] Export  [d] Delete  [/] Search  [Esc] Close│
└──────────────────────────────────────────────────────────────┘
```

**Keyboard shortcut**: `E` (Explorer) from main view

### 2. Session Source Tracking

Track which interface created/modified each session:

```ruby
# Session metadata additions
{
  source: "tui" | "mcp" | "api" | "web",
  source_client: "claude-desktop" | "cursor" | nil,
  created_via: "tui",
  last_message_via: "mcp"
}
```

### 3. Session Search

Search across all sessions:
- Full-text search in message content
- Filter by PO, date range, source
- Highlight matching messages

### 4. Session Export/Import

**Export formats:**
- JSON (full fidelity, re-importable)
- Markdown (human-readable, shareable)

```ruby
# Export single session
session_store.export(session_id, format: :json)
session_store.export(session_id, format: :markdown)

# Export all sessions for a PO
session_store.export_all(po_name: "coordinator", format: :json)

# Import
session_store.import(file_path)
```

**Markdown export format:**
```markdown
# Session: Planning task
- **PO**: coordinator
- **Created**: 2025-01-06 10:00
- **Messages**: 24

---

**User** (10:00):
Help me plan the refactoring task

**coordinator** (10:01):
I'll help you plan this. Let me break it down...
```

### 5. Session Commands

Conversation commands for session management:

| Command | Description |
|---------|-------------|
| `/sessions` | List sessions for current PO |
| `/session new [name]` | Create new session |
| `/session rename <name>` | Rename current session |
| `/session switch <name>` | Switch to named session |
| `/session export [format]` | Export current session |
| `/session info` | Show session metadata |

### 6. Session Analytics

Optional stats tracking:

```ruby
SessionStats = Struct.new(
  :total_messages,
  :user_messages,
  :assistant_messages,
  :total_tokens,        # If available from LLM
  :avg_response_time,
  :tool_calls,
  keyword_init: true
)
```

---

## Implementation Steps

### Step 1: Session Source Tracking
- Add `source` and `source_client` fields to session schema
- Update session store to accept source on create/append
- Pass source through Context

### Step 2: Session Explorer Model
- Create `session_explorer.rb` UI model
- List all sessions with filtering
- Sorting by date, PO, message count

### Step 3: Session Explorer Integration
- Add `E` key shortcut
- Wire up to app modal system
- Navigate and view sessions

### Step 4: Session Export
- JSON export with full metadata
- Markdown export for readability
- File save dialog or clipboard

### Step 5: Session Import
- Parse exported JSON
- Validate and merge into store
- Handle conflicts (same ID)

### Step 6: Session Search
- SQLite FTS (full-text search) on messages
- Search UI in explorer
- Result highlighting

### Step 7: Session Commands
- Parse `/session` commands in input
- Execute corresponding actions
- Feedback in conversation

---

## Data Schema Updates

```sql
-- Add to sessions table
ALTER TABLE sessions ADD COLUMN source TEXT DEFAULT 'tui';
ALTER TABLE sessions ADD COLUMN source_client TEXT;
ALTER TABLE sessions ADD COLUMN last_message_source TEXT;

-- Add FTS for search
CREATE VIRTUAL TABLE messages_fts USING fts5(
  content,
  content='messages',
  content_rowid='id'
);
```

---

## Open Questions

1. Should session export include tool call details?
2. How to handle very large sessions (1000+ messages)?
3. Session archiving vs deletion?
4. Cross-environment session copying?

---

## Future Enhancements

- Session branching (fork from a point)
- Session templates (start with predefined context)
- Session sharing URLs
- Collaborative sessions (multiple users)
- Session replay (step through history)
