# Web Server Architecture for PromptObjects

## Overview

This document describes the architecture for serving PromptObjects environments via a web interface, using Falcon as the async Ruby web server.

### The Smalltalk Parallel

```
Smalltalk VM     ←→  PromptObjects gem (runtime)
Smalltalk Image  ←→  .poenv bundle (POs + state)
Smalltalk UI     ←→  React web interface
```

The gem is the universal runtime. Images are portable, shareable bundles containing Prompt Objects and their state. Users install the runtime once, then load any image.

### Design Principles

1. **One interface at a time** - TUI or web, not both simultaneously (for now)
2. **Image format is the contract** - UIs come and go, images are stable
3. **Core runtime is UI-agnostic** - Server and TUI are peers, both talk to the same core
4. **Streaming-first** - Falcon's async model enables natural LLM streaming

---

## V1 Scope

Based on design discussions, V1 focuses on proving the core loop works via web interface.

### V1 Goals

- **Input**: Manual trigger (send message through UI)
- **Output**: Chat responses (proves LLM integration works)
- **UI**: Dashboard + detail view (PO cards, drill into one)

### What V1 Is NOT

- Not a visual flowchart/graph of PO relationships
- Not supporting webhooks, file watching, or scheduled triggers (yet)
- Not generating dynamic UIs from POs (deferred)
- Not running multiple interfaces simultaneously

### Primary Use Case

Once POs are built, they mostly run automatically. Human interaction is primarily:
- **Shaping the environment** - editing POs, adding capabilities
- **Monitoring** - watching outputs, checking status
- **Occasional intervention** - responding to human-in-the-loop requests

Chat is available but not the center of the experience.

### V1 UI Structure

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Header: Environment name, global notification count                     │
├────────────────────────────────────────────────┬────────────────────────┤
│                                                │                        │
│  Dashboard (main area)                         │  Message Bus           │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐          │  (collapsible right    │
│  │ PO Card │ │ PO Card │ │ PO Card │          │   sidebar)             │
│  │         │ │         │ │         │          │                        │
│  │ name    │ │ name    │ │ name    │          │  [timestamp] from→to   │
│  │ status  │ │ status  │ │ status  │          │  [timestamp] from→to   │
│  │ notifs  │ │ notifs  │ │ notifs  │          │  [timestamp] from→to   │
│  │ sessions│ │ sessions│ │ sessions│          │                        │
│  └─────────┘ └─────────┘ └─────────┘          │                        │
│                                                │                        │
│  Click card → PO Detail View                   │                        │
│                                                │                        │
└────────────────────────────────────────────────┴────────────────────────┘

PO Detail View (replaces dashboard when drilling in):
┌─────────────────────────────────────────────────────────────────────────┐
│  ← Back to Dashboard          PO Name                    [Edit] [...]   │
├─────────────────────────────────────────────────────────────────────────┤
│  [Chat] [Sessions] [Capabilities] [Edit]    ← Tabs                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Tab Content Area                                                       │
│                                                                         │
│  Chat tab: conversation + input                                         │
│  Sessions tab: list of sessions, switch/create/rename                   │
│  Capabilities tab: list of capabilities PO has access to                │
│  Edit tab: Monaco editor for PO markdown                                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### PO Card Contents

Each card on the dashboard shows:
- **Name** - PO identifier
- **Status indicator** - idle / busy / waiting for human
- **Notification badge** - count of pending human requests
- **Session info** - number of sessions, active session indicator

### Notifications

- **Global**: Header shows total count across all POs, click to see list
- **Per-PO**: When in detail view, see that PO's pending requests
- **Response**: Modal or inline form to respond to human-in-the-loop requests

### UI Feel

Clean and modern. Works well with both keyboard and mouse. Not overly dense (website) but not overly sparse (desktop app). Dark mode support.

### Deferred Decisions

