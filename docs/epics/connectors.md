# Connectors: Multi-Interface Runtime

## Overview

Enable environments/images to be accessed through multiple interfaces beyond the TUI. The environment is the persistent data store; connectors are different ways to interact with it.

```
                    ┌─────────────────────────────────────┐
                    │         Environment/Image           │
                    │                                     │
                    │  ┌─────────┐ ┌─────────┐ ┌───────┐ │
                    │  │   POs   │ │Sessions │ │Prims  │ │
                    │  └─────────┘ └─────────┘ └───────┘ │
                    │                                     │
                    │  ┌───────────────────────────────┐  │
                    │  │     Runtime (shared state)    │  │
                    │  └───────────────────────────────┘  │
                    └─────────────────────────────────────┘
                              ▲       ▲       ▲
                              │       │       │
              ┌───────────────┼───────┼───────┼───────────────┐
              │               │       │       │               │
         ┌────┴────┐    ┌────┴───┐ ┌─┴──┐ ┌──┴───┐    ┌─────┴─────┐
         │   TUI   │    │  MCP   │ │API │ │ Web  │    │  Future   │
         │ Manager │    │ Server │ │    │ │  UI  │    │ Connectors│
         └─────────┘    └────────┘ └────┘ └──────┘    └───────────┘
              │               │       │       │               │
              ▼               ▼       ▼       ▼               ▼
         Developer       Claude    Custom  Browser         Slack,
         Terminal        Desktop   Apps    Users           Discord,
                         Cursor                            Webhooks
```

## Motivation

- **Flexibility**: Use the right interface for the task
- **Integration**: Claude Desktop, Cursor, custom apps can connect
- **Separation**: End users interact via clean UI, not raw POs
- **Shareability**: Share an image; recipient runs it as MCP server
- **Observability**: TUI can watch sessions from any connector in real-time

## Key Decision: Gem Executable (Not Embedded)

**Approach**: The gem provides executables that run environments in different modes.

```bash
# TUI mode (existing)
prompt_objects_tui --env my-assistant

# MCP server mode (new)
prompt_objects serve --mcp ~/.prompt_objects/environments/my-assistant

# API server mode (future)
prompt_objects serve --api --port 3000 ~/.prompt_objects/environments/my-assistant

# Multiple modes simultaneously (future)
prompt_objects serve --mcp --api ~/.prompt_objects/environments/my-assistant
```

**Why not embed executable in image:**
- Would need to bundle Ruby + gems (~50MB+)
- Platform-specific builds (macOS, Linux, Windows)
- Image size explodes from ~1KB to ~50MB
- Updates require re-bundling every image
- The gem already handles this cleanly

**Sharing workflow:**
1. Export environment: `prompt_objects export my-assistant` → `my-assistant.poenv`
2. Share the `.poenv` file (or zip of environment directory)
3. Recipient imports: `prompt_objects import my-assistant.poenv`
4. Recipient runs: `prompt_objects serve --mcp my-assistant`

---

## Phase 1: MCP Server Mode

### Executable

```bash
# New executable: exe/prompt_objects_serve
prompt_objects serve --mcp <environment-name-or-path>
```

Or extend existing MCP server to accept environment:
```bash
prompt_objects_mcp --env my-assistant
```

### Claude Desktop Configuration

```json
{
  "mcpServers": {
    "my-assistant": {
      "command": "prompt_objects",
      "args": ["serve", "--mcp", "my-assistant"]
    },
    "work-tools": {
      "command": "prompt_objects",
      "args": ["serve", "--mcp", "/path/to/work-tools"]
    }
  }
}
```

### MCP Tools Exposed

| Tool | Description |
|------|-------------|
| `list_prompt_objects` | List all POs in the environment |
| `send_message` | Send message to a PO (creates/continues session) |
| `list_sessions` | List sessions (optionally filtered by PO) |
| `get_conversation` | Get session history |

### Session Management

- MCP connections create sessions tagged with `source: "mcp"`
- Optional: Track `source_client` from MCP client info
- Sessions persist and are visible in TUI

### Concurrent Access

Multiple interfaces can connect to same environment:
- SQLite handles concurrent reads
- Write locking for session updates
- TUI can watch MCP sessions in real-time

---

## Phase 2: REST API Server

### Executable

```bash
prompt_objects serve --api --port 3000 my-assistant
```

### Endpoints

```
GET  /api/pos                    # List POs
GET  /api/pos/:name              # Get PO details
POST /api/pos/:name/message      # Send message
GET  /api/sessions               # List sessions
GET  /api/sessions/:id           # Get session
POST /api/sessions               # Create session
DELETE /api/sessions/:id         # Delete session
```

### Authentication

