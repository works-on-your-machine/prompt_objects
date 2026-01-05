# frozen_string_literal: true

module PromptObjects
  module Env
    # Exports an environment as a git bundle (.poenv file).
    # The bundle contains all commits, objects, primitives, and manifest.
    # Sessions are NOT included (private data).
    class Exporter
      # @param env_path [String] Path to the environment directory
      def initialize(env_path)
        @env_path = env_path
        @name = File.basename(env_path)
      end

      # Export the environment to a git bundle.
      # @param output_path [String] Path for the output .poenv file
      # @param commit_message [String, nil] Message for any uncommitted changes
      # @return [Hash] Export result with :success, :path, :stats
      def export(output_path, commit_message: nil)
        validate_environment!

        # Ensure we have a clean state
        commit_changes(commit_message) if Git.dirty?(@env_path)

        # Create the bundle
        output_path = normalize_output_path(output_path)
        success = Git.bundle(@env_path, output_path)

        unless success
          return { success: false, error: "Failed to create git bundle" }
        end

        {
          success: true,
          path: output_path,
          stats: gather_stats
        }
      end

      private

      def validate_environment!
        unless Dir.exist?(@env_path)
          raise Error, "Environment not found: #{@env_path}"
        end

        unless Git.repo?(@env_path)
          raise Error, "Environment is not a git repository: #{@env_path}"
        end

        # Must have at least one commit
        if Git.commit_count(@env_path) == 0
          raise Error, "Environment has no commits. Make at least one change first."
        end
      end

      def commit_changes(message)
        msg = message || "Export preparation"
        Git.commit(@env_path, msg)
      end

      def normalize_output_path(path)
        # Add .poenv extension if not present
        path = "#{path}.poenv" unless path.end_with?(".poenv")

        # Expand to absolute path
        File.expand_path(path)
      end

      def gather_stats
        objects_dir = File.join(@env_path, "objects")
        primitives_dir = File.join(@env_path, "primitives")

        {
          name: @name,
          commits: Git.commit_count(@env_path),
          objects: Dir.exist?(objects_dir) ? Dir.glob(File.join(objects_dir, "*.md")).count : 0,
          primitives: Dir.exist?(primitives_dir) ? Dir.glob(File.join(primitives_dir, "*.rb")).count : 0
        }
      end
    end
  end
end
