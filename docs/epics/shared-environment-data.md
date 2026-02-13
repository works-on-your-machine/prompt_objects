# Shared Environment Data — Thread-Scoped Key-Value Store

**Status**: Design
**Priority**: High
**Depends on**: Session/thread infrastructure (complete)
**Supersedes**: Early brainstorm in `environment-data.md` (which explored full stigmergy/watch patterns — that's deferred to later phases)

---

## Problem

When POs communicate through delegation, the calling PO sends a natural language message to the target PO. But that message often lacks the *context* needed for the target to do its work well.

**ARC-AGI example**: The solver PO loads a puzzle grid, then delegates to an observer PO asking "what patterns do you notice?" The observer has no access to the grid — it wasn't passed in the message, and the observer can't call `load_arc_task` because it doesn't know which task to load. The solver would need to serialize the entire grid into its message, bloating the conversation and duplicating data.

**The deeper issue**: POs in a delegation chain are working on the same problem but don't share working memory. Each PO only sees what's explicitly passed to it via messages.

## Solution

A **thread-scoped, namespaced key-value store** that any PO in a delegation chain can read from and write to. Data is scoped to the delegation tree — when a solver starts working on a problem, any PO it delegates to (and any PO *they* delegate to) can access the same shared data.

### Data Shape

Each entry in the store has three fields:

```ruby
{
  key: String,              # Namespaced identifier, e.g. "arc_task", "findings", "current_file"
  short_description: String, # 1-2 sentence summary of what's in this key (for LLM discoverability)
  value: Object              # The actual data (Hash, Array, String, etc.) — serialized as JSON
}
```

The `short_description` is critical. When a PO calls `list_env_data()`, it gets back a lightweight manifest:

```json
[
  { "key": "arc_task", "short_description": "The current ARC-AGI puzzle: task ID training-001, a 3x3 input grid with colored cells and expected output." },
  { "key": "observed_patterns", "short_description": "Patterns the observer has identified so far: rotation symmetry, color mapping." },
  { "key": "solution_attempts", "short_description": "Previous solution attempts and their outcomes (2 attempts, both failed)." }
]
```

This lets the PO's LLM decide which keys are relevant to its task and selectively retrieve them, rather than dumping all shared data into context.

### Scoping: Thread-Local

Data is scoped to the **root thread** of a delegation chain. When a human sends a message to the coordinator, that creates a root thread. Any delegation threads spawned from it (coordinator -> solver -> observer) all share the same environment data scope.

```
Root Thread (human -> coordinator)
├── Delegation Thread (coordinator -> solver)
│   ├── solver calls store_env_data(key: "arc_task", ...)    ← writes to root scope
│   └── Delegation Thread (solver -> observer)
│       └── observer calls get_env_data(key: "arc_task")      ← reads from root scope
└── Delegation Thread (coordinator -> summarizer)
    └── summarizer calls list_env_data()                       ← sees all data in root scope
```

**Why thread-scoped (not global)**:
- Different conversations/tasks don't pollute each other
- Data lifecycle is clear — when the task is done, the data is naturally scoped to that work
- Avoids the "noisy global store" problem where POs have to sift through unrelated data
- Maps naturally to how delegation already works

**Future consideration**: Cross-thread data access and threads spawning other threads is an interesting direction (self-replicating, self-managing long-term applications), but is explicitly out of scope for this design. Thread-local is the right starting point.

---

## Universal Capabilities (CRUD)

Five new universal capabilities, available to all POs automatically:

### `store_env_data`

Write a new key or overwrite an existing one.

```ruby
store_env_data(
  key: "arc_task",
  short_description: "The current ARC-AGI puzzle: task ID training-001, 3x3 grid.",
  value: {
    task_id: "training-001",
    input_grid: [[0, 1, 2], [3, 4, 5], [6, 7, 8]],
    output_grid: [[8, 7, 6], [5, 4, 3], [2, 1, 0]]
  }
)
# Returns: "Stored 'arc_task' in environment data."
```

**Parameters**:
- `key` (String, required): The namespaced key
- `short_description` (String, required): 1-2 sentence description of the data
- `value` (Object, required): The data to store

### `get_env_data`

Retrieve a specific key's full value.

```ruby
get_env_data(key: "arc_task")
# Returns: { task_id: "training-001", input_grid: [...], output_grid: [...] }
```

**Parameters**:
- `key` (String, required): The key to retrieve

### `list_env_data`

List all keys and their descriptions (no values — keeps it lightweight).

```ruby
list_env_data()
# Returns:
# [
#   { key: "arc_task", short_description: "The current ARC-AGI puzzle..." },
#   { key: "observed_patterns", short_description: "Patterns identified so far..." }
# ]
```

**Parameters**: None.

### `update_env_data`

Update an existing key's value and/or description. Fails if the key doesn't exist (use `store_env_data` for create-or-replace).

```ruby
update_env_data(
  key: "observed_patterns",
  short_description: "Updated: 3 patterns identified including rotation symmetry.",
  value: ["rotation_symmetry", "color_mapping", "border_detection"]
)
# Returns: "Updated 'observed_patterns'."
```

**Parameters**:
- `key` (String, required): The key to update
- `short_description` (String, optional): New description (keeps existing if omitted)
- `value` (Object, optional): New value (keeps existing if omitted)

### `delete_env_data`

Remove a key from the store.

```ruby
delete_env_data(key: "solution_attempts")
# Returns: "Deleted 'solution_attempts' from environment data."
```

**Parameters**:
- `key` (String, required): The key to delete

---

## Walkthrough: ARC-AGI Solver + Observer

### Before (current behavior)

1. Human tells coordinator: "Solve ARC task training-001"
2. Coordinator delegates to solver: "Solve ARC task training-001"
3. Solver calls `load_arc_task(task_id: "training-001")` — gets the grid
4. Solver delegates to observer: "What patterns do you notice in this grid? Here's the data: [[0,1,2],[3,4,5]...]"
5. Observer receives a wall of serialized grid data in a natural language message
6. Observer has to parse it, reason about it, respond
7. If solver also wants to consult a transformer PO, it has to serialize the grid *again*

### After (with environment data)

1. Human tells coordinator: "Solve ARC task training-001"
2. Coordinator delegates to solver: "Solve ARC task training-001"
3. Solver calls `load_arc_task(task_id: "training-001")` — gets the grid
4. Solver calls `store_env_data(key: "arc_task", short_description: "Current ARC puzzle: training-001, 3x3 grid with color rotation pattern", value: { ... })`
5. Solver delegates to observer: "What patterns do you notice in the current task?"
6. Observer calls `list_env_data()` — sees `arc_task` is available with a description
7. Observer calls `get_env_data(key: "arc_task")` — gets the full grid
8. Observer reasons about it, stores findings: `store_env_data(key: "observed_patterns", ...)`
9. Observer responds to solver: "I found rotation symmetry and color mapping"
10. Solver calls `get_env_data(key: "observed_patterns")` — gets the structured findings
11. If solver delegates to a transformer PO next, it also just calls `get_env_data("arc_task")`

### What changed

- Messages between POs are about **intent** ("what patterns do you notice?"), not data smuggling
- Any PO in the chain can access shared context without it being explicitly passed
- Data is stored *once*, read by many
- The `short_description` lets POs discover what's available without loading everything
- Structured data stays structured (no serialize-into-natural-language-then-hope-LLM-parses-it-back)

---

## Other Scenarios

### Multi-step research

A researcher PO investigates a codebase:

```
store_env_data(key: "project_structure", short_description: "Directory layout and key files for the Rails app", value: {...})
store_env_data(key: "database_schema", short_description: "All models and their associations", value: {...})
store_env_data(key: "findings", short_description: "Issues and observations found during research", value: [...])
```

When the coordinator later delegates to a writer PO to draft documentation, the writer calls `list_env_data()`, sees the research is available, and pulls exactly what it needs.

### Code review pipeline

```
# Linter PO stores issues
store_env_data(key: "lint_results", short_description: "12 linting issues found: 3 errors, 9 warnings", value: [...])

# Fixer PO reads issues, stores fixes
get_env_data(key: "lint_results")
store_env_data(key: "applied_fixes", short_description: "Fixed 3/3 errors and 7/9 warnings", value: [...])

# Reviewer PO reads both to validate
get_env_data(key: "lint_results")
get_env_data(key: "applied_fixes")
```

### Knowledge accumulation across delegations

A coordinator delegates to several specialists over a long conversation. Each one stores what it learns. By the end, there's a rich shared knowledge base that any newly-created PO can immediately access via `list_env_data()` — no re-explaining needed.

---

## Implementation

### Storage

SQLite table in the existing session database:

```sql
CREATE TABLE env_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  root_thread_id TEXT NOT NULL,     -- scoped to the root thread of a delegation chain
  key TEXT NOT NULL,
  short_description TEXT NOT NULL,
  value TEXT NOT NULL,               -- JSON-serialized
  stored_by TEXT NOT NULL,           -- PO name that wrote this
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(root_thread_id, key)        -- one value per key per thread scope
);
```

### Thread Scope Resolution

When a PO calls `store_env_data` or `get_env_data`, the system needs to resolve which root thread to use. The context already tracks the delegation chain, so:

1. Look at the current thread/session
2. Walk up parent pointers to find the root thread
3. Use that root thread ID as the scope

```ruby
# In the universal capability:
def resolve_root_thread(context)
  session_id = context.current_session_id
  return session_id unless context.env.session_store

  # Walk up delegation chain to root
  current = session_id
  loop do
    session = context.env.session_store.get_session(current)
    parent = session&.dig(:parent_session_id)
    break unless parent
    current = parent
  end
  current
end
```

### Universal Capability Classes

Five new files in `lib/prompt_objects/universal/`:
- `store_env_data.rb`
- `get_env_data.rb`
- `list_env_data.rb`
- `update_env_data.rb`
- `delete_env_data.rb`

Each follows the existing universal capability pattern (extend `Capability`, define `name`, `description`, `parameters`, `receive`).

### Registration

Add to `UNIVERSAL_CAPABILITIES` array in `lib/prompt_objects.rb` and register in `Runtime#register_universal_capabilities`.

### WebSocket Broadcasting

When env data changes, broadcast to connected clients so the web UI can show a live data panel (similar to how delegation events are already broadcast):

```ruby
# In the store/update/delete capabilities:
context.env.broadcast_env_data_changed(key: key, action: :stored, stored_by: context.calling_po)
```

---

## Open Questions

1. **Size limits on values?** Should we cap the JSON size to prevent POs from dumping enormous data? Probably yes — maybe 100KB per key with a warning.
2. **Data lifetime**: Should env data be cleaned up when a root thread is "done"? Or persist for replay/inspection? Leaning toward persist — it's useful for debugging and the thread explorer.
3. **Conflict resolution**: If two POs in the same delegation tree write to the same key concurrently, last-write-wins is probably fine for now.
4. **Should `store_env_data` require human approval?** Probably not for the store itself, but the *watcher PO* pattern (see `watcher-po-and-reactive-patterns.md`) provides a human oversight layer for what happens *in response to* data changes.
