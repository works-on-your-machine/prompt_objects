# frozen_string_literal: true

require "fileutils"

module PromptObjects
  module Primitives
    # Primitive capability to write content to a file.
    class WriteFile < Base
      description "Write content to a file (creates or overwrites)"
      param :path, desc: "The path to the file to write"
      param :content, desc: "The content to write to the file"

      def execute(path:, content:)
        if path.nil? || path.empty?
          return { error: "path is required" }
        end

        if content.nil?
          return { error: "content is required" }
        end

        safe_path = File.expand_path(path)

        # Create parent directories if they don't exist
        dir = File.dirname(safe_path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        File.write(safe_path, content, encoding: "UTF-8")

        log("Wrote #{content.length} bytes to #{path}")
        "Successfully wrote #{content.length} bytes to #{path}"
      rescue Errno::EACCES
        { error: "Permission denied: #{path}" }
      rescue StandardError => e
        { error: "Error writing file: #{e.message}" }
      end
    end
  end
end
