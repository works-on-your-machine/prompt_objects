# Phase 6: Multiple Named Sessions

## Overview

Enable multiple independent conversation sessions per PromptObject. Each session maintains its own history, allowing users to have parallel conversations with the same PO for different contexts or tasks.

## Motivation

- **Context separation**: Keep different topics/tasks in separate conversations
- **Experimentation**: Try different approaches without polluting main conversation
- **Persistence**: Save and resume conversations across app restarts
- **Collaboration**: Share specific sessions without exposing all history

## Core Concepts

### Session

A session represents a single conversation thread with a PromptObject:

```ruby
Session = Struct.new(
  :id,           # UUID
  :name,         # User-friendly name ("Default", "Debug task", etc.)
  :po_name,      # Which PO this session belongs to
  :history,      # Array of messages [{role:, content:, ...}]
  :created_at,
  :updated_at,
  :metadata      # Optional tags, notes, etc.
)
```

### Session Manager

Central registry for all sessions:

```ruby
class SessionManager
  def create(po_name:, name: "New Session")
  def list(po_name: nil)  # All sessions, or filtered by PO
  def get(session_id)
  def rename(session_id, new_name)
  def delete(session_id)
  def duplicate(session_id, new_name:)
  def export(session_id)  # JSON/Markdown export
  def import(data)
end
```

## Architecture

### File Structure

```
lib/prompt_objects/
├── session.rb              # Session data class
├── session_manager.rb      # CRUD operations
├── session_storage.rb      # Persistence layer
└── ui/
    └── models/
        └── session_picker.rb  # Session selection modal
```

### Storage

Sessions stored as JSON files:

```
.prompt_objects/
└── sessions/
    ├── index.json           # Session metadata index
    ├── {uuid-1}.json        # Full session with history
    ├── {uuid-2}.json
    └── ...
```

**index.json** (fast loading without reading all histories):
```json
{
  "sessions": [
    {
      "id": "uuid-1",
      "name": "Default",
      "po_name": "coordinator",
      "message_count": 12,
      "created_at": "2025-01-03T10:00:00Z",
      "updated_at": "2025-01-03T14:30:00Z"
    }
  ]
}
```

**{uuid}.json** (full session):
```json
{
  "id": "uuid-1",
  "name": "Default",
  "po_name": "coordinator",
  "history": [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi there!"}
  ],
  "created_at": "2025-01-03T10:00:00Z",
  "updated_at": "2025-01-03T14:30:00Z",
  "metadata": {}
}
```

## Implementation Steps

### Step 1: Session Model & Manager

1. Create `Session` class with validation
2. Create `SessionManager` with in-memory operations
3. Add default session creation when PO is first used
4. Update `PromptObject#receive` to use session history instead of `@history`

### Step 2: Session Storage

1. Create `SessionStorage` class for file I/O
2. Implement lazy loading (only load full history when needed)
3. Auto-save on message append
4. Handle concurrent access (file locking or single-writer)

### Step 3: Environment Integration

1. Add `SessionManager` to `Environment`
2. Update `Context` to track current session
3. Modify `PromptObject` to accept session parameter:
   ```ruby
   po.receive(message, context:, session:)
   ```

### Step 4: UI - Session Indicator

1. Show current session name in conversation panel title
2. Add session info to status bar
3. Visual indicator for unsaved changes

### Step 5: UI - Session Picker Modal

New modal (triggered by `S` key) showing:

```
┌─ Sessions for: coordinator ─────────────────┐
│                                             │
│  > [*] Default (12 messages)         14:30  │
│    [ ] Debug investigation (3 msgs)  12:15  │
│    [ ] API integration (8 msgs)      Yesterday│
│                                             │
│  [n] New  [d] Delete  [r] Rename           │
├─────────────────────────────────────────────┤
│ [Enter] Select  [Esc] Cancel               │
└─────────────────────────────────────────────┘
```

Features:
- List all sessions for current PO
- Show message count and last activity
- Create new session
- Rename session
- Delete session (with confirmation)
- Switch between sessions

### Step 6: UI - Quick Session Actions

1. `S` - Open session picker
2. `N` - New session (quick create)
3. Session name in panel title: `┌─ coordinator: Default ─┐`

### Step 7: Session Commands

Add commands accessible via conversation:

- `/sessions` - List sessions
- `/session new [name]` - Create new session
- `/session rename [name]` - Rename current
- `/session switch [name]` - Switch to named session
- `/session delete` - Delete current (with confirm)
- `/session export` - Export to markdown

### Step 8: Auto-save & Recovery

1. Auto-save after each message exchange
2. Crash recovery from last saved state
3. Periodic backup of active sessions
4. Session pruning (delete old empty sessions)

### Step 9: Session Sharing (Optional)

1. Export session to shareable format (Markdown with metadata)
2. Import session from file
3. Copy session between POs (if compatible)

## Data Migration

For existing users with conversation history:

1. On first run of new version, check for POs with non-empty `@history`
2. Create "Migrated" session containing existing history
3. Clear `@history` from PO (now managed by sessions)

## UI Mockup

### Conversation Panel with Session

```
┌─ coordinator: Default ────────────────────┐
│ A coordinator that orchestrates tasks...  │
│                                           │
│ You: Hello there                          │
│                                           │
│ coordinator: Hi! How can I help you       │
│ today?                                    │
│                                           │
│                                           │
│                                           │
└───────────────────────────────────────────┘
```

### Status Bar with Session Info

```
[i] insert  [h/l] PO  [S] sessions  [q] quit    Session: Default (12 msgs)
```

## API Changes

### PromptObject

```ruby
# Before
po.receive(message, context:)
po.history  # => Array

# After
po.receive(message, context:, session:)
# po.history removed - use session.history instead
```

### Environment

```ruby
env.session_manager  # => SessionManager
env.current_session  # => Session (convenience accessor)
```

### Context

```ruby
context.session      # => Current Session
context.session_id   # => UUID string
```

## Edge Cases

1. **Deleted PO with sessions**: Keep sessions, mark as orphaned, allow re-association
2. **Renamed PO**: Update `po_name` in all associated sessions
3. **Concurrent sessions**: Only one session active per PO at a time in UI
4. **Large histories**: Implement pagination or summarization for very long sessions
5. **Session conflicts**: Handle if same session opened in multiple app instances

## Testing Strategy

1. Unit tests for Session and SessionManager
2. Integration tests for storage persistence
3. Manual UI testing for session picker
4. Migration testing with sample data

## Future Enhancements

- Session templates (start with predefined context)
- Session branching (fork from a point in history)
- Session search (find sessions by content)
- Session analytics (token usage, response times)
- Collaborative sessions (multiple users)
