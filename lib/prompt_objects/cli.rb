# frozen_string_literal: true

module PromptObjects
  # Command-line interface for environment management.
  module CLI
    # Handle env subcommands: list, create, info, archive, restore, clone, etc.
    class EnvCommand
      def initialize(manager: nil)
        @manager = manager || Env::Manager.new
      end

      # Run the env subcommand.
      # @param args [Array<String>] Arguments after 'env'
      def run(args)
        subcommand = args.shift || "list"

        case subcommand
        when "list", "ls"
          list
        when "create", "new"
          create(args)
        when "info"
          info(args)
        when "export"
          export(args)
        when "import"
          import(args)
        when "archive"
          archive(args)
        when "restore"
          restore(args)
        when "clone", "cp"
          clone(args)
        when "delete"
          delete(args)
        when "default"
          set_default(args)
        else
          puts "Unknown env command: #{subcommand}"
          puts
          help
          exit 1
        end
      end

      def list
        @manager.setup!
        envs = @manager.list_with_manifests

        if envs.empty?
          puts "No environments found."
          puts "Create one with: prompt_objects env create <name>"
          return
        end

        default = @manager.default_environment

        puts "Environments:"
        puts
        envs.each do |manifest|
          default_marker = manifest.name == default ? " (default)" : ""
          last_opened = manifest.last_opened&.strftime("%Y-%m-%d") || "never"
          puts "  #{manifest.icon} #{manifest.name}#{default_marker}"
          puts "    #{manifest.description}" if manifest.description
          puts "    Last opened: #{last_opened}, Objects: #{manifest.stats['po_count']}"
          puts
        end
      end

      def create(args)
        name = args.shift
        unless name
          puts "Usage: prompt_objects env create <name> [--template <template>]"
          exit 1
        end

        template = nil
        args.each_with_index do |arg, i|
          if arg == "--template" || arg == "-t"
            template = args[i + 1]
          end
        end

        @manager.setup!

        path = @manager.create(name: name, template: template)
        puts "Created environment: #{name}"
        puts "Location: #{path}"

        if @manager.list.size == 1
          @manager.set_default_environment(name)
          puts "Set as default environment."
        end
      end

      def info(args)
        name = args.shift || @manager.default_environment
        unless name
          puts "Usage: prompt_objects env info <name>"
          exit 1
        end

        manifest = @manager.manifest_for(name)
        unless manifest
          puts "Environment '#{name}' not found."
          exit 1
        end

        path = @manager.environment_path(name)
        objects = Dir.glob(File.join(path, "objects", "*.md")).map { |f| File.basename(f, ".md") }
        primitives = Dir.glob(File.join(path, "primitives", "*.rb")).map { |f| File.basename(f, ".rb") }

        puts manifest.info
        puts
        puts "  Location: #{path}"
        puts "  Objects: #{objects.join(', ')}" if objects.any?
        puts "  Custom primitives: #{primitives.join(', ')}" if primitives.any?
        puts

        if Env::Git.repo?(path)
          commits = Env::Git.commit_count(path)
          dirty = Env::Git.dirty?(path)
          puts "  Git: #{commits} commits#{dirty ? ' (uncommitted changes)' : ''}"
        end
      end

      def export(args)
        @manager.setup!

        # Parse arguments
        name = nil
        output = nil

        i = 0
        while i < args.length
          case args[i]
          when "-o", "--output"
            output = args[i + 1]
            i += 1
          else
            name ||= args[i]
          end
          i += 1
        end

        # Default to current directory name if no output specified
        name ||= @manager.default_environment
        unless name
          puts "Usage: prompt_objects env export <name> [-o output.poenv]"
          exit 1
        end

        unless @manager.environment_exists?(name)
          puts "Environment '#{name}' not found."
          exit 1
        end

        output ||= "#{name}.poenv"
        env_path = @manager.environment_path(name)

        exporter = Env::Exporter.new(env_path)
        result = exporter.export(output)

        if result[:success]
          puts "Exported '#{name}' to: #{result[:path]}"
          puts
          puts "Stats:"
          puts "  Commits: #{result[:stats][:commits]}"
          puts "  Objects: #{result[:stats][:objects]}"
          puts "  Primitives: #{result[:stats][:primitives]}"
        else
          puts "Export failed: #{result[:error]}"
          exit 1
        end
      end

      def import(args)
        @manager.setup!

        # Parse arguments
        bundle_path = nil
        import_as = nil
        trust = false

        i = 0
        while i < args.length
          case args[i]
          when "--as"
            import_as = args[i + 1]
            i += 1
          when "--trust"
            trust = true
          else
            bundle_path ||= args[i]
          end
          i += 1
        end

        unless bundle_path
          puts "Usage: prompt_objects env import <bundle.poenv> [--as <name>] [--trust]"
          puts
          puts "Options:"
          puts "  --as <name>   Import with a different name"
          puts "  --trust       Trust custom primitives (skip sandbox warnings)"
          exit 1
        end

        importer = Env::Importer.new(bundle_path)

        # First, inspect and show what's in the bundle
        info = importer.inspect_bundle
        unless info.valid
          puts "Invalid bundle: #{info.error}"
          exit 1
        end

        puts "Bundle contents:"
        puts "  Name: #{info.name}"
        puts "  Description: #{info.description}" if info.description
        puts "  Objects: #{info.objects.join(', ')}" if info.objects.any?
        puts "  Primitives: #{info.primitives.join(', ')}" if info.primitives.any?
        puts "  Commits: #{info.commits}"
        puts

        # Warn about primitives
        if info.primitives.any? && !trust
          puts "⚠️  WARNING: This bundle contains custom primitives."
          puts "Custom primitives can execute arbitrary Ruby code."
          puts "Review the code before running, or use --trust to skip this warning."
          puts
        end

        # Import
        import_name = import_as || info.name
        result = importer.import(manager: @manager, name: import_name, trust_primitives: trust)

        if result[:success]
          puts "Imported as '#{result[:name]}'"
          puts "Location: #{result[:path]}"

          if result[:warnings].any?
            puts
            result[:warnings].each { |w| puts w }
          end
        else
          puts "Import failed: #{result[:error]}"
          exit 1
        end
      end

      def archive(args)
        name = args.shift
        unless name
          puts "Usage: prompt_objects env archive <name>"
          exit 1
        end

        path = @manager.archive(name)
        puts "Archived environment '#{name}' to:"
        puts "  #{path}"
      end

      def restore(args)
        archived_name = args.shift
        unless archived_name
          # Show available archived environments
          archived = @manager.list_archived
          if archived.empty?
            puts "No archived environments."
          else
            puts "Archived environments:"
            archived.each { |name| puts "  - #{name}" }
            puts
            puts "Usage: prompt_objects env restore <archived_name> [--as <new_name>]"
          end
          return
        end

        restore_as = nil
        args.each_with_index do |arg, i|
          restore_as = args[i + 1] if arg == "--as"
        end

        path = @manager.restore(archived_name, restore_as: restore_as)
        puts "Restored to: #{path}"
      end

      def clone(args)
        source = args.shift
        target = args.shift

        unless source && target
          puts "Usage: prompt_objects env clone <source> <target>"
          exit 1
        end

        path = @manager.clone(source, target)
        puts "Cloned '#{source}' to '#{target}'"
        puts "Location: #{path}"
      end

      def delete(args)
        name = args.shift
        permanent = args.include?("--permanent")

        unless name
          puts "Usage: prompt_objects env delete <archived_name> --permanent"
          puts
          puts "Note: Only archived environments can be permanently deleted."
          puts "First archive an environment, then delete it."
          return
        end

        unless permanent
          puts "Use --permanent to confirm deletion."
          puts "This cannot be undone."
          return
        end

        @manager.delete_archived(name)
        puts "Permanently deleted: #{name}"
      end

      def set_default(args)
        name = args.shift
        unless name
          current = @manager.default_environment
          if current
            puts "Current default: #{current}"
          else
            puts "No default environment set."
          end
          puts
          puts "Usage: prompt_objects env default <name>"
          return
        end

        @manager.set_default_environment(name)
        puts "Default environment set to: #{name}"
      end

      def help
        puts <<~HELP
          Environment management commands:

            prompt_objects env list              List all environments
            prompt_objects env create <name>    Create new environment
              --template, -t <template>         Use template (minimal, developer, writer, empty)
            prompt_objects env info <name>      Show environment details
            prompt_objects env export <name>    Export environment as .poenv bundle
              -o, --output <file>               Output file path
            prompt_objects env import <file>    Import environment from .poenv bundle
              --as <name>                       Import with different name
              --trust                           Trust custom primitives
            prompt_objects env archive <name>   Archive (soft delete) environment
            prompt_objects env restore <name>   Restore archived environment
              --as <new_name>                   Restore with different name
            prompt_objects env clone <src> <dest>  Clone environment
            prompt_objects env default <name>   Set default environment
            prompt_objects env delete <name> --permanent  Delete archived env

          Available templates:
            minimal    - Basic assistant PO
            developer  - Code review, debugging, testing specialists
            writer     - Editor, researcher for content creation
            empty      - No objects, full control
        HELP
      end
    end

    # Parse arguments and run appropriate command.
    # @param args [Array<String>] Command line arguments
    # @return [Hash] Parsed options for main command
    def self.parse(args)
      options = {
        env_name: nil,
        dev_mode: false,
        sandbox: false,
        command: :run
      }

      i = 0
      while i < args.length
        arg = args[i]
        case arg
        when "env"
          options[:command] = :env
          options[:env_args] = args[(i + 1)..]
          return options
        when "--env", "-e"
          options[:env_name] = args[i + 1]
          i += 1
        when "--dev"
          options[:dev_mode] = true
        when "--sandbox", "-s"
          options[:sandbox] = true
        when "--help", "-h"
          options[:command] = :help
          return options
        else
          # Assume it's a PO name or objects_dir (legacy)
          options[:legacy_args] ||= []
          options[:legacy_args] << arg
        end
        i += 1
      end

      options
    end

    # List available templates.
    # @return [Array<Hash>] Template info
    def self.list_templates
      templates_dir = File.expand_path("../../templates", __dir__)
      return [] unless Dir.exist?(templates_dir)

      Dir.children(templates_dir).filter_map do |name|
        manifest_path = File.join(templates_dir, name, "manifest.yml")
        next unless File.exist?(manifest_path)

        manifest = YAML.safe_load(File.read(manifest_path))
        {
          name: name,
          description: manifest["description"],
          icon: manifest["icon"]
        }
      end
    end
  end
end
