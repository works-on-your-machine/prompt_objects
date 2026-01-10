# Connectors: Reactive Multi-Interface Runtime

## Vision

A PromptObjects environment as a **living system** (like a Smalltalk image):
- Multiple entry points (TUI, MCP, HTTP API, WebSocket, custom)
- Shared state that's reactive across all interfaces
- POs themselves can spawn interfaces (web servers, API endpoints)
- Deployable anywhere - local dev, server, cloud
- Remote inspection/modification via TUI over SSH

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Environment "Image"                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   Core Daemon Process                        ││
│  │                                                              ││
│  │  ┌──────────┐  ┌──────────┐  ┌───────────────────────────┐  ││
│  │  │ Runtime  │  │ Session  │  │      Event Stream         │  ││
│  │  │  (POs)   │  │  Store   │  │       (pub/sub)           │  ││
│  │  └──────────┘  └──────────┘  └─────────────┬─────────────┘  ││
│  │                                            │                 ││
│  │  ┌─────────────────────────────────────────┼───────────────┐││
│  │  │              Connector Layer            │               │││
│  │  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────────┴───────────┐   │││
│  │  │  │ IPC  │ │ MCP  │ │ HTTP │ │   PO-Spawned         │   │││
│  │  │  │socket│ │stdio │ │ API  │ │   Interfaces         │   │││
│  │  │  └──┬───┘ └──┬───┘ └──┬───┘ └──────────────────────┘   │││
│  │  └─────┼────────┼────────┼────────────────────────────────┘││
│  └────────┼────────┼────────┼─────────────────────────────────┘│
└───────────┼────────┼────────┼──────────────────────────────────┘
            │        │        │
     ┌──────┘        │        └──────┐
     │               │               │
┌────┴────┐    ┌─────┴────┐    ┌─────┴─────┐
│   TUI   │    │  Claude  │    │    Web    │
│ (client)│    │ Desktop  │    │  Browser  │
└─────────┘    └──────────┘    └───────────┘
```

**Key insight**: TUI becomes a **client** that connects to the daemon, not the owner of the runtime.

---

## Core Concepts

### 1. Environment Daemon

The daemon is the "image" - a long-running process that owns:
- Runtime (PO instances, registry, primitives)
- Session store (SQLite)
- Message bus
- Event stream
- All connectors

```bash
# Start daemon (explicit)
prompt_objects daemon start --env myenv

# Or auto-starts when first client connects
prompt_objects tui --env myenv  # starts daemon if not running
```

### 2. Event Stream

Internal pub/sub system for reactive updates. All state changes emit events.

```ruby
module PromptObjects
  module Events
    # Session events
    SessionCreated = Data.define(:session_id, :po_name, :source)
    SessionDeleted = Data.define(:session_id)

    # Message events
    MessageAdded = Data.define(:session_id, :message_id, :role, :content, :source)

    # PO events
    POStateChanged = Data.define(:po_name, :old_state, :new_state)
    POLoaded = Data.define(:po_name)
    POUnloaded = Data.define(:po_name)

    # Human queue events
    HumanRequestQueued = Data.define(:request_id, :from_po, :question)
    HumanRequestResponded = Data.define(:request_id, :response)

    # Connector events
    ConnectorAttached = Data.define(:connector_type, :connector_id)
    ConnectorDetached = Data.define(:connector_type, :connector_id)

    # Bus events (inter-PO messages)
    BusEntry = Data.define(:from, :to, :message, :timestamp)
  end
end
```

```ruby
class EventStream
  def initialize
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @all_subscribers = []
    @mutex = Mutex.new
  end

  # Subscribe to specific event types, or all events
  def subscribe(*event_types, &block)
    @mutex.synchronize do
      if event_types.empty?
        @all_subscribers << block
      else
        event_types.each { |t| @subscribers[t] << block }
      end
    end
    # Return unsubscribe proc
    -> { unsubscribe(event_types, block) }
  end

  def publish(event)
    @mutex.synchronize do
      # Notify type-specific subscribers
      @subscribers[event.class].each { |sub| sub.call(event) }
      # Notify all-event subscribers
      @all_subscribers.each { |sub| sub.call(event) }
    end
  end
