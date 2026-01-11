# frozen_string_literal: true

require_relative "server/api/routes"
require_relative "server/websocket_handler"
require_relative "server/app"

module PromptObjects
  module Server
    # Start the server for a given runtime.
    # @param runtime [Runtime] The runtime/environment to serve
    # @param host [String] Host to bind to
    # @param port [Integer] Port to listen on
    def self.start(runtime:, host: "localhost", port: 3000)
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

      Async do |task|
        endpoint = Async::HTTP::Endpoint.parse(url)

        server = Falcon::Server.new(
          Falcon::Server.middleware(app),
          endpoint
        )

        task.async do
          server.run
        end
      end
    end
  end
end
