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
  # For Phase 1, this is a minimal implementation - just enough to run a single PO.
  class Environment
    attr_reader :llm, :registry, :objects_dir

    def initialize(objects_dir: "objects", llm: nil)
      @objects_dir = objects_dir
      @llm = llm || LLM::OpenAIAdapter.new
      @registry = nil  # Will be added in Phase 2
      @prompt_objects = {}
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

      @prompt_objects[po.name] = po
      po
    end

    # Load a prompt object by name from the objects directory.
    # @param name [String] Name of the prompt object (without .md extension)
    # @return [PromptObject]
    def load_by_name(name)
      path = File.join(@objects_dir, "#{name}.md")
      load_prompt_object(path)
    end

    # Get a loaded prompt object by name.
    # @param name [String] Name of the prompt object
    # @return [PromptObject, nil]
    def get(name)
      @prompt_objects[name]
    end

    # List all loaded prompt objects.
    # @return [Array<String>] Names of loaded prompt objects
    def loaded_objects
      @prompt_objects.keys
    end
  end
end