end
```

### 3. Connector Protocol

All interfaces speak the same protocol. Commands flow in, events flow out.

```ruby
module PromptObjects
  module Protocol
    # === Commands (client → daemon) ===

    # PO interaction
    SendMessage = Data.define(:po_name, :message, :session_id)
    ListPOs = Data.define()
    InspectPO = Data.define(:po_name)

    # Session management
    ListSessions = Data.define(:po_name, :source)  # nil = all
    GetSession = Data.define(:session_id)
    CreateSession = Data.define(:po_name, :name)
    DeleteSession = Data.define(:session_id)
    SwitchSession = Data.define(:po_name, :session_id)

    # Subscriptions
    Subscribe = Data.define(:event_types)  # empty = all events
    Unsubscribe = Data.define(:subscription_id)

    # Human queue
    ListPendingRequests = Data.define()
    RespondToRequest = Data.define(:request_id, :response)

    # === Responses (daemon → client) ===

    # Immediate responses
    POList = Data.define(:pos)
    POInfo = Data.define(:name, :description, :state, :capabilities, :session_id)
    SessionList = Data.define(:sessions)
    SessionInfo = Data.define(:session)
    MessageResponse = Data.define(:po_name, :response, :session_id)
    RequestList = Data.define(:requests)

    # Subscription confirmation
    Subscribed = Data.define(:subscription_id, :event_types)

    # Errors
    Error = Data.define(:code, :message, :details)

    # === Pushed Events (daemon → subscribed clients) ===

    # Wrapper for events pushed to subscribers
    EventNotification = Data.define(:subscription_id, :event)
  end
end
```

### 4. IPC Transport

Unix domain socket for local communication. Fast, secure, no network overhead.

```ruby
class IPCServer
  SOCKET_PATH_TEMPLATE = "/tmp/prompt_objects_%{env_name}.sock"

  def initialize(runtime:, event_stream:, env_name:)
    @runtime = runtime
    @event_stream = event_stream
    @socket_path = SOCKET_PATH_TEMPLATE % { env_name: env_name }
    @clients = {}
  end

  def start
    cleanup_stale_socket
    @server = UNIXServer.new(@socket_path)

    loop do
      client = @server.accept
      handle_client(client)
    end
  end

  private

  def handle_client(socket)
    Thread.new do
      client_id = SecureRandom.uuid
      @clients[client_id] = ClientConnection.new(socket, client_id)

      loop do
        command = read_command(socket)
        break if command.nil?  # Client disconnected

        response = process_command(command, client_id)
        write_response(socket, response)
      end
    ensure
      @clients.delete(client_id)
      socket.close
    end
  end

  def process_command(command, client_id)
    case command
    when Protocol::SendMessage
      handle_send_message(command, client_id)
    when Protocol::Subscribe
      handle_subscribe(command, client_id)
    # ... etc
    end
  end
end
```

### 5. TUI as IPC Client

The TUI connects to the daemon instead of owning the runtime.

```ruby
class TUIClient
  def initialize(env_name:)
    @env_name = env_name
    @socket = nil
    @subscriptions = {}
    @event_callbacks = []
  end

  def connect
    socket_path = IPCServer::SOCKET_PATH_TEMPLATE % { env_name: @env_name }

    # Auto-start daemon if not running
    unless File.exist?(socket_path)
      start_daemon
      wait_for_socket(socket_path)
    end

    @socket = UNIXSocket.new(socket_path)
    start_event_listener
  end

  def send_message(po_name, message, session_id: nil)
    send_command(Protocol::SendMessage.new(po_name, message, session_id))
  end

  def subscribe_all(&callback)
    @event_callbacks << callback
    send_command(Protocol::Subscribe.new([]))
  end

  private

  def start_event_listener
    @event_thread = Thread.new do
      loop do
        msg = read_message
        case msg
        when Protocol::EventNotification
          # Push to Bubbletea update loop
          Bubbletea.send_message(msg.event)
        else
          # Response to a command - handled by request/response mechanism
        end
      end
    end
  end

  def start_daemon
    pid = spawn("prompt_objects", "daemon", "start", "--env", @env_name,
                [:out, :err] => "/dev/null")
    Process.detach(pid)
  end
