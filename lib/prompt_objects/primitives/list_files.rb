# frozen_string_literal: true

module PromptObjects
  module Primitives
    # Primitive capability to list files in a directory.
    class ListFiles < Primitive
      def name
        "list_files"
      end

      def description
        "List files and directories in a given path"
      end

      def parameters
        {
          type: "object",
          properties: {
            path: {
              type: "string",
              description: "The directory path to list (defaults to current directory)"
            }
          }
        }
      end

      def receive(message, context:)
        path = extract_path(message)
        path = "." if path.nil? || path.empty?

        safe_path = File.expand_path(path)

        unless File.exist?(safe_path)
          return "Error: Path not found: #{path}"
        end

        unless File.directory?(safe_path)
          return "Error: Not a directory: #{path}"
        end

        entries = Dir.entries(safe_path)
          .reject { |e| e.start_with?(".") } # Hide hidden files
          .sort
          .map { |entry| format_entry(safe_path, entry) }

        if entries.empty?
          "Directory is empty: #{path}"
        else
          entries.join("\n")
        end
      rescue Errno::EACCES
        "Error: Permission denied: #{path}"
      rescue StandardError => e
        "Error listing directory: #{e.message}"
      end

      private

      def extract_path(message)
        case message
        when Hash
          message[:path] || message["path"]
        when String
          message
        when NilClass
          "."
        else
          message.to_s
        end
      end

      def format_entry(base_path, entry)
        full_path = File.join(base_path, entry)

        if File.directory?(full_path)
          "#{entry}/"
        else
          size = File.size(full_path)
          "#{entry} (#{human_size(size)})"
        end
      end

      def human_size(bytes)
        return "0 B" if bytes == 0

        units = ["B", "KB", "MB", "GB"]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = units.length - 1 if exp >= units.length

        "%.1f %s" % [bytes.to_f / (1024 ** exp), units[exp]]
      end
    end
  end
end
