# frozen_string_literal: true

require "fileutils"
require "yaml"

module PromptObjects
  module Env
    # Manages multiple environments in the user's data directory.
    # Handles creation, listing, opening, archiving environments.
    class Manager
      DEFAULT_BASE_DIR = File.expand_path("~/.prompt_objects")
      ENVIRONMENTS_DIR = "environments"
      ARCHIVE_DIR = "archive"
      CONFIG_FILE = "config.yml"
      DEV_ENV_NAME = "_development"

      attr_reader :base_dir

      def initialize(base_dir: nil)
        @base_dir = base_dir || ENV.fetch("PROMPT_OBJECTS_HOME", DEFAULT_BASE_DIR)
      end

      # Ensure base directory structure exists.
      def setup!
        FileUtils.mkdir_p(environments_dir)
        FileUtils.mkdir_p(archive_dir)
        ensure_global_config
      end

      # Path to environments directory.
      # @return [String]
      def environments_dir
        File.join(@base_dir, ENVIRONMENTS_DIR)
      end

      # Path to archive directory.
      # @return [String]
      def archive_dir
        File.join(@base_dir, ARCHIVE_DIR)
      end

      # Path to global config file.
      # @return [String]
      def config_path
        File.join(@base_dir, CONFIG_FILE)
      end

      # Load global config.
      # @return [Hash]
      def global_config
        return {} unless File.exist?(config_path)

        YAML.safe_load(File.read(config_path)) || {}
      end

      # Save global config.
      # @param config [Hash]
      def save_global_config(config)
        File.write(config_path, config.to_yaml)
      end

      # Check if any environments exist.
      # @return [Boolean]
      def any_environments?
        list.any?
      end

      # Check if first-run wizard should be shown.
      # @return [Boolean]
      def first_run?
        !any_environments?
      end

      # List all environment names.
      # @return [Array<String>]
      def list
        return [] unless Dir.exist?(environments_dir)

        Dir.children(environments_dir)
           .select { |name| environment_exists?(name) }
           .reject { |name| name.start_with?("_") } # Hide dev environments
           .sort
      end

      # List all environments with their manifests.
      # @return [Array<Manifest>]
      def list_with_manifests
        list.map { |name| manifest_for(name) }.compact
      end

      # Check if an environment exists.
      # @param name [String]
      # @return [Boolean]
      def environment_exists?(name)
        path = environment_path(name)
        Dir.exist?(path) && File.exist?(File.join(path, Env::Manifest::FILENAME))
      end

      # Get path to an environment.
      # @param name [String]
      # @return [String]
      def environment_path(name)
        File.join(environments_dir, name)
      end

      # Get manifest for an environment.
      # @param name [String]
      # @return [Manifest, nil]
      def manifest_for(name)
        return nil unless environment_exists?(name)

        Manifest.load_from_dir(environment_path(name))
      rescue StandardError
        nil
      end

      # Create a new environment from a template.
      # @param name [String] Environment name
      # @param template [String, nil] Template name (from templates/)
      # @param description [String, nil] Environment description
      # @return [String] Path to created environment
      def create(name:, template: nil, description: nil)
        raise Error, "Environment '#{name}' already exists" if environment_exists?(name)
        raise Error, "Invalid environment name: #{name}" unless valid_name?(name)

        env_path = environment_path(name)
        FileUtils.mkdir_p(env_path)
        FileUtils.mkdir_p(File.join(env_path, "objects"))
        FileUtils.mkdir_p(File.join(env_path, "primitives"))

        # Copy template if specified
        template_manifest = copy_template(env_path, template) if template

        # Create manifest
        manifest = Manifest.new(
          name: name,
          description: description || template_manifest&.dig("description"),
          icon: template_manifest&.dig("icon") || "📦",
          color: template_manifest&.dig("color") || "#4A90D9"
        )
        manifest.save_to_dir(env_path)

        # Create .gitignore
        create_gitignore(env_path)

        # Initialize git repo
        init_git(env_path)

        env_path
      end

      # Create the development environment (for --dev flag).
      # @return [String] Path to dev environment
      def create_dev_environment
        return environment_path(DEV_ENV_NAME) if environment_exists?(DEV_ENV_NAME)

        env_path = environment_path(DEV_ENV_NAME)
        FileUtils.mkdir_p(env_path)
        FileUtils.mkdir_p(File.join(env_path, "objects"))
        FileUtils.mkdir_p(File.join(env_path, "primitives"))

        manifest = Manifest.new(
          name: DEV_ENV_NAME,
          description: "Development environment",
          icon: "🔧"
        )
        manifest.save_to_dir(env_path)

        create_gitignore(env_path)
        init_git(env_path)

        env_path
      end

      # Get path to development environment.
      # @return [String]
      def dev_environment_path
        create_dev_environment
      end

      # Archive (soft delete) an environment.
      # @param name [String]
      def archive(name)
        raise Error, "Environment '#{name}' not found" unless environment_exists?(name)
        raise Error, "Cannot archive development environment" if name == DEV_ENV_NAME

        src = environment_path(name)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        dest = File.join(archive_dir, "#{name}_#{timestamp}")

        FileUtils.mv(src, dest)
        dest
      end

      # List archived environments.
      # @return [Array<String>]
      def list_archived
        return [] unless Dir.exist?(archive_dir)

        Dir.children(archive_dir).sort
      end

      # Restore an archived environment.
      # @param archived_name [String] Name with timestamp suffix
      # @param restore_as [String, nil] New name (defaults to original name)
      def restore(archived_name, restore_as: nil)
        src = File.join(archive_dir, archived_name)
        raise Error, "Archived environment not found: #{archived_name}" unless Dir.exist?(src)

        # Extract original name (remove timestamp suffix)
        original_name = archived_name.sub(/_\d{8}_\d{6}$/, "")
        new_name = restore_as || original_name

        raise Error, "Environment '#{new_name}' already exists" if environment_exists?(new_name)

        dest = environment_path(new_name)
        FileUtils.mv(src, dest)

        # Update manifest name if restored under different name
        if new_name != original_name
          manifest = Manifest.load_from_dir(dest)
          manifest.name = new_name
          manifest.save_to_dir(dest)
        end

        dest
      end

      # Permanently delete an archived environment.
      # @param archived_name [String]
      def delete_archived(archived_name)
        path = File.join(archive_dir, archived_name)
        raise Error, "Archived environment not found: #{archived_name}" unless Dir.exist?(path)

        FileUtils.rm_rf(path)
      end

      # Clone an environment.
      # @param source_name [String]
      # @param new_name [String]
      # @return [String] Path to cloned environment
      def clone(source_name, new_name)
        raise Error, "Source environment '#{source_name}' not found" unless environment_exists?(source_name)
        raise Error, "Environment '#{new_name}' already exists" if environment_exists?(new_name)
        raise Error, "Invalid environment name: #{new_name}" unless valid_name?(new_name)

        src = environment_path(source_name)
        dest = environment_path(new_name)

        # Copy directory (excluding sessions.db)
        FileUtils.mkdir_p(dest)
        Dir.glob(File.join(src, "**", "*"), File::FNM_DOTMATCH).each do |path|
          relative = path.sub("#{src}/", "")
          next if relative == "." || relative == ".."
          next if relative.include?("sessions.db")
          next if relative.start_with?(".git/")

          target = File.join(dest, relative)
          if File.directory?(path)
            FileUtils.mkdir_p(target)
          else
            FileUtils.cp(path, target)
          end
        end

        # Update manifest
        manifest = Manifest.load_from_dir(dest)
        manifest.name = new_name
        manifest.instance_variable_set(:@created_at, Time.now)
        manifest.instance_variable_set(:@stats, { "total_messages" => 0, "total_sessions" => 0, "po_count" => manifest.stats["po_count"] })
        manifest.save_to_dir(dest)

        # Initialize fresh git repo
        init_git(dest)

        dest
      end

      # Get default environment name from config.
      # @return [String, nil]
      def default_environment
        global_config["default_environment"]
      end

      # Set default environment.
      # @param name [String]
      def set_default_environment(name)
        raise Error, "Environment '#{name}' not found" unless environment_exists?(name)

        config = global_config
        config["default_environment"] = name
        save_global_config(config)
      end

      private

      # Validate environment name.
      # @param name [String]
      # @return [Boolean]
      def valid_name?(name)
        return false if name.nil? || name.empty?
        return false if name.start_with?("_") # Reserved for system envs
        return false unless name.match?(/\A[a-zA-Z0-9_-]+\z/)

        true
      end

      # Copy template files to environment.
      # @param env_path [String]
      # @param template_name [String]
      # @return [Hash, nil] Template manifest data
      def copy_template(env_path, template_name)
        template_path = find_template(template_name)
        raise Error, "Template '#{template_name}' not found" unless template_path

        # Read template manifest
        template_manifest_path = File.join(template_path, "manifest.yml")
        template_manifest = if File.exist?(template_manifest_path)
                              YAML.safe_load(File.read(template_manifest_path))
                            end

        # Copy objects
        template_objects = File.join(template_path, "objects")
        if Dir.exist?(template_objects)
          FileUtils.cp_r(Dir.glob("#{template_objects}/*"), File.join(env_path, "objects"))
        end

        # Copy primitives if present
        template_primitives = File.join(template_path, "primitives")
        if Dir.exist?(template_primitives)
          FileUtils.cp_r(Dir.glob("#{template_primitives}/*"), File.join(env_path, "primitives"))
        end

        template_manifest
      end

      # Find template directory.
      # @param name [String]
      # @return [String, nil]
      def find_template(name)
        # Look in gem's templates directory
        gem_templates = File.expand_path("../../../../templates", __FILE__)
        path = File.join(gem_templates, name)
        return path if Dir.exist?(path)

        nil
      end

      # Create .gitignore for environment.
      # @param env_path [String]
      def create_gitignore(env_path)
        gitignore_content = <<~GITIGNORE
          # Session data (private)
          sessions.db
          sessions.db-journal
          sessions.db-wal
          sessions.db-shm
        GITIGNORE

        File.write(File.join(env_path, ".gitignore"), gitignore_content)
      end

      # Initialize git repository.
      # @param env_path [String]
      def init_git(env_path)
        Dir.chdir(env_path) do
          system("git init --quiet")
          system("git add .")
          system("git commit --quiet -m 'Initial environment setup'")
        end
      end

      # Ensure global config file exists.
      def ensure_global_config
        return if File.exist?(config_path)

        save_global_config({
          "default_environment" => nil,
          "trusted_primitives" => []
        })
      end
    end
  end
end