- API key in header: `Authorization: Bearer <key>`
- Keys stored in environment config
- Optional: No auth for local-only mode

---

## Phase 3: Web UI

### Purpose

Provide a clean interface for end-users who don't need to see individual POs.

```
┌─────────────────────────────────────────────────────────────┐
│  My Assistant                                    [Settings] │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │  You: Help me plan my week                         │   │
│  │                                                     │   │
│  │  Assistant: I'd be happy to help! Let me check     │   │
│  │  your calendar and create a plan...                │   │
│  │                                                     │   │
│  │  [Thinking: Checking calendar via calendar_po...]  │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Type a message...                            [Send] │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Features

- Single "assistant" facade (routes to coordinator PO)
- Hides internal PO delegation
- Optional: Show which PO is responding
- Session history sidebar
- Mobile-friendly

### Implementation Options

1. **Embedded server**: Sinatra/Roda serving static + API
2. **Separate frontend**: React/Vue app connecting to API
3. **LiveView-style**: Hotwire/Turbo for real-time updates

---

## Phase 4: Additional Connectors

### Slack Bot

```yaml
# In environment config
connectors:
  slack:
    enabled: true
    bot_token: ${SLACK_BOT_TOKEN}
    default_po: coordinator
    channels:
      - "#assistant"
```

### Discord Bot

```yaml
connectors:
  discord:
    enabled: true
    bot_token: ${DISCORD_BOT_TOKEN}
    default_po: coordinator
```

### Webhooks (Inbound)

```yaml
connectors:
  webhooks:
    enabled: true
    endpoints:
      - path: /hooks/github
        po: code_reviewer
        secret: ${GITHUB_WEBHOOK_SECRET}
```

### Email

```yaml
connectors:
  email:
    enabled: true
    imap:
      server: imap.gmail.com
      username: ${EMAIL_USER}
    watch_folders: ["INBOX"]
    default_po: email_handler
```

---

## Architecture

### Connector Interface

```ruby
module PromptObjects
  module Connectors
    class Base
      def initialize(runtime:, config:)
        @runtime = runtime
        @config = config
      end

      # Start the connector (blocking or background)
      def start
        raise NotImplementedError
      end

      # Stop gracefully
      def stop
        raise NotImplementedError
      end

      # Connector identifier for session tracking
      def source_name
        raise NotImplementedError
      end
    end
  end
end
```

### MCP Connector

```ruby
module PromptObjects
  module Connectors
    class MCP < Base
      def start
        # Start stdio MCP server
        # Handle tool calls by routing to POs
        # Create sessions tagged with source: "mcp"
      end

      def source_name
        "mcp"
      end
    end
  end
end
```

### Multi-Connector Runner

```ruby
# prompt_objects serve --mcp --api my-assistant
runner = ConnectorRunner.new(
  runtime: runtime,
  connectors: [:mcp, :api]
)
runner.start  # Runs all connectors
```

---

## Implementation Steps

### Step 1: Refactor MCP Server
- Extract MCP logic from current executable
- Create `Connectors::MCP` class
- Accept runtime as parameter

### Step 2: Session Source Tracking
- Add source field to sessions
- Pass source through connector → runtime → session store

### Step 3: Serve Command
- New `exe/prompt_objects` with `serve` subcommand
- `--mcp` flag for MCP mode
- Load environment by name or path

### Step 4: TUI Live View
- Watch for session changes from other connectors
- Show "live" indicator when MCP session active
- Optional: Real-time message streaming

### Step 5: API Connector
- Sinatra/Roda minimal server
- REST endpoints
- API key auth

### Step 6: Web UI
- Static HTML + JS
- Connect to API
- Clean user-facing interface

---

## Configuration

### Environment Manifest

```yaml
# manifest.yml additions
connectors:
  mcp:
    enabled: true
  api:
    enabled: true
    port: 3000
    auth:
      type: api_key
      keys:
        - name: default
          key_hash: "sha256:..."
  web:
    enabled: true
    port: 8080
    default_po: coordinator
```

### CLI Flags Override Config

```bash
# Config says port 3000, but run on 4000
prompt_objects serve --api --port 4000 my-assistant
```

---

## Open Questions

1. How to handle long-running PO tasks across connector restarts?
2. Should connectors share sessions or have isolated sessions?
3. Rate limiting for API/Web?
4. How to expose PO capabilities in Web UI (or hide them)?
5. Multi-tenant support (multiple users, same environment)?

---

## Future Enhancements

- **Connector marketplace**: Share connector configs
- **Connector composition**: Chain connectors (webhook → Slack)
- **Connector analytics**: Track usage per connector
- **Connector health**: Monitor and restart failed connectors
- **Federation**: Multiple environments communicating