end
```

### 6. PO-Spawned Interfaces

POs can create their own interfaces - the Smalltalk magic.

```ruby
# Primitive available to POs
class SpawnHttpServer < Primitive
  description "Spawn an HTTP server that routes requests to this PO"

  def call(port:, routes: nil)
    po = @context.current_po
    routes ||= default_routes(po)

    connector_id = @runtime.spawn_connector(
      :http,
      port: port,
      owner_po: po.name,
      routes: routes
    )

    "HTTP server started on port #{port} (connector: #{connector_id})"
  end

  private

  def default_routes(po)
    {
      "GET /" => { action: :info },
      "POST /message" => { action: :receive_message },
      "GET /history" => { action: :get_history }
    }
  end
end
```

Example PO that serves a dashboard:

```markdown
---
name: dashboard
description: Serves a web dashboard for system status
capabilities:
  - spawn_http_server
  - query_sessions
  - list_prompt_objects
---

# Dashboard

I serve a web dashboard. When initialized, I spawn an HTTP server.

## Initialization

On startup, spawn HTTP server on port 8080 with these routes:
- GET / - Render dashboard HTML
- GET /api/status - Return system status JSON
- GET /api/sessions - Return recent sessions

## Request Handling

When I receive a request to /, render an HTML page showing:
- All active POs and their states
- Recent sessions across all POs
- Pending human requests

When I receive a request to /api/status, return JSON with:
- PO states
- Session counts
- Uptime
```

---

## Deployment Scenarios

### Local Development

```bash
# Start TUI (daemon auto-starts)
prompt_objects tui --env dev

# Claude Desktop connects via MCP (same daemon)
# Both see same state, reactive updates
```

### Server Deployment

```bash
# On server: Start daemon with HTTP API
prompt_objects daemon start --env prod --http 8080 --mcp

# Remote TUI via SSH
ssh server "prompt_objects tui --env prod"

# Or API access
curl https://server:8080/api/pos/assistant/message -d '{"message": "hello"}'
```

### PO-Hosted Web App

```bash
# Daemon starts, dashboard PO spawns HTTP on port 3000
prompt_objects daemon start --env webapp

# Users interact via browser at localhost:3000
# dashboard PO handles all requests
```

### Multi-Interface Demo

```bash
# Terminal 1: TUI
prompt_objects tui --env demo

# Terminal 2: Watch the socket
# (daemon already running from TUI)

# Claude Desktop: Connect via MCP
# All three interfaces see same state
# Changes in one appear instantly in others
```

---

## Phase 1: Event Stream Foundation

Add event stream to runtime. Emit events from all state changes.

### Files to Create/Modify

```
lib/prompt_objects/
├── events.rb           # Event definitions
├── event_stream.rb     # Pub/sub implementation
└── runtime.rb          # Wire up event emission
```

### Implementation

```ruby
# lib/prompt_objects/events.rb
module PromptObjects
  module Events
    SessionCreated = Data.define(:session_id, :po_name, :source)
    SessionDeleted = Data.define(:session_id)
    MessageAdded = Data.define(:session_id, :message_id, :role, :content, :source)
    POStateChanged = Data.define(:po_name, :old_state, :new_state)
    HumanRequestQueued = Data.define(:request_id, :from_po, :question)
    HumanRequestResponded = Data.define(:request_id, :response)
    BusEntry = Data.define(:from, :to, :message)
  end
end
```

```ruby
# lib/prompt_objects/event_stream.rb
module PromptObjects
  class EventStream
    def initialize
      @subscribers = Hash.new { |h, k| h[k] = [] }
      @all_subscribers = []
      @mutex = Mutex.new
    end

    def subscribe(*event_types, &block)
      @mutex.synchronize do
        if event_types.empty?
          @all_subscribers << block
        else
          event_types.each { |t| @subscribers[t] << block }
        end
      end
      SubscriptionHandle.new(self, event_types, block)
    end

    def unsubscribe(handle)
      @mutex.synchronize do
        if handle.event_types.empty?
          @all_subscribers.delete(handle.block)
        else
          handle.event_types.each { |t| @subscribers[t].delete(handle.block) }
        end
      end
    end

    def publish(event)
      listeners = @mutex.synchronize do
        @subscribers[event.class] + @all_subscribers
      end
      listeners.each { |sub| sub.call(event) }
    end

    SubscriptionHandle = Struct.new(:stream, :event_types, :block) do
      def cancel
        stream.unsubscribe(self)
      end
    end
  end