- **Visual canvas/graph**: Not convinced flowchart model is right for stigmergic coordination. Revisit after v1.
- **Dynamic PO-generated views**: Focus on chat first.
- **Infinite canvas (tldraw)**: Interesting idea, but spatial layout may not matter for this domain.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                 React Application                      │  │
│  │  - Capability Graph        - Session Panels           │  │
│  │  - Message Log             - PO Inspector             │  │
│  │  - Conversation View       - Dynamic Views            │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │ WebSocket
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Falcon Server                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Static      │  │ API         │  │ WebSocket           │  │
│  │ Assets      │  │ Routes      │  │ Handler             │  │
│  │ (React)     │  │ (REST)      │  │ (real-time)         │  │
│  └─────────────┘  └─────────────┘  └──────────┬──────────┘  │
└──────────────────────────────────────────────┬──────────────┘
                                               │
                                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     Core Runtime                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Capability  │  │ Message     │  │ LLM                 │  │
│  │ Registry    │  │ Bus         │  │ Client              │  │
│  └─────────────┘  └──────┬──────┘  └─────────────────────┘  │
│  ┌─────────────┐         │         ┌─────────────────────┐  │
│  │ Environment │         │         │ Session             │  │
│  │ Manager     │         │         │ Store               │  │
│  └─────────────┘         │         └─────────────────────┘  │
└──────────────────────────┼──────────────────────────────────┘
                           │ Subscribe/Publish
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                        Image                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ objects/    │  │ primitives/ │  │ sessions.db         │  │
│  │ *.md        │  │ *.rb        │  │ (SQLite)            │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐                           │
│  │ manifest.yml│  │ .git/       │                           │
│  └─────────────┘  └─────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Image Format

Images are the portable unit of distribution. An image contains everything needed to run a set of Prompt Objects.

### Directory Structure

```
my-environment/
├── manifest.yml          # Metadata
├── objects/              # Prompt Objects
│   ├── greeter.md
│   ├── reader.md
│   └── coordinator.md
├── primitives/           # Custom primitives
│   └── custom_http.rb
├── sessions.db           # Conversation history (SQLite)
└── .git/                 # Version history (optional)
```

### manifest.yml

```yaml
name: my-environment
version: 1
created_at: 2025-01-10T12:00:00Z
description: My collection of helpful agents
template: developer

# Optional metadata
author: Your Name
tags: [productivity, coding]
```

### Bundle Format (.poenv)

For distribution, images can be packaged as `.poenv` files (zip archives):

```bash
# Export
prompt_objects export my-agents.poenv

# Contents of my-agents.poenv:
#   manifest.yml
#   objects/
#   primitives/
#   sessions.db (optional, can exclude with --no-sessions)
```

---

## Falcon Server

### Dependencies

```ruby
# Gemfile additions
gem 'falcon', '~> 0.47'
gem 'async-websocket', '~> 0.26'
```

### File Structure

```
lib/prompt_objects/
├── server/
│   ├── app.rb                 # Main Rack application
│   ├── websocket_handler.rb   # WebSocket connection manager
│   ├── api/
│   │   ├── routes.rb          # REST API routes
│   │   ├── prompt_objects.rb  # PO CRUD endpoints
│   │   └── sessions.rb        # Session endpoints
│   └── public/                # Built frontend assets
│       ├── index.html
│       └── assets/
│           ├── main.[hash].js
│           └── main.[hash].css
```

### Main Application

