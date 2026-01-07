# frozen_string_literal: true

module PromptObjects
  # Context object passed to capabilities during execution.
  # Provides access to environment, message bus, and tracks execution.
  class Context
    attr_reader :env, :bus, :human_queue
    attr_accessor :current_capability, :calling_po, :tui_mode

    def initialize(env:, bus:, human_queue: nil)
      @env = env
      @bus = bus
      @human_queue = human_queue
      @current_capability = nil
      @calling_po = nil  # The PO that initiated the tool call (for resolving "self")
      @tui_mode = false
    end

    # Log a message to the bus.
    # @param to [String] Destination capability
    # @param message [String, Hash] The message
    def log_message(to:, message:)
      @bus.publish(from: @current_capability || "human", to: to, message: message)
    end

    # Log a response to the bus.
    # @param from [String] Source capability
    # @param message [String, Hash] The response
    def log_response(from:, message:)
      @bus.publish(from: from, to: @current_capability || "human", message: message)
    end
  end

  # The runtime environment that holds all capabilities and coordinates execution.
  # Can be initialized either from:
  # - A user environment directory (with manifest.yml, git integration)
  # - A simple objects directory (legacy/development mode)
  class Runtime
    attr_reader :llm, :registry, :objects_dir, :bus, :primitives_dir, :human_queue,
                :manifest, :env_path, :auto_commit, :session_store

    # Initialize from an environment path (with manifest) or objects directory.
    # @param env_path [String, nil] Path to environment directory (preferred)
    # @param objects_dir [String, nil] Legacy: path to objects directory
    # @param primitives_dir [String, nil] Path to primitives directory
    # @param llm [LLM::OpenAIAdapter, nil] LLM adapter
    # @param auto_commit [Boolean] Auto-commit changes to git (default: true for env_path)
    def initialize(env_path: nil, objects_dir: nil, primitives_dir: nil, llm: nil, auto_commit: nil)
      if env_path
        # Environment-based initialization
        @env_path = env_path
        @objects_dir = File.join(env_path, "objects")
        @primitives_dir = primitives_dir || File.join(env_path, "primitives")
        @manifest = Env::Manifest.load_from_dir(env_path)
        @auto_commit = auto_commit.nil? ? true : auto_commit
        @manifest.touch_opened!
        @manifest.save_to_dir(env_path)

        # Initialize session store
        db_path = File.join(env_path, "sessions.db")
        @session_store = Session::Store.new(db_path)
      else
        # Legacy objects_dir initialization
        @env_path = nil
        @objects_dir = objects_dir || "objects"
        @primitives_dir = primitives_dir || File.join(File.dirname(@objects_dir), "primitives")
        @manifest = nil
        @auto_commit = auto_commit || false
        @session_store = nil  # No persistent sessions in legacy mode
      end

      @llm = llm || LLM::OpenAIAdapter.new
      @registry = Registry.new
      @bus = MessageBus.new
      @human_queue = HumanQueue.new

      register_primitives
      register_universal_capabilities
    end

    # Create runtime from a user environment by name.
    # @param name [String] Environment name
    # @param manager [Env::Manager, nil] Manager instance
    # @return [Runtime]
    def self.from_environment(name, manager: nil)
      manager ||= Env::Manager.new
      raise Error, "Environment '#{name}' not found" unless manager.environment_exists?(name)

      new(env_path: manager.environment_path(name))
    end

    # Name of the environment (from manifest or directory name).
    # @return [String]
    def name
      @manifest&.name || File.basename(@objects_dir)
    end

    # Check if this is an environment-based runtime (vs legacy objects_dir).
    # @return [Boolean]
    def environment?
      !@env_path.nil?
    end

    # Save a commit with all current changes.
    # @param message [String]
    # @return [Boolean] True if committed
    def save(message = "Save changes")
      return false unless environment? && @auto_commit

      Env::Git.auto_commit(@env_path, message)
    end

    # Check if there are unsaved changes.
    # @return [Boolean]
    def dirty?
      return false unless environment?

      Env::Git.dirty?(@env_path)
    end

    # Update manifest stats from current state.
    def update_manifest_stats!
      return unless @manifest

      stats = { po_count: @registry.prompt_objects.size }

      # Add session stats if available
      if @session_store
        stats[:total_sessions] = @session_store.total_sessions
        stats[:total_messages] = @session_store.total_messages
      end

      @manifest.update_stats(**stats)
      @manifest.save_to_dir(@env_path)
    end

    # Create a context for capability execution.
    # @param tui_mode [Boolean] Whether running in TUI mode
    # @return [Context]
    def context(tui_mode: false)
      ctx = Context.new(env: self, bus: @bus, human_queue: @human_queue)
      ctx.tui_mode = tui_mode
      ctx
    end

    # Load a prompt object from a file path.
    # @param path [String] Path to the .md file
    # @return [PromptObject]
    def load_prompt_object(path)
      data = Loader.load(path)

      po = PromptObject.new(
        config: data[:config],
        body: data[:body],
        env: self,
        llm: @llm
      )

      @registry.register(po)
      po
    end

    # Load a prompt object by name from the objects directory.
    # @param name [String] Name of the prompt object (without .md extension)
    # @return [PromptObject]
    def load_by_name(name)
      path = File.join(@objects_dir, "#{name}.md")
      load_prompt_object(path)
    end

    # Load all prompt objects that a capability depends on.
    # @param capability [PromptObject] The capability to load dependencies for
    def load_dependencies(capability)
      return unless capability.is_a?(PromptObject)

      deps = capability.config["capabilities"] || []
      deps.each do |dep_name|
        next if @registry.exists?(dep_name)

        # Try to load as a prompt object
        path = File.join(@objects_dir, "#{dep_name}.md")
        if File.exist?(path)
          load_prompt_object(path)
        end
      end
    end

    # Get a capability by name (prompt object or primitive).
    # @param name [String] The capability name
    # @return [Capability, nil]
    def get(name)
      @registry.get(name)
    end

    # List all loaded prompt objects.
    # @return [Array<String>]
    def loaded_objects
      @registry.prompt_objects.map(&:name)
    end

    # List all registered primitives.
    # @return [Array<String>]
    def primitives
      @registry.primitives.map(&:name)
    end

    private

    # Register built-in primitive capabilities.
    def register_primitives
      @registry.register(Primitives::ReadFile.new)
      @registry.register(Primitives::ListFiles.new)
      @registry.register(Primitives::WriteFile.new)
      @registry.register(Primitives::HttpGet.new)
    end

    # Register universal capabilities (available to all prompt objects).
    def register_universal_capabilities
      @registry.register(Universal::AskHuman.new)
      @registry.register(Universal::Think.new)
      @registry.register(Universal::CreateCapability.new)
      @registry.register(Universal::AddCapability.new)
      @registry.register(Universal::ListCapabilities.new)
      @registry.register(Universal::ListPrimitives.new)
      @registry.register(Universal::AddPrimitive.new)
      @registry.register(Universal::CreatePrimitive.new)
      @registry.register(Universal::VerifyPrimitive.new)
      @registry.register(Universal::ModifyPrimitive.new)
      @registry.register(Universal::RequestPrimitive.new)
    end
  end

  # Backwards compatibility alias (Environment was renamed to Runtime).
  # Use Runtime for new code; Environment is preserved for existing callers.
  Environment = Runtime
end