end
```

```ruby
# In Runtime#initialize
@event_stream = EventStream.new

# In Session::Store, emit events
def add_message(session_id:, role:, content:, **opts)
  # ... existing code ...
  msg_id = @db.last_insert_row_id

  @event_stream&.publish(Events::MessageAdded.new(
    session_id: session_id,
    message_id: msg_id,
    role: role,
    content: content,
    source: opts[:source]
  ))

  msg_id
end
```

### TUI Integration (Prep)

Wire TUI to use event stream internally (before extracting to client):

```ruby
# In App#init_main
@env.event_stream.subscribe do |event|
  case event
  when Events::MessageAdded
    Bubbletea.send_message(Messages::SessionsChanged.new(...))
  when Events::POStateChanged
    Bubbletea.send_message(Messages::POStateChanged.new(...))
  end
end
```

### Tests

```ruby
class EventStreamTest < Minitest::Test
  def test_subscribe_all_events
    stream = PromptObjects::EventStream.new
    received = []

    stream.subscribe { |e| received << e }
    stream.publish(Events::SessionCreated.new("123", "test", "tui"))
    stream.publish(Events::POStateChanged.new("test", :idle, :working))

    assert_equal 2, received.length
  end

  def test_subscribe_specific_event
    stream = PromptObjects::EventStream.new
    received = []

    stream.subscribe(Events::SessionCreated) { |e| received << e }
    stream.publish(Events::SessionCreated.new("123", "test", "tui"))
    stream.publish(Events::POStateChanged.new("test", :idle, :working))

    assert_equal 1, received.length
    assert_kind_of Events::SessionCreated, received.first
  end

  def test_unsubscribe
    stream = PromptObjects::EventStream.new
    received = []

    handle = stream.subscribe { |e| received << e }
    stream.publish(Events::SessionCreated.new("123", "test", "tui"))
    handle.cancel
    stream.publish(Events::SessionCreated.new("456", "test", "tui"))

    assert_equal 1, received.length
  end
end
```

---

## Phase 2: IPC Protocol & Daemon

Create the daemon process and IPC communication layer.

### Files to Create

```
lib/prompt_objects/
├── daemon/
│   ├── server.rb         # Main daemon process
│   ├── ipc_server.rb     # Unix socket server
│   ├── client.rb         # IPC client base class
│   └── protocol.rb       # Command/response definitions
└── protocol/
    ├── commands.rb       # All command types
    ├── responses.rb      # All response types
    └── serializer.rb     # JSON/MessagePack serialization
```

### Daemon Server

```ruby
# lib/prompt_objects/daemon/server.rb
module PromptObjects
  module Daemon
    class Server
      def initialize(env_path:, options: {})
        @env_path = env_path
        @options = options
        @runtime = nil
        @ipc_server = nil
        @connectors = []
      end

      def start
        setup_runtime
        setup_ipc
        setup_connectors
        write_pid_file

        trap_signals
        run_loop
      ensure
        cleanup
      end

      private

      def setup_runtime
        @runtime = Runtime.new(env_path: @env_path)
        load_all_objects
      end

      def setup_ipc
        @ipc_server = IPCServer.new(
          runtime: @runtime,
          event_stream: @runtime.event_stream,
          env_name: @runtime.name
        )
        Thread.new { @ipc_server.start }
      end

      def setup_connectors
        if @options[:mcp]
          @connectors << Connectors::MCP.new(runtime: @runtime)
        end
        if @options[:http]
          @connectors << Connectors::HTTP.new(
            runtime: @runtime,
            port: @options[:http_port] || 8080
          )
        end
        @connectors.each(&:start)
      end

      def run_loop
        loop { sleep 1 }
      end

      def trap_signals
        %w[INT TERM].each do |sig|
          trap(sig) { @running = false }
        end
      end
    end
  end
