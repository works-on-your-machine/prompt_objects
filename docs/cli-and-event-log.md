# CLI Interface & Persistent Event Log

## Motivation

### The Problem

Right now there are three ways to interact with a PO environment:

1. **Web UI** (`prompt_objects serve --web`) — full-featured, real-time, but requires a browser and running server
2. **REPL** (`prompt_objects repl`) — interactive stdin/stdout, but uses legacy mode (no env_path, no sessions)
3. **MCP** (`prompt_objects serve --mcp`) — for Claude Desktop/Cursor, but a separate process with its own runtime

None of these support a clean **batch/scripting workflow**: send a message to a PO, get the result, done. This matters because:

- **Claude Code** needs to be able to interact with PO environments via Bash tool calls
- **Rapid iteration** on ARC-AGI solving means creating an environment, sending it a task, reading the result, tweaking, repeat
- **CI/testing** needs non-interactive invocation
- **Composition** — piping PO output into other tools, scripting multi-step workflows

### The Architecture

**HTTP Hub**: the web server is the single runtime. CLI and MCP are clients.

```
┌─────────┐  HTTP   ┌──────────────────────────────┐  WebSocket  ┌─────────┐
│  CLI    │────────▶│  Web Server (single Runtime)  │◀───────────▶│ Browser │
└─────────┘         │                                │             └─────────┘
                    │  REST API                      │
┌─────────┐ stdio  │  WebSocket handler              │
│  MCP    │────────▶│  MCP server (embedded)         │
│ clients │         │                                │
└─────────┘         │  MessageBus ─▶ in-memory (live)│
                    │             └─▶ events table   │
                    │                (persistent)    │
                    └──────────────────────────────────┘
```

One process, one runtime. Everything routes through it:
- **Web UI** connects via WebSocket (as now)
- **CLI** sends HTTP requests to the running server's REST API
- **MCP** runs embedded in the same process
- **All actions from all interfaces** flow through the same message bus, get persisted to the same event log, and stream to the web UI in real time

If no server is running, CLI falls back to standalone mode (ephemeral runtime, still writes to sessions.db and events table).

### Why This Over Alternatives

We considered three architectures:

1. **HTTP Hub** (this one) — single runtime, everything is a client
2. **Shared Disk + DB** — multiple runtimes sharing filesystem and SQLite
3. **Event-Sourced** — append-only event log as coordination mechanism

Option 2 has too much sync complexity (file watchers, DB polling, registry drift). Option 3 is philosophically elegant but over-engineers the coordination layer. Option 1 is simplest and gives instant real-time updates.

The persistent event log from option 3 is included as a **feature** (the message bus also writes to SQLite) rather than as the primary coordination mechanism.

### The Message Bus Problem

The current message bus truncates messages at storage time (`truncate_message` in `message_bus.rb:77`). Full tool call arguments, tool results, and PO responses are chopped to 100 characters with newlines stripped — before they even hit the in-memory log. This means:

- You can't inspect what a tool actually received or returned
- You can't trace through an ARC solving run to see what the solver tried
- You can't debug why a PO made a particular decision
- The "semantic binding made visible" promise of the message bus is undermined

The fix: store full messages, truncate only at display time. The persistent event log stores everything. The web UI shows a summary view with expandable full content.

---

## Implementation Steps

### Phase 1: Message Bus — Store Full, Display Truncated

**Goal**: Full messages available for inspection without breaking the existing UI.

**Changes:**

1. **`message_bus.rb`** — Store full message, add separate `summary` field:
   ```ruby
   def publish(from:, to:, message:)
     entry = {
       timestamp: Time.now,
       from: from,
       to: to,
       message: message,          # full content (String or Hash)
       summary: summarize(message) # truncated for display
     }
     @log << entry
     notify_subscribers(entry)
     entry
   end
   ```

2. **REPL `show_interaction_log`** — Use `entry[:summary]` for the compact log display (no change to UX).

3. **WebSocket handler** — Send both `summary` (for the message bus panel) and `message` (for detail view) to the frontend.

4. **Frontend MessageBus component** — Show summary in the stream, click to expand full content.

### Phase 2: Persistent Event Log

**Goal**: All message bus events persisted to SQLite for historical replay and cross-session tracing.

**Changes:**

1. **`message_bus.rb`** — Accept optional `session_store` at initialization. On each `publish`, also write to an `events` table:
   ```ruby
   def initialize(session_store: nil)
     @log = []
     @subscribers = []
     @store = session_store
   end

   def publish(from:, to:, message:, session_id: nil)
     entry = { ... }
     @log << entry
     @store&.add_event(entry.merge(session_id: session_id))
     notify_subscribers(entry)
     entry
   end
   ```