```ruby
# lib/prompt_objects/server/app.rb
require 'async/websocket/adapters/rack'
require 'json'

module PromptObjects
  module Server
    class App
      STATIC_EXTENSIONS = %w[.html .js .css .png .svg .ico .woff .woff2].freeze

      def initialize(environment)
        @environment = environment
        @api = API::Routes.new(environment)
        @public_path = File.expand_path('public', __dir__)
      end

      def call(env)
        request_path = env['PATH_INFO']

        if websocket_request?(env)
          handle_websocket(env)
        elsif request_path.start_with?('/api/')
          @api.call(env)
        elsif static_asset?(request_path)
          serve_static(request_path)
        else
          serve_index
        end
      end

      private

      def websocket_request?(env)
        env['HTTP_UPGRADE']&.downcase == 'websocket'
      end

      def handle_websocket(env)
        Async::WebSocket::Adapters::Rack.open(env, protocols: ['json']) do |connection|
          handler = WebSocketHandler.new(
            environment: @environment,
            connection: connection
          )
          handler.run
        end
      end

      def static_asset?(path)
        STATIC_EXTENSIONS.any? { |ext| path.end_with?(ext) }
      end

      def serve_static(path)
        file_path = File.join(@public_path, path)

        if File.exist?(file_path)
          content_type = content_type_for(path)
          body = File.read(file_path)
          [200, { 'content-type' => content_type }, [body]]
        else
          [404, { 'content-type' => 'text/plain' }, ['Not found']]
        end
      end

      def serve_index
        index_path = File.join(@public_path, 'index.html')
        body = File.read(index_path)
        [200, { 'content-type' => 'text/html' }, [body]]
      end

      def content_type_for(path)
        case File.extname(path)
        when '.html' then 'text/html'
        when '.js' then 'application/javascript'
        when '.css' then 'text/css'
        when '.json' then 'application/json'
        when '.svg' then 'image/svg+xml'
        when '.png' then 'image/png'
        else 'application/octet-stream'
        end
      end
    end
  end
end
```

### WebSocket Handler

```ruby
# lib/prompt_objects/server/websocket_handler.rb
require 'json'
require 'async'

module PromptObjects
  module Server
    class WebSocketHandler
      def initialize(environment:, connection:)
        @environment = environment
        @connection = connection
        @subscribed = false
      end

      def run
        subscribe_to_bus
        send_initial_state
        read_loop
      ensure
        unsubscribe_from_bus
      end

      # === MessageBus Callbacks ===

      def on_message(from:, to:, content:, timestamp:)
        send_message(
          type: 'bus_message',
          payload: {
            from: from,
            to: to,
            content: content,
            timestamp: timestamp.iso8601
          }
        )
      end

      def on_po_state_change(po_name:, state:)
        send_message(
          type: 'po_state',
          payload: {
            name: po_name,
            state: state
          }
        )
      end

      def on_stream_chunk(po_name:, chunk:)
        send_message(
          type: 'stream',
          payload: {
            target: po_name,
            chunk: chunk
          }
        )
      end

      def on_stream_complete(po_name:)
        send_message(
          type: 'stream_end',
          payload: { target: po_name }
        )
      end

      def on_notification(notification)
        send_message(
          type: 'notification',
          payload: notification.to_h
        )
      end

      private

      def subscribe_to_bus
        @environment.message_bus.subscribe(self)
        @subscribed = true
      end

      def unsubscribe_from_bus
        @environment.message_bus.unsubscribe(self) if @subscribed
      end

      def send_initial_state
        # Send current state of all POs
        @environment.registry.prompt_objects.each do |po|
          send_message(
            type: 'po_state',
            payload: {
              name: po.name,
              state: po.to_state_hash
            }
          )
        end

        # Send pending notifications
        @environment.notification_queue.pending.each do |notification|
          send_message(
            type: 'notification',
            payload: notification.to_h
          )
        end
      end

      def read_loop
        while (message = @connection.read)
          handle_client_message(message)
        end
      rescue Async::Wrapper::Cancelled, EOFError
        # Connection closed, exit gracefully
      end

      def handle_client_message(raw_message)
        message = JSON.parse(raw_message.buffer)

        case message['type']
        when 'send_message'
          handle_send_message(message['payload'])
        when 'respond_to_notification'
          handle_notification_response(message['payload'])
        when 'update_po'
          handle_update_po(message['payload'])
        when 'create_session'
          handle_create_session(message['payload'])
        when 'switch_session'
          handle_switch_session(message['payload'])
        else
          send_error("Unknown message type: #{message['type']}")
        end
      rescue JSON::ParserError => e
        send_error("Invalid JSON: #{e.message}")
      rescue => e
        send_error("Error: #{e.message}")
      end

      def handle_send_message(payload)
        po_name = payload['target']
        content = payload['content']

        po = @environment.registry.get(po_name)

        unless po
          send_error("Unknown prompt object: #{po_name}")
          return
        end

        # Run in async context for streaming
        Async do
          po.receive(content, context: @environment) do |chunk|
            # Stream callback
            on_stream_chunk(po_name: po_name, chunk: chunk)
          end
          on_stream_complete(po_name: po_name)
        end
      end

      def handle_notification_response(payload)
        notification_id = payload['id']
        response = payload['response']

        @environment.notification_queue.respond(notification_id, response)
      end

      def handle_update_po(payload)
        po_name = payload['name']
        updates = payload['updates']

        po = @environment.registry.get(po_name)
        po.update(updates) if po
      end

      def handle_create_session(payload)
        po_name = payload['target']
        session_name = payload['name']

        po = @environment.registry.get(po_name)
        session = po.create_session(session_name) if po

        send_message(
          type: 'session_created',
          payload: { target: po_name, session: session.to_h }
        )
      end

      def handle_switch_session(payload)
        po_name = payload['target']
        session_id = payload['session_id']

        po = @environment.registry.get(po_name)
        po.switch_session(session_id) if po
      end

      def send_message(data)
        @connection.write(JSON.generate(data))
        @connection.flush
      end

      def send_error(message)
        send_message(type: 'error', payload: { message: message })
      end
    end
  end
end
```