end
```

### Protocol Serialization

```ruby
# lib/prompt_objects/protocol/serializer.rb
module PromptObjects
  module Protocol
    class Serializer
      def self.encode(message)
        data = {
          type: message.class.name.split("::").last,
          payload: message.to_h
        }
        json = JSON.generate(data)
        [json.bytesize].pack("N") + json  # Length-prefixed
      end

      def self.decode(io)
        length_bytes = io.read(4)
        return nil unless length_bytes

        length = length_bytes.unpack1("N")
        json = io.read(length)
        data = JSON.parse(json, symbolize_names: true)

        type_class = const_get(data[:type])
        type_class.new(**data[:payload])
      end
    end
  end
end
```

### CLI Commands

```ruby
# In exe/prompt_objects
class CLI
  def run_daemon(args)
    options = parse_daemon_options(args)

    case options[:action]
    when :start
      daemon = Daemon::Server.new(
        env_path: options[:env_path],
        options: options
      )
      daemon.start
    when :stop
      Daemon::Controller.stop(options[:env_name])
    when :status
      Daemon::Controller.status(options[:env_name])
    end
  end
end
```

### Tests

```ruby
class IPCProtocolTest < Minitest::Test
  def test_roundtrip_serialization
    command = Protocol::SendMessage.new("test_po", "hello", nil)

    io = StringIO.new
    io.write(Protocol::Serializer.encode(command))
    io.rewind

    decoded = Protocol::Serializer.decode(io)

    assert_equal command.po_name, decoded.po_name
    assert_equal command.message, decoded.message
  end
end

class DaemonIntegrationTest < Minitest::Test
  def test_client_can_list_pos
    # Start daemon in subprocess
    # Connect client
    # Send ListPOs command
    # Verify response
  end
end
```

---

## Phase 3: TUI as IPC Client

Extract TUI from owning runtime to connecting as a client.

### Changes to App

```ruby
# lib/prompt_objects/ui/app.rb
class App
  def initialize(env_name: nil, env_path: nil, **opts)
    @env_name = env_name
    @env_path = env_path
    @client = nil  # IPC client (new)
    @env = nil     # Direct runtime (legacy/fallback)
    # ...
  end

  def init
    if use_daemon_mode?
      init_daemon_client
    else
      init_direct_runtime  # Existing code
    end
  end

  private

  def use_daemon_mode?
    # Use daemon if env_name provided (vs direct path in dev)
    @env_name && !@dev_mode
  end

  def init_daemon_client
    @client = Daemon::TUIClient.new(env_name: @env_name)
    @client.connect

    # Subscribe to all events
    @client.subscribe_all do |event|
      handle_daemon_event(event)
    end

    # Load initial state
    load_initial_state
  end

  def handle_daemon_event(event)
    case event
    when Events::MessageAdded
      if event.session_id == current_session_id
        @conversation.refresh
      end
    when Events::POStateChanged
      @capability_bar.update_state(event.po_name, event.new_state)
    when Events::HumanRequestQueued
      @notification_panel.refresh
    end
  end

  def handle_input_submit(text)
    if @client
      # Send via daemon
      @client.send_message(@active_po_name, text, session_id: @session_id)
    else
      # Direct runtime (existing code)
      @active_po.receive(text, context: @context)
    end
  end
end
```

### TUI Client

```ruby
# lib/prompt_objects/daemon/tui_client.rb
module PromptObjects
  module Daemon
    class TUIClient < Client
      def initialize(env_name:)
        super
        @pending_requests = {}
        @request_id = 0
      end

      def send_message(po_name, message, session_id: nil)
        request_id = next_request_id
        send_command(Protocol::SendMessage.new(po_name, message, session_id), request_id)
        # Response comes via event stream, not return value
      end

      def list_pos
        send_command_sync(Protocol::ListPOs.new)
      end

      def subscribe_all(&callback)
        @event_callback = callback
        send_command(Protocol::Subscribe.new([]))
      end

      private

      def handle_message(msg)
        case msg
        when Protocol::EventNotification
          @event_callback&.call(msg.event)
          # Also push to Bubbletea
          Bubbletea.send_message(msg.event)
        when Protocol::MessageResponse
          # Response to SendMessage - trigger UI update
          Bubbletea.send_message(Messages::POResponse.new(
            po_name: msg.po_name,
            text: msg.response
          ))
        end
      end
    end
  end
