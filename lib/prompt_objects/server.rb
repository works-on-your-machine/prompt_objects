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
            state: po_state_hash(po, runtime: runtime)
          }
        )
        puts "Broadcast: PO registered - #{po.name}"
      }

      # Register callback for PO modification notifications
      # This fires when capabilities are added/removed programmatically
      runtime.on_po_modified = ->(po) {
        app.broadcast(
          type: "po_modified",
          payload: {
            name: po.name,
            state: po_state_hash(po, runtime: runtime)
          }
        )
        puts "Broadcast: PO modified (programmatic) - #{po.name}"
      }

      # Start file watcher for live updates (manual file edits)
      file_watcher = nil
      if env_path
        file_watcher = FileWatcher.new(runtime: runtime, env_path: env_path)
        file_watcher.subscribe do |event, data|
          handle_file_event(app, event, data, runtime: runtime)
        end
        file_watcher.start
      end

      # Write .server file for CLI discovery
      server_file = write_server_file(env_path, host: host, port: port) if env_path

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
        remove_server_file(server_file) if server_file
      end
    end

    # Write a .server file so CLI clients can discover the running server.
    # @param env_path [String] Path to the environment directory
    # @param host [String] Server host
    # @param port [Integer] Server port
    # @return [String] Path to the .server file
    def self.write_server_file(env_path, host:, port:)
      return nil unless env_path

      server_file = File.join(env_path, ".server")
      data = {
        pid: Process.pid,
        host: host,
        port: port,
        started_at: Time.now.iso8601
      }
      File.write(server_file, JSON.generate(data))
      server_file
    end

    # Remove the .server file on shutdown.
    # @param path [String] Path to the .server file
    def self.remove_server_file(path)
      File.delete(path) if path && File.exist?(path)
    rescue StandardError
      # Ignore cleanup errors
    end

    # Read a .server file to discover a running server.
    # Returns nil if no server is running or the file is stale.
    # @param env_path [String] Path to the environment directory
    # @return [Hash, nil] Server info with :host, :port, :pid
    def self.read_server_file(env_path)
      server_file = File.join(env_path, ".server")
      return nil unless File.exist?(server_file)

      data = JSON.parse(File.read(server_file), symbolize_names: true)

      # Check if the process is still running
      begin
        Process.kill(0, data[:pid])
        data
      rescue Errno::ESRCH
        # Process is dead, clean up stale file
        File.delete(server_file)
        nil
      end
    rescue StandardError
      nil
    end

    # Handle file change events and broadcast to connected clients.
    def self.handle_file_event(app, event, data, runtime: nil)
      case event
      when :po_added
        po = data
        app.broadcast(
          type: "po_added",
          payload: {
            name: po.name,
            state: po_state_hash(po, runtime: runtime)
          }
        )
        puts "Broadcast: PO added - #{po.name}"

      when :po_modified
        po = data
        app.broadcast(
          type: "po_modified",
          payload: {
            name: po.name,
            state: po_state_hash(po, runtime: runtime)
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
    # When runtime is provided, includes full capability info (name, description, parameters)
    # and universal capabilities — matching the WebSocket handler's po_state_hash format.
    def self.po_state_hash(po, runtime: nil)
      {
        status: po.instance_variable_get(:@state) || "idle",
        description: po.description,
        capabilities: declared_capabilities_info(po, runtime: runtime),
        universal_capabilities: universal_capabilities_info(runtime: runtime),
        current_session: current_session_hash(po),
        sessions: po.list_sessions.map do |s|
          {
            id: s[:id],
            name: s[:name],
            message_count: s[:message_count] || 0,
            updated_at: s[:updated_at]&.iso8601,
            # Thread fields
            parent_session_id: s[:parent_session_id],
            parent_po: s[:parent_po],
            thread_type: s[:thread_type] || "root"
          }
        end,
        prompt: po.body,
        config: po.config
      }
    end

    # Build full capability info objects for a PO's declared capabilities.
    def self.declared_capabilities_info(po, runtime: nil)
      declared = po.config["capabilities"] || []
      return declared unless runtime # Fallback to string names if no runtime

      declared.map do |name|
        cap = runtime.registry.get(name)
        {
          name: name,
          description: cap&.description || "Capability not found",
          parameters: cap&.parameters
        }
      end
    end

    # Build full capability info objects for universal capabilities.
    def self.universal_capabilities_info(runtime: nil)
      return [] unless runtime

      UNIVERSAL_CAPABILITIES.map do |name|
        cap = runtime.registry.get(name)
        {
          name: name,
          description: cap&.description || "Universal capability",
          parameters: cap&.parameters
        }
      end
    end

    # Helper to get current session data for a PO.
    def self.current_session_hash(po)
      return nil unless po.session_id

      {
        id: po.session_id,
        messages: po.history.map { |m| message_to_hash(m) }
      }
    end

    # Helper to convert a message to JSON-serializable hash.
    def self.message_to_hash(msg)
      case msg[:role]
      when :user
        { role: "user", content: msg[:content], from: msg[:from] }
      when :assistant
        hash = { role: "assistant", content: msg[:content] }
        if msg[:tool_calls]
          hash[:tool_calls] = msg[:tool_calls].map do |tc|
            tc_id = tc.respond_to?(:id) ? tc.id : (tc[:id] || tc["id"])
            tc_name = tc.respond_to?(:name) ? tc.name : (tc[:name] || tc["name"])
            tc_args = tc.respond_to?(:arguments) ? tc.arguments : (tc[:arguments] || tc["arguments"] || {})
            { id: tc_id, name: tc_name, arguments: tc_args }
          end
        end
        hash
      when :tool
        { role: "tool", results: msg[:results] }
      else
        { role: msg[:role].to_s, content: msg[:content] }
      end
    end
  end
end
