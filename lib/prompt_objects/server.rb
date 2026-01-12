# frozen_string_literal: true

require_relative "server/api/routes"
require_relative "server/websocket_handler"
require_relative "server/file_watcher"
require_relative "server/app"

module PromptObjects
  module Server
    # Start the server for a given runtime.
    # @param runtime [Runtime] The runtime/environment to serve
    # @param host [String] Host to bind to
    # @param port [Integer] Port to listen on
    # @param env_path [String] Path to the environment directory
    def self.start(runtime:, host: "localhost", port: 3000, env_path: nil)
      require "async"
      require "async/http/endpoint"
      require "falcon"

      app = App.new(runtime)
      url = "http://#{host}:#{port}"

      puts "PromptObjects Server"
      puts "===================="
      puts "Environment: #{runtime.name}"
      puts "URL: #{url}"
      puts ""
      puts "Prompt Objects:"
      runtime.registry.prompt_objects.each do |po|
        puts "  - #{po.name}: #{po.description}"
      end
      puts ""
      puts "Press Ctrl+C to stop"
      puts ""

      # Register callback for immediate PO registration notifications
      # This fires when create_capability creates a new PO programmatically
      runtime.on_po_registered = ->(po) {
        app.broadcast(
          type: "po_added",
          payload: {
            name: po.name,
            state: po_state_hash(po)
          }
        )
        puts "Broadcast: PO registered - #{po.name}"
      }

      # Start file watcher for live updates (manual file edits)
      file_watcher = nil
      if env_path
        file_watcher = FileWatcher.new(runtime: runtime, env_path: env_path)
        file_watcher.subscribe do |event, data|
          handle_file_event(app, event, data)
        end
        file_watcher.start
      end

      Async do |task|
        endpoint = Async::HTTP::Endpoint.parse(url)

        server = Falcon::Server.new(
          Falcon::Server.middleware(app),
          endpoint
        )

        task.async do
          server.run
        end
      ensure
        file_watcher&.stop
      end
    end

    # Handle file change events and broadcast to connected clients.
    def self.handle_file_event(app, event, data)
      case event
      when :po_added
        po = data
        app.broadcast(
          type: "po_added",
          payload: {
            name: po.name,
            state: po_state_hash(po)
          }
        )
        puts "Broadcast: PO added - #{po.name}"

      when :po_modified
        po = data
        app.broadcast(
          type: "po_modified",
          payload: {
            name: po.name,
            state: po_state_hash(po)
          }
        )
        puts "Broadcast: PO modified - #{po.name}"

      when :po_removed
        app.broadcast(
          type: "po_removed",
          payload: { name: data[:name] }
        )
        puts "Broadcast: PO removed - #{data[:name]}"
      end
    end

    # Helper to convert PO to state hash for broadcasting.
    def self.po_state_hash(po)
      {
        status: po.instance_variable_get(:@state) || "idle",
        description: po.description,
        capabilities: po.config["capabilities"] || [],
        current_session: nil, # New POs don't have sessions yet
        sessions: po.list_sessions.map do |s|
          {
            id: s[:id],
            name: s[:name],
            message_count: s[:message_count] || 0,
            updated_at: s[:updated_at]&.iso8601
          }
        end,
        prompt: po.body,
        config: po.config
      }
    end
  end
end
