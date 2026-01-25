# frozen_string_literal: true

require "net/http"
require "uri"

module PromptObjects
  module Primitives
    # Primitive capability to fetch content from a URL.
    class HttpGet < Base
      description "Fetch content from a URL via HTTP GET request"
      param :url, desc: "The URL to fetch"

      def execute(url:)
        return { error: "URL is required" } if url.nil? || url.empty?

        uri = URI.parse(url)

        unless %w[http https].include?(uri.scheme)
          return { error: "Only http and https URLs are supported" }
        end

        response = Net::HTTP.get_response(uri)

        case response
        when Net::HTTPSuccess
          content = response.body.to_s

          # Truncate very large responses
          if content.length > 50_000
            content = content[0, 50_000] + "\n\n... [truncated, response is #{content.length} bytes]"
          end

          log("Fetched #{url} (#{content.length} bytes)")
          content
        when Net::HTTPRedirection
          "Redirected to: #{response['location']}"
        else
          { error: "HTTP Error: #{response.code} #{response.message}" }
        end
      rescue URI::InvalidURIError
        { error: "Invalid URL format" }
      rescue SocketError => e
        { error: "Could not connect - #{e.message}" }
      rescue Timeout::Error
        { error: "Request timed out" }
      rescue StandardError => e
        { error: "Error fetching URL: #{e.message}" }
      end
    end
  end
end