end
```

### Graceful Reconnection

```ruby
def connect
  @reconnect_attempts = 0

  loop do
    begin
      do_connect
      @reconnect_attempts = 0
      break
    rescue Errno::ECONNREFUSED, Errno::ENOENT
      if @reconnect_attempts < 3
        # Daemon not running, try to start it
        start_daemon
        sleep 0.5
        @reconnect_attempts += 1
      else
        raise "Could not connect to daemon after #{@reconnect_attempts} attempts"
      end
    end
  end
end

def handle_disconnect
  # Show "Reconnecting..." in status bar
  Bubbletea.send_message(Messages::ConnectionLost.new)

  Thread.new do
    sleep 1
    connect
    Bubbletea.send_message(Messages::ConnectionRestored.new)
  end
end
```

---

## Phase 4: HTTP Connector

REST API and optional web UI.

### HTTP Connector

```ruby
# lib/prompt_objects/connectors/http.rb
require "webrick"
require "json"

module PromptObjects
  module Connectors
    class HTTP < Base
      def initialize(runtime:, port: 8080, config: {})
        super(runtime: runtime, config: config)
        @port = port
      end

      def source_name
        "api"
      end

      def start
        @server = WEBrick::HTTPServer.new(Port: @port, Logger: WEBrick::Log.new("/dev/null"))

        mount_api_routes
        mount_websocket if @config[:websocket]
        mount_static if @config[:static_dir]

        Thread.new { @server.start }
      end

      def stop
        @server&.shutdown
      end

      private

      def mount_api_routes
        @server.mount_proc "/api/pos" do |req, res|
          handle_list_pos(req, res)
        end

        @server.mount_proc "/api/pos/" do |req, res|
          # /api/pos/:name/message, /api/pos/:name, etc.
          route_po_request(req, res)
        end

        @server.mount_proc "/api/sessions" do |req, res|
          handle_sessions(req, res)
        end
      end

      def handle_list_pos(req, res)
        pos = @runtime.registry.prompt_objects.map do |po|
          { name: po.name, description: po.description, state: po.state }
        end

        res.content_type = "application/json"
        res.body = JSON.generate({ prompt_objects: pos })
      end

      def route_po_request(req, res)
        path_parts = req.path.split("/").reject(&:empty?)
        # ["api", "pos", "name", "message"]

        po_name = path_parts[2]
        action = path_parts[3]

        case [req.request_method, action]
        when ["POST", "message"]
          handle_send_message(po_name, req, res)
        when ["GET", nil]
          handle_get_po(po_name, req, res)
        when ["GET", "history"]
          handle_get_history(po_name, req, res)
        end
      end

      def handle_send_message(po_name, req, res)
        body = JSON.parse(req.body)
        session_id = body["session_id"]
        message = body["message"]

        po = @runtime.registry.get(po_name)
        unless po.is_a?(PromptObject)
          res.status = 404
          res.body = JSON.generate({ error: "PO not found" })
          return
        end

        # Setup session
        session_id ||= setup_session(po)

        # Send message
        response = po.receive(message, context: @runtime.context)

        res.content_type = "application/json"
        res.body = JSON.generate({
          po_name: po_name,
          response: response,
          session_id: session_id
        })
      end
    end
  end
end
```

### WebSocket for Real-time Events

```ruby
# Using faye-websocket or similar
def mount_websocket
  @server.mount_proc "/ws" do |req, res|
    if Faye::WebSocket.websocket?(req)
      ws = Faye::WebSocket.new(req)

      # Subscribe to events and forward to WebSocket
      subscription = @runtime.event_stream.subscribe do |event|
        ws.send(JSON.generate({
          type: "event",
          event_type: event.class.name,
          payload: event.to_h
        }))
      end

      ws.on :close do
        subscription.cancel
      end

      ws.rack_response
    end
  end