### REST API Routes

```ruby
# lib/prompt_objects/server/api/routes.rb
require 'json'

module PromptObjects
  module Server
    module API
      class Routes
        def initialize(environment)
          @environment = environment
        end

        def call(env)
          request = Rack::Request.new(env)
          path = request.path_info.sub('/api', '')

          response = route(request, path)
          json_response(response)
        rescue => e
          json_response({ error: e.message }, status: 500)
        end

        private

        def route(request, path)
          case [request.request_method, path]

          # Prompt Objects
          when ['GET', '/prompt_objects']
            list_prompt_objects
          when ['GET', %r{^/prompt_objects/([^/]+)$}]
            get_prompt_object($1)
          when ['PUT', %r{^/prompt_objects/([^/]+)$}]
            update_prompt_object($1, request.body.read)
          when ['POST', '/prompt_objects']
            create_prompt_object(request.body.read)

          # Sessions
          when ['GET', %r{^/prompt_objects/([^/]+)/sessions$}]
            list_sessions($1)
          when ['GET', %r{^/prompt_objects/([^/]+)/sessions/([^/]+)$}]
            get_session($1, $2)

          # Environment
          when ['GET', '/environment']
            get_environment_info

          else
            { error: 'Not found' }
          end
        end

        def list_prompt_objects
          pos = @environment.registry.prompt_objects.map(&:to_summary_hash)
          { prompt_objects: pos }
        end

        def get_prompt_object(name)
          po = @environment.registry.get(name)
          po ? po.to_full_hash : { error: 'Not found' }
        end

        def update_prompt_object(name, body)
          po = @environment.registry.get(name)
          return { error: 'Not found' } unless po

          updates = JSON.parse(body)
          po.update(updates)
          { success: true, prompt_object: po.to_full_hash }
        end

        def create_prompt_object(body)
          params = JSON.parse(body)
          po = @environment.create_prompt_object(params)
          { success: true, prompt_object: po.to_full_hash }
        end

        def list_sessions(po_name)
          po = @environment.registry.get(po_name)
          return { error: 'Not found' } unless po

          { sessions: po.sessions.map(&:to_summary_hash) }
        end

        def get_session(po_name, session_id)
          po = @environment.registry.get(po_name)
          return { error: 'Not found' } unless po

          session = po.get_session(session_id)
          session ? session.to_full_hash : { error: 'Session not found' }
        end

        def get_environment_info
          {
            name: @environment.name,
            path: @environment.path,
            prompt_object_count: @environment.registry.prompt_objects.count,
            primitive_count: @environment.registry.primitives.count
          }
        end

        def json_response(data, status: 200)
          [
            status,
            { 'content-type' => 'application/json' },
            [JSON.generate(data)]
          ]
        end
      end
    end
  end
end
```

---

## WebSocket Protocol

### Message Format

All messages are JSON with a `type` field and a `payload` field.

### Client → Server Messages

