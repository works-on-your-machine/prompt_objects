# frozen_string_literal: true

require "async/websocket/adapters/rack"
require "json"
require "rack"

module PromptObjects
  module Server
    # Main Rack application for the PromptObjects web server.
    # Routes requests to WebSocket handler, API, or static assets.
    class App
      STATIC_EXTENSIONS = %w[.html .js .css .png .svg .ico .woff .woff2 .map .json].freeze

      attr_reader :connections

      def initialize(runtime)
        @runtime = runtime
        @api = API::Routes.new(runtime)
        @public_path = File.expand_path("public", __dir__)
        @connections = []
        @connections_mutex = Mutex.new
      end

      def call(env)
        request_path = env["PATH_INFO"]

        if websocket_request?(env)
          handle_websocket(env)
        elsif request_path.start_with?("/api/")
          @api.call(env)
        elsif static_asset?(request_path)
          serve_static(request_path)
        else
          serve_index
        end
      end

      # Broadcast a message to all connected WebSocket clients.
      # @param message [Hash] Message to broadcast
      def broadcast(message)
        @connections_mutex.synchronize do
          @connections.each do |handler|
            handler.send_message(message)
          rescue StandardError => e
            puts "Broadcast error: #{e.message}" if ENV["DEBUG"]
          end
        end
      end

      # Register a connection handler.
      def register_connection(handler)
        @connections_mutex.synchronize do
          @connections << handler
        end
      end

      # Unregister a connection handler.
      def unregister_connection(handler)
        @connections_mutex.synchronize do
          @connections.delete(handler)
        end
      end

      private

      def websocket_request?(env)
        env["HTTP_UPGRADE"]&.downcase == "websocket"
      end

      def handle_websocket(env)
        Async::WebSocket::Adapters::Rack.open(env, protocols: ["json"]) do |connection|
          handler = WebSocketHandler.new(
            runtime: @runtime,
            connection: connection,
            app: self
          )

          register_connection(handler)
          begin
            handler.run
          ensure
            unregister_connection(handler)
          end
        end
      end

      def static_asset?(path)
        STATIC_EXTENSIONS.any? { |ext| path.end_with?(ext) }
      end

      def serve_static(path)
        # Security: prevent directory traversal
        safe_path = File.expand_path(File.join(@public_path, path))
        unless safe_path.start_with?(@public_path)
          return [403, { "content-type" => "text/plain" }, ["Forbidden"]]
        end

        if File.exist?(safe_path) && File.file?(safe_path)
          content_type = content_type_for(path)
          body = File.read(safe_path)
          [200, { "content-type" => content_type }, [body]]
        else
          [404, { "content-type" => "text/plain" }, ["Not found"]]
        end
      end

      def serve_index
        index_path = File.join(@public_path, "index.html")

        if File.exist?(index_path)
          body = File.read(index_path)
          [200, { "content-type" => "text/html" }, [body]]
        else
          # If no frontend is built yet, serve a placeholder
          [200, { "content-type" => "text/html" }, [placeholder_html]]
        end
      end

      def content_type_for(path)
        case File.extname(path)
        when ".html" then "text/html"
        when ".js" then "application/javascript"
        when ".css" then "text/css"
        when ".json" then "application/json"
        when ".svg" then "image/svg+xml"
        when ".png" then "image/png"
        when ".ico" then "image/x-icon"
        when ".woff" then "font/woff"
        when ".woff2" then "font/woff2"
        when ".map" then "application/json"
        else "application/octet-stream"
        end
      end

      def placeholder_html
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <title>PromptObjects</title>
            <style>
              body {
                font-family: system-ui, -apple-system, sans-serif;
                max-width: 600px;
                margin: 100px auto;
                padding: 20px;
                background: #1a1a2e;
                color: #eee;
              }
              h1 { color: #7c3aed; }
              code {
                background: #2d2d44;
                padding: 2px 6px;
                border-radius: 4px;
              }
              .status { color: #22c55e; }
            </style>
          </head>
          <body>
            <h1>PromptObjects</h1>
            <p class="status">Server is running</p>
            <p>Environment: <code>#{@runtime.name}</code></p>
            <p>Prompt Objects: <code>#{@runtime.registry.prompt_objects.size}</code></p>
            <p>WebSocket endpoint: <code>ws://localhost:PORT/</code></p>
            <hr>
            <p>The React frontend has not been built yet.</p>
            <p>For now, you can connect via WebSocket to interact with POs.</p>
          </body>
          </html>
        HTML
      end
    end
  end
end