2. **`session/store.rb`** — Add `events` table and methods:
   ```sql
   CREATE TABLE IF NOT EXISTS events (
     id INTEGER PRIMARY KEY AUTOINCREMENT,
     session_id TEXT,
     timestamp TEXT NOT NULL,
     from_name TEXT NOT NULL,
     to_name TEXT NOT NULL,
     message TEXT NOT NULL,
     event_type TEXT,
     created_at TEXT DEFAULT CURRENT_TIMESTAMP
   );
   CREATE INDEX idx_events_session ON events(session_id);
   CREATE INDEX idx_events_timestamp ON events(timestamp);
   ```

   Methods:
   - `add_event(entry)` — insert event row
   - `get_events(session_id:)` — all events for a session
   - `get_events_since(timestamp)` — for catch-up when web UI reconnects
   - `get_events_between(start, end)` — for historical queries
   - `search_events(query)` — full-text search across event messages

3. **`environment.rb`** — Pass session_store to MessageBus on initialization:
   ```ruby
   @bus = MessageBus.new(session_store: @session_store)
   ```

4. **`prompt_object.rb`** — Include `session_id` when publishing to bus, so events are linked to sessions.

### Phase 3: REST Message Endpoint

**Goal**: Send messages to POs via HTTP, enabling the CLI client.

**Changes:**

1. **`server/api/routes.rb`** — Add POST endpoint:
   ```ruby
   when ["POST", %r{^/prompt_objects/([^/]+)/message$}]
     send_message(path_param(path, 1), request.body.read)
   ```

   The `send_message` method:
   - Parses the JSON body (`{ "message": "...", "session_id": "..." }`)
   - Looks up the PO in the registry
   - Calls `po.receive(message, context:)` (same as WebSocket handler)
   - Returns JSON with the response, session_id, and event count
   - All tool calls stream to WebSocket subscribers in real time (because it's the same runtime)

2. **Server discovery** — Write a `.server` file to the environment directory on startup:
   ```json
   {"pid": 12345, "port": 3000, "host": "localhost", "started_at": "..."}
   ```
   Remove on shutdown. CLI checks for this file to know where to send requests.

### Phase 4: CLI `message` Command

**Goal**: `prompt_objects message <env> <po> "message"` — send a message and print the response.

**Changes:**

1. **`exe/prompt_objects`** — Add `message` command:
   ```ruby
   when "message"
     run_message(args)
   ```

   `run_message`:
   - Parse args: `env_name`, `po_name`, `message_text`
   - Check for `.server` file in the environment directory
   - If server running: POST to `http://host:port/api/prompt_objects/:name/message`
   - If no server: start a standalone Runtime, send the message, print response, exit
   - Print the PO's response to stdout
   - Optional `--events` flag to also print the event log for the interaction
   - Optional `--json` flag for machine-readable output

2. **Additional CLI commands** (using the same server-or-standalone pattern):
   ```bash
   prompt_objects message <env> <po> "text"    # Send message, print response
   prompt_objects info <env>                    # List POs, primitives, stats
   prompt_objects events <env> [--session ID]   # Show recent events
   prompt_objects primitives <env>              # List registered primitives
   ```

### Phase 5: Embedded MCP Server

**Goal**: MCP clients connect to the running web server process instead of spawning a separate one.

**Changes:**

1. **MCP transport**: The current MCP server uses stdio transport (read stdin, write stdout). For embedding in the web server, add SSE (Server-Sent Events) transport or a WebSocket-based MCP transport. This lets Claude Desktop connect to the running server rather than spawning a separate process.

2. **Alternatively**: Keep MCP as a separate thin process that forwards to the web server's HTTP API (like the CLI does). This is simpler and doesn't require a new MCP transport:
   ```
   Claude Desktop --stdio--> MCP bridge process --HTTP--> Web Server (Runtime)
   ```

   The bridge process is ~50 lines: read MCP JSON-RPC from stdin, translate to HTTP calls, write responses back.

This phase is lower priority — the CLI covers the Claude Code use case, and MCP-via-bridge is a straightforward wrapper once the HTTP API exists.

### Phase 6: Web UI — Event History & Full Message Inspection

**Goal**: Browse historical events, inspect full messages, trace through past runs.

**Changes:**

1. **MessageBus panel** — Show summary, click to expand full message content
2. **Session detail view** — Show the event timeline for a session (all tool calls, arguments, results)
3. **Historical events** — Load events from the database, not just the live in-memory log
4. **Search** — Search across event messages ("find all events where grid_diff was called")
5. **Run comparison** — Side-by-side view of two solving attempts on the same task (future)

---

## Summary

| Phase | What | Enables |
|-------|------|---------|
| 1 | Full messages in bus | Inspecting tool arguments and results |
| 2 | Persistent event log | Historical replay, cross-session tracing |
| 3 | REST message endpoint | CLI and external clients |
| 4 | CLI `message` command | Claude Code interaction, scripting, CI |
| 5 | Embedded MCP | Single-process MCP for Claude Desktop |
| 6 | Web UI history | Browse past runs, search events, compare attempts |

Phases 1-4 are the critical path. Phase 5 is nice-to-have. Phase 6 is ongoing polish.