```typescript
// Send a message to a Prompt Object
{
  type: 'send_message',
  payload: {
    target: 'reader',          // PO name
    content: 'What files are in src/?'
  }
}

// Respond to a notification (human-in-the-loop)
{
  type: 'respond_to_notification',
  payload: {
    id: 'notif_123',
    response: 'yes'            // or custom input
  }
}

// Update a Prompt Object
{
  type: 'update_po',
  payload: {
    name: 'reader',
    updates: {
      capabilities: ['read_file', 'list_files', 'http_get']
    }
  }
}

// Create a new session
{
  type: 'create_session',
  payload: {
    target: 'reader',
    name: 'Exploring the API'
  }
}

// Switch to a different session
{
  type: 'switch_session',
  payload: {
    target: 'reader',
    session_id: 'sess_456'
  }
}
```

### Server → Client Messages

```typescript
// Full PO state (sent on connect and on changes)
{
  type: 'po_state',
  payload: {
    name: 'reader',
    state: {
      status: 'idle',                    // idle | thinking | calling_tool
      current_tool: null,                // or 'list_files'
      description: 'Helps read files',
      capabilities: ['read_file', 'list_files'],
      current_session: {
        id: 'sess_123',
        name: 'Main',
        messages: [
          { role: 'user', content: '...' },
          { role: 'assistant', content: '...' }
        ]
      },
      sessions: [
        { id: 'sess_123', name: 'Main', message_count: 5 },
        { id: 'sess_456', name: 'API exploration', message_count: 12 }
      ]
    }
  }
}

// Streaming token from LLM
{
  type: 'stream',
  payload: {
    target: 'reader',
    chunk: 'Let me look at '
  }
}

// Stream complete
{
  type: 'stream_end',
  payload: {
    target: 'reader'
  }
}

// Message bus event (for visualization)
{
  type: 'bus_message',
  payload: {
    from: 'reader',
    to: 'list_files',
    content: { path: 'src/' },
    timestamp: '2025-01-10T12:00:00Z'
  }
}

// Human-in-the-loop notification
{
  type: 'notification',
  payload: {
    id: 'notif_123',
    po_name: 'coordinator',
    type: 'confirm_action',
    message: 'Create a new file at src/utils.rb?',
    options: ['yes', 'no']
  }
}

// Error
{
  type: 'error',
  payload: {
    message: 'Unknown prompt object: foo'
  }
}
```

---

## CLI Commands

```ruby
# lib/prompt_objects/cli.rb
require 'thor'
require 'async'

module PromptObjects
  class CLI < Thor
    desc "serve PATH", "Serve an environment via web UI"
    option :port, type: :numeric, default: 3000, aliases: '-p'
    option :host, type: :string, default: 'localhost', aliases: '-h'
    option :open, type: :boolean, default: false, aliases: '-o',
           desc: "Open browser automatically"
    def serve(path)
      environment = load_environment(path)
      app = Server::App.new(environment)

      url = "http://#{options[:host]}:#{options[:port]}"

      puts "PromptObjects v#{VERSION}"
      puts "Environment: #{environment.name}"
      puts "Serving at: #{url}"
      puts
      puts "Press Ctrl+C to stop"

      open_browser(url) if options[:open]

      Async do
        endpoint = Async::HTTP::Endpoint.parse(url)
        server = Falcon::Server.new(
          Falcon::Server.middleware(app),
          endpoint
        )
        server.run
      end
    end

    desc "tui PATH", "Run terminal UI for an environment"
    option :dev, type: :boolean, default: false
    def tui(path)
      # Existing TUI implementation
      environment = load_environment(path)
      UI::App.new(environment).run
    end

    desc "new NAME", "Create a new environment"
    option :template, type: :string, default: 'minimal',
           desc: "Template: minimal, developer, writer"
    def new(name)
      path = File.expand_path(name)
      Environment.create(path, template: options[:template])
      puts "Created environment at #{path}"
      puts
      puts "Next steps:"
      puts "  cd #{name}"
      puts "  poop serve ."
    end

    desc "export PATH", "Export environment as .poenv bundle"
    option :output, type: :string, aliases: '-o'
    option :include_sessions, type: :boolean, default: true
    def export(path)
      environment = load_environment(path)
      output = options[:output] || "#{environment.name}.poenv"

      environment.export(output, include_sessions: options[:include_sessions])
      puts "Exported to #{output}"
    end

    desc "import BUNDLE", "Import a .poenv bundle"
    option :path, type: :string, desc: "Where to extract (default: bundle name)"
    def import(bundle)
      path = options[:path] || File.basename(bundle, '.poenv')
      Environment.import(bundle, to: path)
      puts "Imported to #{path}"
    end

    private

    def load_environment(path)
      expanded = File.expand_path(path)

      if path.end_with?('.poenv')
        # Load from bundle (extracts to temp, or we could serve directly)
        Environment.load_bundle(expanded)
      else
        Environment.load(expanded)
      end
    end

    def open_browser(url)
      case RUBY_PLATFORM
      when /darwin/
        system("open", url)
      when /linux/
        system("xdg-open", url)
      when /mswin|mingw/
        system("start", url)
      end
    end
  end
end
```

