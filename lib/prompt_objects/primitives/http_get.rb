# frozen_string_literal: true

require "net/http"
require "uri"

module PromptObjects
  module Primitives
    # Primitive capability to fetch content from a URL.
    class HttpGet < Primitive
      def name
        "http_get"
      end

      def description
        "Fetch content from a URL via HTTP GET request"
      end

      def parameters
        {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "The URL to fetch"
            }
          },
          required: ["url"]
        }
      end

      def receive(message, context:)
        url = message[:url] || message["url"]

        return "Error: URL is required" if url.nil? || url.empty?

        begin
          uri = URI.parse(url)

          unless %w[http https].include?(uri.scheme)
            return "Error: Only http and https URLs are supported"
          end

          response = Net::HTTP.get_response(uri)

          case response
          when Net::HTTPSuccess
            content = response.body.to_s

            # Truncate very large responses
            if content.length > 50_000
              content = content[0, 50_000] + "\n\n... [truncated, response is #{content.length} bytes]"
            end

            content
          when Net::HTTPRedirection
            "Redirected to: #{response['location']}"
          else
            "HTTP Error: #{response.code} #{response.message}"
          end
        rescue URI::InvalidURIError
          "Error: Invalid URL format"
        rescue SocketError => e
          "Error: Could not connect - #{e.message}"
        rescue Timeout::Error
          "Error: Request timed out"
        rescue StandardError => e
          "Error fetching URL: #{e.message}"
        end
      end
    end
  end
end
