# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module PromptObjects
  module Env
    # Imports an environment from a git bundle (.poenv file).
    # Handles security concerns around custom primitives.
    class Importer
      # Result of inspecting a bundle before import
      InspectResult = Struct.new(
        :valid,
        :name,
        :description,
        :objects,
        :primitives,
        :commits,
        :error,
        keyword_init: true
      )

      # @param bundle_path [String] Path to the .poenv bundle file
      def initialize(bundle_path)
        @bundle_path = File.expand_path(bundle_path)
      end

      # Inspect the bundle without importing it.
      # Use this to show the user what's in the bundle before importing.
      # @return [InspectResult]
      def inspect_bundle
        unless File.exist?(@bundle_path)
          return InspectResult.new(valid: false, error: "Bundle file not found: #{@bundle_path}")
        end

        unless valid_bundle?
          return InspectResult.new(valid: false, error: "Invalid git bundle file")
        end

        # Clone to temp dir to inspect contents
        Dir.mktmpdir("poenv_inspect_") do |temp_dir|
          unless Git.clone_bundle(@bundle_path, temp_dir)
            return InspectResult.new(valid: false, error: "Failed to extract bundle")
          end

          gather_inspect_result(temp_dir)
        end
      end

      # Import the bundle as a new environment.
      # @param manager [Manager] Environment manager
      # @param name [String] Name for the new environment
      # @param trust_primitives [Boolean] Trust custom primitives (skip sandboxing)
      # @return [Hash] Import result with :success, :path, :warnings
      def import(manager:, name:, trust_primitives: false)
        inspect_result = inspect_bundle
        unless inspect_result.valid
          return { success: false, error: inspect_result.error }
        end

        # Check if environment already exists
        if manager.environment_exists?(name)
          return { success: false, error: "Environment '#{name}' already exists" }
        end

        # Clone bundle to environment location
        env_path = manager.environment_path(name)
        unless Git.clone_bundle(@bundle_path, env_path)
          return { success: false, error: "Failed to clone bundle" }
        end

        # Update manifest with new name if different
        update_manifest(env_path, name)

        # Build result with warnings about primitives
        warnings = []
        if inspect_result.primitives.any? && !trust_primitives
          warnings << "This environment contains #{inspect_result.primitives.count} custom primitive(s):"
          inspect_result.primitives.each do |prim|
            warnings << "  - #{prim}"
          end
          warnings << "Custom primitives will be sandboxed by default."
          warnings << "Review the code before trusting: #{File.join(env_path, 'primitives')}"
        end

        {
          success: true,
          path: env_path,
          name: name,
          objects: inspect_result.objects,
          primitives: inspect_result.primitives,
          warnings: warnings
        }
      end

      # Check if a bundle contains custom primitives.
      # @return [Boolean]
      def has_primitives?
        result = inspect_bundle
        result.valid && result.primitives.any?
      end

      private

      def valid_bundle?
        # Git bundle verify returns 0 if valid
        system("git bundle verify #{@bundle_path} >/dev/null 2>&1")
      end

      def gather_inspect_result(temp_dir)
        objects_dir = File.join(temp_dir, "objects")
        primitives_dir = File.join(temp_dir, "primitives")
        manifest_path = File.join(temp_dir, "manifest.yml")

        # Get manifest info
        manifest_name = nil
        manifest_desc = nil
        if File.exist?(manifest_path)
          manifest = YAML.safe_load(File.read(manifest_path))
          manifest_name = manifest["name"]
          manifest_desc = manifest["description"]
        end

        # List objects and primitives
        objects = Dir.exist?(objects_dir) ? Dir.glob(File.join(objects_dir, "*.md")).map { |f| File.basename(f, ".md") } : []
        primitives = Dir.exist?(primitives_dir) ? Dir.glob(File.join(primitives_dir, "*.rb")).map { |f| File.basename(f, ".rb") } : []

        InspectResult.new(
          valid: true,
          name: manifest_name || File.basename(@bundle_path, ".poenv"),
          description: manifest_desc,
          objects: objects,
          primitives: primitives,
          commits: Git.commit_count(temp_dir)
        )
      end

      def update_manifest(env_path, new_name)
        manifest_path = File.join(env_path, "manifest.yml")
        return unless File.exist?(manifest_path)

        manifest = YAML.safe_load(File.read(manifest_path))
        original_name = manifest["name"]

        # Only update if name changed
        return if original_name == new_name

        manifest["name"] = new_name
        manifest["imported_from"] = original_name
        manifest["imported_at"] = Time.now.utc.iso8601

        File.write(manifest_path, manifest.to_yaml)

        # Commit the manifest change
        Git.commit(env_path, "Imported as '#{new_name}' (from '#{original_name}')")
      end
    end
  end
end