---

## Frontend Architecture

### Tech Stack

- **React 18** - UI framework
- **Zustand** - State management (simple, no boilerplate)
- **Monaco** - PO markdown editing (in Edit tab)
- **Tailwind CSS** - Styling
- **Vite** - Build tool

Note: React Flow / capability graph visualization is deferred. May revisit post-v1.

### Directory Structure

```
frontend/
├── src/
│   ├── main.tsx                    # Entry point
│   ├── App.tsx                     # Root component, routing
│   ├── store/
│   │   ├── index.ts                # Zustand store
│   │   └── websocket.ts            # WS connection manager
│   ├── components/
│   │   ├── Layout/
│   │   │   ├── Header.tsx          # Env name, global notifications
│   │   │   ├── MainLayout.tsx      # Dashboard + sidebar structure
│   │   │   └── BusSidebar.tsx      # Collapsible right sidebar
│   │   ├── Dashboard/
│   │   │   ├── Dashboard.tsx       # Grid of PO cards
│   │   │   └── POCard.tsx          # Single PO summary card
│   │   ├── PODetail/
│   │   │   ├── PODetail.tsx        # Container with tabs
│   │   │   ├── ChatTab.tsx         # Conversation UI
│   │   │   ├── SessionsTab.tsx     # Session list + management
│   │   │   ├── CapabilitiesTab.tsx # Capabilities list
│   │   │   └── EditTab.tsx         # Monaco editor for markdown
│   │   ├── Chat/
│   │   │   ├── MessageList.tsx     # Conversation messages
│   │   │   ├── Message.tsx         # Single message
│   │   │   ├── StreamingMessage.tsx# In-progress streaming
│   │   │   └── ChatInput.tsx       # Message input
│   │   ├── MessageBus/
│   │   │   ├── BusLog.tsx          # Message log in sidebar
│   │   │   └── BusMessage.tsx      # Single bus message
│   │   ├── Notifications/
│   │   │   ├── NotificationBadge.tsx  # Header badge
│   │   │   ├── NotificationList.tsx   # Global list
│   │   │   └── NotificationModal.tsx  # Response modal
│   │   └── Sessions/
│   │       └── SessionList.tsx     # List with actions
│   ├── hooks/
│   │   ├── useWebSocket.ts         # WS connection + message handling
│   │   └── usePromptObject.ts      # PO-specific helpers
│   └── types/
│       └── index.ts                # TypeScript types
├── public/
├── package.json
├── vite.config.ts
└── tailwind.config.js
```

### State Management (Zustand)

