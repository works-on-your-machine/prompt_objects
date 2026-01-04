# frozen_string_literal: true

module PromptObjects
  module Env
    # Git operations for environments.
    # Each environment is a git repository for built-in versioning.
    module Git
      # Check if a directory is a git repository.
      # @param path [String]
      # @return [Boolean]
      def self.repo?(path)
        Dir.exist?(File.join(path, ".git"))
      end

      # Initialize a git repository.
      # @param path [String]
      def self.init(path)
        Dir.chdir(path) { system("git init --quiet") }
      end

      # Stage all changes.
      # @param path [String]
      def self.add_all(path)
        Dir.chdir(path) { system("git add -A") }
      end

      # Create a commit.
      # @param path [String]
      # @param message [String]
      # @return [Boolean] Success
      def self.commit(path, message)
        Dir.chdir(path) do
          system("git add -A")
          system("git", "commit", "--quiet", "-m", message)
        end
      end

      # Get list of uncommitted changes.
      # @param path [String]
      # @return [Array<String>] Changed file paths
      def self.uncommitted_changes(path)
        Dir.chdir(path) do
          status = `git status --porcelain 2>/dev/null`
          status.lines.map { |line| line[3..].strip }
        end
      end

      # Check if there are uncommitted changes.
      # @param path [String]
      # @return [Boolean]
      def self.dirty?(path)
        uncommitted_changes(path).any?
      end

      # Get current commit hash (short).
      # @param path [String]
      # @return [String, nil]
      def self.current_commit(path)
        Dir.chdir(path) do
          result = `git rev-parse --short HEAD 2>/dev/null`.strip
          result.empty? ? nil : result
        end
      end

      # Get commit count.
      # @param path [String]
      # @return [Integer]
      def self.commit_count(path)
        Dir.chdir(path) do
          `git rev-list --count HEAD 2>/dev/null`.strip.to_i
        end
      end

      # Get recent commits.
      # @param path [String]
      # @param limit [Integer]
      # @return [Array<Hash>] Array of {hash:, message:, date:}
      def self.recent_commits(path, limit: 10)
        Dir.chdir(path) do
          log = `git log --oneline --format="%h|%s|%ci" -n #{limit} 2>/dev/null`
          log.lines.map do |line|
            hash, message, date = line.strip.split("|", 3)
            { hash: hash, message: message, date: date }
          end
        end
      end

      # Create a git bundle for export.
      # @param path [String]
      # @param output [String] Output file path
      # @return [Boolean] Success
      def self.bundle(path, output)
        Dir.chdir(path) do
          system("git bundle create #{output} --all 2>/dev/null")
        end
      end

      # Clone from a git bundle.
      # @param bundle_path [String]
      # @param dest_path [String]
      # @return [Boolean] Success
      def self.clone_bundle(bundle_path, dest_path)
        system("git clone --quiet #{bundle_path} #{dest_path} 2>/dev/null")
      end

      # Auto-commit if there are changes (used for saving PO modifications).
      # @param path [String]
      # @param message [String]
      # @return [Boolean] True if committed, false if no changes
      def self.auto_commit(path, message = "Auto-save")
        return false unless dirty?(path)

        commit(path, message)
        true
      end
    end
  end
end
