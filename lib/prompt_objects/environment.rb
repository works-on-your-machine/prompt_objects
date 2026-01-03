# frozen_string_literal: true

module PromptObjects
  # Simple context object passed to capabilities during execution.
  class Context
    attr_reader :env
    attr_accessor :current_capability

    def initialize(env:)
      @env = env
      @current_capability = nil
    end
  end

  # The runtime environment that holds all capabilities and coordinates execution.
  class Environment
    attr_reader :llm, :registry, :objects_dir

    def initialize(objects_dir: "objects", llm: nil)
      @objects_dir = objects_dir
      @llm = llm || LLM::OpenAIAdapter.new
      @registry = Registry.new

      register_primitives
    end

    # Create a context for capability execution.
    # @return [Context]
    def context
      Context.new(env: self)
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
    end
  end
end