```typescript
// frontend/src/store/index.ts
import { create } from 'zustand'

interface PromptObject {
  name: string
  description: string
  status: 'idle' | 'thinking' | 'calling_tool'
  currentTool: string | null
  capabilities: string[]
  currentSession: Session
  sessions: SessionSummary[]
}

interface Session {
  id: string
  name: string
  messages: Message[]
}

interface BusMessage {
  from: string
  to: string
  content: any
  timestamp: string
}

interface Notification {
  id: string
  poName: string
  type: string
  message: string
  options: string[]
}

interface Store {
  // State
  promptObjects: Record<string, PromptObject>
  busMessages: BusMessage[]
  notifications: Notification[]
  selectedPO: string | null
  streamingContent: Record<string, string>  // po_name -> partial content
  busOpen: boolean                           // right sidebar state
  activeTab: 'chat' | 'sessions' | 'capabilities' | 'edit'

  // Computed (via selectors)
  // globalNotificationCount - sum of all PO notifications
  // notificationsForPO(name) - filtered for specific PO

  // Actions
  setPromptObject: (name: string, state: PromptObject) => void
  addBusMessage: (message: BusMessage) => void
  addNotification: (notification: Notification) => void
  removeNotification: (id: string) => void
  selectPO: (name: string | null) => void
  appendStreamChunk: (poName: string, chunk: string) => void
  clearStream: (poName: string) => void
  toggleBus: () => void
  setActiveTab: (tab: Store['activeTab']) => void
}

export const useStore = create<Store>((set) => ({
  promptObjects: {},
  busMessages: [],
  notifications: [],
  selectedPO: null,
  streamingContent: {},

  setPromptObject: (name, state) =>
    set((s) => ({
      promptObjects: { ...s.promptObjects, [name]: state }
    })),

  addBusMessage: (message) =>
    set((s) => ({
      busMessages: [...s.busMessages.slice(-99), message]  // Keep last 100
    })),

  addNotification: (notification) =>
    set((s) => ({
      notifications: [...s.notifications, notification]
    })),

  removeNotification: (id) =>
    set((s) => ({
      notifications: s.notifications.filter((n) => n.id !== id)
    })),

  selectPO: (name) => set({ selectedPO: name }),

  appendStreamChunk: (poName, chunk) =>
    set((s) => ({
      streamingContent: {
        ...s.streamingContent,
        [poName]: (s.streamingContent[poName] || '') + chunk
      }
    })),

  clearStream: (poName) =>
    set((s) => {
      const { [poName]: _, ...rest } = s.streamingContent
      return { streamingContent: rest }
    })
}))
```

### WebSocket Hook

```typescript
// frontend/src/hooks/useWebSocket.ts
import { useEffect, useRef, useCallback } from 'react'
import { useStore } from '../store'

export function useWebSocket() {
  const ws = useRef<WebSocket | null>(null)
  const {
    setPromptObject,
    addBusMessage,
    addNotification,
    appendStreamChunk,
    clearStream
  } = useStore()

  useEffect(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    ws.current = new WebSocket(`${protocol}//${window.location.host}`)

    ws.current.onmessage = (event) => {
      const message = JSON.parse(event.data)

      switch (message.type) {
        case 'po_state':
          setPromptObject(message.payload.name, message.payload.state)
          break
        case 'stream':
          appendStreamChunk(message.payload.target, message.payload.chunk)
          break
        case 'stream_end':
          clearStream(message.payload.target)
          break
        case 'bus_message':
          addBusMessage(message.payload)
          break
        case 'notification':
          addNotification(message.payload)
          break
      }
    }

    return () => ws.current?.close()
  }, [])

  const sendMessage = useCallback((poName: string, content: string) => {
    ws.current?.send(JSON.stringify({
      type: 'send_message',
      payload: { target: poName, content }
    }))
  }, [])

  const respondToNotification = useCallback((id: string, response: string) => {
    ws.current?.send(JSON.stringify({
      type: 'respond_to_notification',
      payload: { id, response }
    }))
  }, [])

  return { sendMessage, respondToNotification }
}
```

### Build & Bundle

```json
// frontend/package.json
{
  "name": "prompt-objects-frontend",
  "scripts": {
    "dev": "vite",
    "build": "vite build --outDir ../lib/prompt_objects/server/public",
    "preview": "vite preview"
  }
}
```

The built assets go directly into the gem's server/public directory.

---

## Streaming Flow

```
User types message
        │
        ▼
┌─────────────────┐
│ React Frontend  │  sendMessage('reader', 'What files?')
└────────┬────────┘
         │ WebSocket
         ▼
