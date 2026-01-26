# frozen_string_literal: true

module PromptObjects
  # Registry for all capabilities (both primitives and prompt objects).
  # Supports both:
  # - RubyLLM::Tool classes (primitives) - stored as classes
  # - Capability instances (PromptObjects) - stored as instances
  class Registry
    def initialize
      @capabilities = {}
      @tool_classes = {}  # Cache for tool class lookups
    end

    # Register a capability.
    # @param capability [Class, Capability] Tool class or capability instance
    # @return [Class, Capability] The registered capability
    def register(capability)
      name = extract_name(capability)
      @capabilities[name] = capability
      @tool_classes.delete(name)  # Clear cache
      capability
    end

    # Unregister a capability by name.
    # @param name [String] The capability name
    # @return [Class, Capability, nil] The removed capability or nil
    def unregister(name)
      @tool_classes.delete(name.to_s)
      @capabilities.delete(name.to_s)
    end

    # Get a capability by name.
    # @param name [String] The capability name
    # @return [Class, Capability, nil] The capability or nil if not found
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
    # @return [Array<Class, Capability>]
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

    # Get only primitives (RubyLLM::Tool subclasses).
    # @return [Array<Class>]
    def primitives
      @capabilities.values.select { |c| ruby_llm_tool_class?(c) }
    end

    # Check if a capability is a prompt object.
    # @param name [String] The capability name
    # @return [Boolean]
    def prompt_object?(name)
      cap = get(name)
      cap.is_a?(PromptObject)
    end

    # Check if a capability is a RubyLLM::Tool class.
    # @param name [String] The capability name
    # @return [Boolean]
    def tool_class?(name)
      cap = get(name)
      ruby_llm_tool_class?(cap)
    end

    # Get RubyLLM::Tool classes for a list of capability names.
    # Creates wrapper classes for non-tool capabilities (like PromptObjects).
    # @param names [Array<String>] Capability names
    # @param context [Context, nil] Context to inject into wrapper tools
    # @return [Array<Class>] Tool classes for RubyLLM
    def tool_classes_for(names, context: nil)
      names.filter_map do |name|
        get_or_create_tool_class(name, context)
      end
    end

    # Get tool descriptors for a list of capability names (legacy support).
    # @param names [Array<String>] Capability names
    # @return [Array<Hash>] Tool descriptors for LLM
    def descriptors_for(names)
      names.filter_map do |name|
        cap = get(name)
        next unless cap

        if ruby_llm_tool_class?(cap)
          # Generate descriptor from RubyLLM::Tool class
          tool_descriptor_from_class(cap)
        elsif cap.respond_to?(:descriptor)
          cap.descriptor
        end
      end
    end

    # Get tool descriptors for all capabilities.
    # @return [Array<Hash>]
    def all_descriptors
      @capabilities.values.map do |cap|
        if ruby_llm_tool_class?(cap)
          tool_descriptor_from_class(cap)
        elsif cap.respond_to?(:descriptor)
          cap.descriptor
        end
      end.compact
    end

    private

    def extract_name(capability)
      if capability.is_a?(Class)
        # RubyLLM::Tool class - use the tool_name if available
        if capability.respond_to?(:tool_name)
          capability.tool_name
        elsif capability.respond_to?(:name)
          # Convert class name to snake_case tool name
          capability.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        else
          capability.to_s
        end
      else
        # Instance - use name method
        capability.name.to_s
      end
    end

    def ruby_llm_tool_class?(cap)
      cap.is_a?(Class) && defined?(RubyLLM::Tool) && cap < RubyLLM::Tool
    end

    def get_or_create_tool_class(name, context)
      cap = get(name)
      return nil unless cap

      if ruby_llm_tool_class?(cap)
        # Already a RubyLLM::Tool class
        cap
      elsif cap.is_a?(PromptObject)
        # Create a wrapper tool class for the PromptObject
        create_po_wrapper_tool(cap, context)
      elsif cap.respond_to?(:receive)
        # Create a wrapper for old-style capabilities
        create_capability_wrapper_tool(cap, context)
      end
    end

    # Create a wrapper RubyLLM::Tool class for a PromptObject
    def create_po_wrapper_tool(po, context)
      # Cache the wrapper class
      cache_key = "po_#{po.name}"
      return @tool_classes[cache_key] if @tool_classes[cache_key]

      # Create a dynamic tool class
      wrapper = Class.new(RubyLLM::Tool) do
        @po = po
        @context = context

        class << self
          attr_accessor :po, :context
        end

        description po.description
        param :message, desc: "Natural language message to send to #{po.name}"

        define_method(:execute) do |message:|
          self.class.po.receive(message, context: self.class.context)
        end

        define_method(:name) { self.class.po.name }
      end

      # Set the tool name
      wrapper.define_singleton_method(:tool_name) { po.name }

      @tool_classes[cache_key] = wrapper
      wrapper
    end

    # Create a wrapper RubyLLM::Tool class for an old-style capability
    def create_capability_wrapper_tool(cap, context)
      cache_key = "cap_#{cap.name}"
      return @tool_classes[cache_key] if @tool_classes[cache_key]

      wrapper = Class.new(RubyLLM::Tool) do
        @capability = cap
        @context = context

        class << self
          attr_accessor :capability, :context
        end

        description cap.description

        # Define params from capability's parameters schema
        if cap.respond_to?(:parameters)
          params = cap.parameters
          if params[:properties]
            params[:properties].each do |prop_name, prop_def|
              param prop_name.to_sym, desc: prop_def[:description] || prop_name.to_s
            end
          end
        end

        define_method(:execute) do |**args|
          self.class.capability.receive(args, context: self.class.context)
        end

        define_method(:name) { self.class.capability.name }
      end

      wrapper.define_singleton_method(:tool_name) { cap.name }

      @tool_classes[cache_key] = wrapper
      wrapper
    end

    # Generate a tool descriptor from a RubyLLM::Tool class
    def tool_descriptor_from_class(tool_class)
      {
        type: "function",
        function: {
          name: extract_name(tool_class),
          description: tool_class.description,
          parameters: extract_parameters_schema(tool_class)
        }
      }
    end

    def extract_parameters_schema(tool_class)
      # RubyLLM::Tool stores parameters in class-level methods
      return { type: "object", properties: {} } unless tool_class.respond_to?(:parameters)

      schema = tool_class.parameters
      return schema if schema.is_a?(Hash) && schema[:type]

      # Build schema from param definitions
      properties = {}
      required = []

      if tool_class.respond_to?(:defined_params)
        tool_class.defined_params.each do |param|
          properties[param[:name]] = {
            type: param[:type] || "string",
            description: param[:desc] || param[:description] || param[:name].to_s
          }
          required << param[:name].to_s if param[:required]
        end
      end

      {
        type: "object",
        properties: properties,
        required: required.empty? ? nil : required
      }.compact
    end
  end
end
