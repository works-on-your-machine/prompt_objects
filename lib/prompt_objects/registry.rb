# frozen_string_literal: true

module PromptObjects
  # Registry for all capabilities (both primitives and prompt objects).
  # Provides lookup by name and generates tool descriptors for LLM calls.
  class Registry
    def initialize
      @capabilities = {}
    end

    # Register a capability.
    # @param capability [Capability] The capability to register
    # @return [Capability] The registered capability
    def register(capability)
      @capabilities[capability.name] = capability
      capability
    end

    # Unregister a capability by name.
    # @param name [String] The capability name
    # @return [Capability, nil] The removed capability or nil
    def unregister(name)
      @capabilities.delete(name.to_s)
    end

    # Get a capability by name.
    # @param name [String] The capability name
    # @return [Capability, nil] The capability or nil if not found
    def get(name)
      @capabilities[name.to_s]
    end

    # Check if a capability exists.
    # @param name [String] The capability name
    # @return [Boolean]
    def exists?(name)
      @capabilities.key?(name.to_s)
    end

    # Get all registered capabilities.
    # @return [Array<Capability>]
    def all
      @capabilities.values
    end

    # Get all capability names.
    # @return [Array<String>]
    def names
      @capabilities.keys
    end

    # Get only prompt objects.
    # @return [Array<PromptObject>]
    def prompt_objects
      @capabilities.values.select { |c| c.is_a?(PromptObject) }
    end

    # Get only primitives.
    # @return [Array<Primitive>]
    def primitives
      @capabilities.values.select { |c| c.is_a?(Primitive) }
    end

    # Check if a capability is a prompt object.
    # @param name [String] The capability name
    # @return [Boolean]
    def prompt_object?(name)
      cap = get(name)
      cap.is_a?(PromptObject)
    end

    # Get tool descriptors for a list of capability names.
    # @param names [Array<String>] Capability names
    # @return [Array<Hash>] Tool descriptors for LLM
    def descriptors_for(names)
      names.filter_map do |name|
        cap = get(name)
        cap&.descriptor
      end
    end

    # Get tool descriptors for all capabilities.
    # @return [Array<Hash>]
    def all_descriptors
      @capabilities.values.map(&:descriptor)
    end
  end
end
