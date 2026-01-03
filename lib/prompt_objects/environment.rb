# frozen_string_literal: true

module PromptObjects
  # Context object passed to capabilities during execution.
  # Provides access to environment, message bus, and tracks execution.
  class Context
    attr_reader :env, :bus
    attr_accessor :current_capability

    def initialize(env:, bus:)
      @env = env
      @bus = bus
      @current_capability = nil
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
  class Environment
    attr_reader :llm, :registry, :objects_dir, :bus

    def initialize(objects_dir: "objects", llm: nil)
      @objects_dir = objects_dir
      @llm = llm || LLM::OpenAIAdapter.new
      @registry = Registry.new
      @bus = MessageBus.new

      register_primitives
      register_universal_capabilities
    end

    # Create a context for capability execution.
    # @return [Context]
    def context
      Context.new(env: self, bus: @bus)
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
    end
  end
end
