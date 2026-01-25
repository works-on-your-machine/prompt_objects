# frozen_string_literal: true

module PromptObjects
  module Primitives
    # Primitive capability to read file contents.
    class ReadFile < Base
      description "Read the contents of a text file"
      param :path, desc: "The path to the file to read"

      def execute(path:)
        safe_path = validate_path(path)

        unless File.exist?(safe_path)
          return { error: "File not found: #{path}" }
        end

        unless File.file?(safe_path)
          return { error: "Not a file: #{path}" }
        end

        content = File.read(safe_path, encoding: "UTF-8")

        # Truncate very large files
        if content.length > 50_000
          content = content[0, 50_000] + "\n\n... [truncated, file is #{content.length} bytes]"
        end

        log("Read #{path} (#{content.length} bytes)")
        content
      rescue Errno::EACCES
        { error: "Permission denied: #{path}" }
      rescue StandardError => e
        { error: "Error reading file: #{e.message}" }
      end

      private

      def validate_path(path)
        # Expand and normalize the path
        File.expand_path(path)
      end
    end
  end
end
