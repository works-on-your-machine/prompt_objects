# frozen_string_literal: true

module PromptObjects
  module Primitives
    # Primitive capability to write content to a file.
    class WriteFile < Primitive
      def name
        "write_file"
      end

      def description
        "Write content to a file (creates or overwrites)"
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "The path to the file to write"
            },
            content: {
              type: "string",
              description: "The content to write to the file"
            }
          },
          required: ["path", "content"]
        }
      end

      def receive(message, context:)
        path = extract_param(message, :path)
        content = extract_param(message, :content)

        if path.nil? || path.empty?
          return "Error: path is required"
        end

        if content.nil?
          return "Error: content is required"
        end

        safe_path = File.expand_path(path)

        # Create parent directories if they don't exist
        dir = File.dirname(safe_path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        File.write(safe_path, content, encoding: "UTF-8")

        "Successfully wrote #{content.length} bytes to #{path}"
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue StandardError => e
        "Error writing file: #{e.message}"
      end

      private

      def extract_param(message, key)
        case message
        when Hash
          message[key] || message[key.to_s]
        else
          nil
        end
      end
    end
  end
end

require "fileutils"
