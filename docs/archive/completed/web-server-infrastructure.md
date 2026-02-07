# Web Server Infrastructure

**Status**: Complete
**Priority**: High
**Depends on**: Core framework (done)
**Design doc**: [web-server-design.md](../web-server-design.md)

## Overview

Build the Falcon-based web server and React frontend foundation. This epic covers the backend WebSocket infrastructure and basic frontend that proves the core loop works.

## Goals

- Falcon server serving static assets + WebSocket
- WebSocket handler integrated with MessageBus
- React + Zustand frontend with WebSocket connection
- End-to-end: send message → streaming response → rendered in UI

## Non-Goals

- Full UI (dashboard, detail views) - that's the next epic
- CLI integration - that's a later epic
- Authentication, multiple users

---

## Phase 1: Falcon Server (Ruby)

### Tasks

- [x] Add falcon and async-websocket to Gemfile
- [x] Create `lib/prompt_objects/server/` directory structure
- [x] Implement `Server::App` Rack application
  - [x] Route WebSocket upgrade requests
  - [x] Route `/api/*` to API handler
  - [x] Serve static files from `public/`
  - [x] SPA fallback (serve index.html for unknown routes)
- [x] Implement `Server::WebSocketHandler`
  - [x] Subscribe to MessageBus on connect
  - [x] Subscribe to HumanQueue for notifications
  - [x] Send initial PO state on connect
  - [x] Handle incoming messages (send_message, respond_to_notification)
  - [x] Broadcast state changes, stream chunks, bus messages
  - [x] Fix tui_mode context for proper ask_human blocking
- [x] Implement basic `Server::API::Routes`
  - [x] GET /api/prompt_objects
  - [x] GET /api/prompt_objects/:name
  - [x] GET /api/environment
- [x] Manual testing with wscat/curl

### Exit Criteria

```bash
# Start server manually in console
ruby -r prompt_objects -e "
  env = PromptObjects::Environment.load('./test-env')
  app = PromptObjects::Server::App.new(env)
  # ... start Falcon
"

# In another terminal
wscat -c ws://localhost:3000
> {"type": "send_message", "payload": {"target": "greeter", "content": "hello"}}
# See streaming response chunks
```

---

## Phase 2: React Frontend Foundation

### Tasks

- [x] Set up `frontend/` directory with Vite + React + TypeScript
- [x] Configure Tailwind CSS
- [x] Create Zustand store with full state shape
  - [x] promptObjects: Record<string, PromptObject>
  - [x] busMessages: BusMessage[]
  - [x] notifications: Notification[]
  - [x] selectedPO, streamingContent, busOpen, activeTab
- [x] Implement `useWebSocket` hook
  - [x] Connect on mount
  - [x] Route incoming messages to store actions
  - [x] Expose sendMessage, respondToNotification
- [x] Build full UI (exceeded minimal goals)
  - [x] Header with environment name, notification bell with badge
  - [x] Dashboard with PO cards grid
  - [x] PO detail view with tabs (Chat, Sessions, Capabilities)
  - [x] Chat with markdown rendering and syntax highlighting
  - [x] Split view layout (see dashboard while chatting)
  - [x] Message bus sidebar
  - [x] Notification panel with response UI
- [x] Configure Vite for development (direct WS connection in dev mode)
- [x] Build script outputs to `lib/prompt_objects/server/public/`

### Exit Criteria

```bash
# Terminal 1: Ruby server
ruby script/dev_server.rb ./test-env

# Terminal 2: Vite dev server
cd frontend && npm run dev

# Browser: http://localhost:5173
# - See PO list
# - Click PO, type message
# - See streaming response appear
```

---

## File Structure

```
lib/prompt_objects/
├── server/
│   ├── app.rb                 # Main Rack app
│   ├── websocket_handler.rb   # WS connection manager
│   ├── api/
│   │   └── routes.rb          # REST endpoints
│   └── public/                # Built frontend (gitignored during dev)

frontend/
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── store/
│   │   └── index.ts           # Zustand store
│   ├── hooks/
│   │   └── useWebSocket.ts
│   ├── components/
│   │   ├── Header.tsx
│   │   ├── POCard.tsx
│   │   └── Chat.tsx
│   └── types/
│       └── index.ts
├── package.json
├── vite.config.ts
└── tailwind.config.js
```

---

## Technical Notes

### Falcon + WebSocket

```ruby
# Using async-websocket adapter
Async::WebSocket::Adapters::Rack.open(env, protocols: ['json']) do |connection|
  handler = WebSocketHandler.new(environment: @environment, connection: connection)
  handler.run
end
```

### MessageBus Integration

The WebSocketHandler subscribes to MessageBus and receives callbacks:
- `on_message(from:, to:, content:, timestamp:)` - bus traffic
- `on_po_state_change(po_name:, state:)` - PO state updates
- `on_stream_chunk(po_name:, chunk:)` - LLM streaming
- `on_notification(notification)` - human-in-the-loop requests

### Vite Dev Proxy

```typescript
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      '/api': 'http://localhost:3000',
      '/ws': {
        target: 'ws://localhost:3000',
        ws: true
      }
    }
  }
})
```

---

## Open Questions

1. Should we use a single WebSocket endpoint or separate ones for different concerns?
2. How to handle WebSocket reconnection in the frontend?
3. Rate limiting for messages to prevent abuse?

---

## Related

- [web-server-design.md](../web-server-design.md) - Full design document
- [web-ui-complete.md](web-ui-complete.md) - Next epic (dashboard + features)