end
```

---

## Phase 5: PO-Spawned Interfaces

Allow POs to create their own HTTP endpoints.

### Primitive

```ruby
# lib/prompt_objects/primitives/spawn_http_server.rb
module PromptObjects
  module Primitives
    class SpawnHttpServer < Primitive
      def name
        "spawn_http_server"
      end

      def description
        "Spawn an HTTP server that routes requests to this PO"
      end

      def parameters
        {
          port: { type: "integer", description: "Port to listen on", required: true },
          routes: { type: "object", description: "Route definitions (optional)" }
        }
      end

      def call(port:, routes: nil)
        po = @context.current_po

        # Validate port is available
        raise "Port #{port} already in use" if port_in_use?(port)

        # Create HTTP connector owned by this PO
        connector = POHttpConnector.new(
          runtime: @runtime,
          port: port,
          owner_po: po,
          routes: routes || default_routes
        )

        connector.start
        @runtime.register_po_connector(po.name, connector)

        "HTTP server started on port #{port}. Routes: #{connector.route_summary}"
      end

      private

      def default_routes
        {
          "GET /" => :handle_root,
          "POST /message" => :handle_message,
          "GET /history" => :handle_history
        }
      end
    end
  end
end
```

### PO HTTP Connector

```ruby
class POHttpConnector
  def initialize(runtime:, port:, owner_po:, routes:)
    @runtime = runtime
    @port = port
    @owner_po = owner_po
    @routes = routes
  end

  def start
    @server = WEBrick::HTTPServer.new(Port: @port)

    @routes.each do |pattern, action|
      method, path = pattern.split(" ", 2)
      @server.mount_proc path do |req, res|
        next unless req.request_method == method
        handle_request(action, req, res)
      end
    end

    Thread.new { @server.start }
  end

  def handle_request(action, req, res)
    # Route to the PO
    message = build_request_message(action, req)
    response = @owner_po.receive(message, context: @runtime.context)

    # PO response is the HTTP response
    res.content_type = infer_content_type(response)
    res.body = response
  end

  def build_request_message(action, req)
    <<~MSG
      HTTP Request received:
      Action: #{action}
      Method: #{req.request_method}
      Path: #{req.path}
      Query: #{req.query}
      Body: #{req.body}

      Please handle this request and return the appropriate response.
    MSG
  end
end
```

---

## Testing Strategy

### Unit Tests

- Event stream subscription/unsubscription
- Protocol serialization roundtrip
- Command handling in isolation

### Integration Tests

- Daemon startup/shutdown
- Client connect/reconnect
- Multi-client coordination
- Event propagation across clients

### End-to-End Tests

- TUI + MCP simultaneous access
- HTTP API full workflow
- PO-spawned server handling requests

---

## Migration Path

### Phase 1 (Non-breaking)
- Add event stream to runtime
- Emit events from existing code
- TUI subscribes internally

### Phase 2 (Parallel)
- Add daemon server
- Add IPC client
- TUI can run in either mode (flag)

### Phase 3 (Default)
- TUI defaults to daemon mode
- Direct mode for dev/debugging
- Deprecate direct mode eventually

---

## Configuration

### Daemon Config

```yaml
# ~/.prompt_objects/daemon.yml
auto_start: true        # Start daemon when client connects
idle_timeout: 3600      # Shut down after 1 hour of no connections (0 = never)
log_level: info
```

### Environment Manifest Additions

```yaml
# manifest.yml
connectors:
  http:
    enabled: false
    port: 8080
    auth:
      type: api_key
  websocket:
    enabled: false
  mcp:
    enabled: true
```

---

## Open Questions

1. **Daemon lifecycle**: Auto-start on first connection? Auto-stop after idle?
2. **Authentication**: How to secure IPC socket? HTTP API keys?
3. **Multi-user**: Can multiple users connect to same daemon?
4. **Resource limits**: Max connections? Rate limiting?
5. **Crash recovery**: How to handle daemon crash mid-conversation?

---

## Success Criteria

- [ ] TUI and Claude Desktop see same state in real-time
- [ ] Changes from one interface appear in others < 100ms
- [ ] Daemon survives interface disconnects
- [ ] PO can spawn working HTTP server
- [ ] System deployable to remote server with TUI access via SSH
