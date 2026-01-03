# frozen_string_literal: true

module PromptObjects
  module Primitives
    # Primitive capability to read file contents.
    class ReadFile < Primitive
      def name
        "read_file"
      end

      def description
        "Read the contents of a text file"
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "The path to the file to read"
            }
          },
          required: ["path"]
        }
      end

      def receive(message, context:)
        path = extract_path(message)
        safe_path = validate_path(path)

        unless File.exist?(safe_path)
          return "Error: File not found: #{path}"
        end

        unless File.file?(safe_path)
          return "Error: Not a file: #{path}"
        end

        content = File.read(safe_path, encoding: "UTF-8")

        # Truncate very large files
        if content.length > 50_000
          content = content[0, 50_000] + "\n\n... [truncated, file is #{content.length} bytes]"
        end

        content
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue StandardError => e
        "Error reading file: #{e.message}"
      end

      private

      def extract_path(message)
        case message
        when Hash
          message[:path] || message["path"]
        when String
          message
        else
          message.to_s
        end
      end

      def validate_path(path)
        # Expand and normalize the path
        expanded = File.expand_path(path)

        # Basic safety: don't allow reading outside current directory tree
        # In a real implementation, you'd want more robust sandboxing
        cwd = File.expand_path(".")

        # Allow absolute paths but warn if outside cwd
        # For now, we'll be permissive but could restrict this
        expanded
      end
    end
  end
end