┌─────────────────┐
│ WebSocketHandler│  handle_send_message
└────────┬────────┘
         │ Async task
         ▼
┌─────────────────┐
│  PromptObject   │  receive(message)
└────────┬────────┘
         │ Calls LLM with streaming
         ▼
┌─────────────────┐
│   LLM Client    │  stream_completion(messages) { |chunk| ... }
└────────┬────────┘
         │ Each chunk
         ▼
┌─────────────────┐
│ WebSocketHandler│  on_stream_chunk(po_name, chunk)
└────────┬────────┘
         │ WebSocket
         ▼
┌─────────────────┐
│ React Frontend  │  appendStreamChunk → re-render
└─────────────────┘
```

---

## Migration Path

### Phase 1: Server Infrastructure (Ruby)

1. Add Falcon and async-websocket to Gemfile
2. Create `lib/prompt_objects/server/` structure
3. Implement basic Rack App with routing
4. Implement WebSocketHandler with MessageBus subscription
5. Test with curl/wscat - verify WS connects and receives state

**Exit criteria**: Can connect via WebSocket, receive PO state, send a message, get streaming response.

### Phase 2: Frontend Foundation (React)

1. Set up Vite + React + TypeScript + Tailwind in `frontend/`
2. Implement Zustand store with all state shape
3. Implement useWebSocket hook
4. Build minimal UI: header + single hardcoded PO card + chat
5. Wire up to real WebSocket - see streaming work end-to-end

**Exit criteria**: Can load page, see POs, send message, see streaming response.

### Phase 3: Dashboard + Detail Views

1. Dashboard with PO cards grid
2. PO detail view with tab structure
3. Chat tab (conversation + input)
4. Navigation between dashboard and detail
5. Message bus sidebar (collapsible)

**Exit criteria**: Full navigation flow works. Can chat with any PO.

### Phase 4: Feature Completion

1. Sessions tab (list, switch, create, rename)
2. Capabilities tab (view capabilities)
3. Edit tab (Monaco editor)
4. Notifications (global badge + list + response modal)
5. File watching for hot reload during development

**Exit criteria**: Feature parity with TUI for core workflows.

### Phase 5: CLI + Bundling

1. Add `serve` command to CLI
2. Build script to bundle frontend into gem
3. Test gem installation + serve flow
4. Add `export`/`import` commands for .poenv bundles

**Exit criteria**: `gem install prompt_objects && poop serve ./my-env` works.

### Future (Post-V1)

- Visual canvas/graph exploration (tldraw, React Flow, or something else)
- Webhooks, file watching, scheduled triggers
- Dynamic PO-generated views
- Multi-interface (TUI + web simultaneously)
- Authentication for remote access
- Mobile responsive design

---

## Open Questions

1. **Hot reload in development** - During frontend development, want Vite dev server proxying to Ruby. Need to set this up.

2. **File change detection** - When user edits PO markdown in external editor, should we watch filesystem and push updates? Probably yes.

3. **Multiple browser tabs** - Current design allows it. Is this desired behavior or should we warn/prevent?

4. **Error handling UX** - How to surface Ruby errors, LLM errors, WebSocket disconnects gracefully?

5. **Stigmergy / Environment Data** - Vague but important. How does shared data space work? What's the API for POs to read/write environment data?

---

## Resolved Decisions

- **Primary view**: Dashboard with PO cards (not graph-first, not chat-first)
- **Message bus**: Collapsible right sidebar
- **Frontend stack**: React + Zustand (not htmx, not vanilla)
- **PO detail**: Tabbed sections (Chat, Sessions, Capabilities, Edit)
- **Notifications**: Global header badge + per-PO when in detail view
- **Dynamic PO views**: Deferred
- **Visual canvas**: Deferred (spatial layout may not matter for stigmergic model)
- **UI feel**: Clean and modern, keyboard + mouse friendly

---

## Non-Goals (For Now)

- Running TUI and web simultaneously on same image
- Multi-user collaboration
- Cloud hosting / authentication
- Real-time sync between multiple images
- Visual flowchart/graph of PO relationships
- Webhooks, file watching, scheduled triggers as inputs
- Mobile-first responsive design
