# frozen_string_literal: true

require "yaml"

module PromptObjects
  module Universal
    # Universal capability to create new capabilities at runtime.
    # Can create both prompt objects (markdown) and primitives (Ruby code).
    # This enables self-modification - the system can create new specialists and tools.
    class CreateCapability < Primitive
      def name
        "create_capability"
      end

      def description
        "Create a new capability. Use type='prompt_object' for LLM-backed specialists, or type='primitive' for deterministic Ruby tools."
      end

      def parameters
        {
          type: "object",
          properties: {
            type: {
              type: "string",
              enum: ["prompt_object", "primitive"],
              description: "Type of capability: 'prompt_object' for LLM specialists, 'primitive' for Ruby tools"
            },
            name: {
              type: "string",
              description: "Name for the capability (lowercase, underscores allowed)"
            },
            description: {
              type: "string",
              description: "Brief description of what this capability does"
            },
            # For prompt_objects:
            capabilities: {
              type: "array",
              items: { type: "string" },
              description: "(prompt_object only) List of capabilities this PO can use"
            },
            identity: {
              type: "string",
              description: "(prompt_object only) Who is this prompt object? Their personality and role."
            },
            behavior: {
              type: "string",
              description: "(prompt_object only) How should this prompt object behave?"
            },
            # For primitives:
            parameters_schema: {
              type: "object",
              description: "(primitive only) JSON Schema for the parameters this primitive accepts"
            },
            ruby_code: {
              type: "string",
              description: "(primitive only) Ruby code for the receive method body. Has access to 'message' (Hash) and 'context'."
            }
          },
          required: ["type", "name", "description"]
        }
      end

      def receive(message, context:)
        type = message[:type] || message["type"]
        cap_name = message[:name] || message["name"]

        # Validate name
        unless cap_name && cap_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return "Error: Name must be lowercase letters, numbers, and underscores, starting with a letter."
        end

        # Check if already exists
        if context.env.registry.exists?(cap_name)
          return "Error: A capability named '#{cap_name}' already exists."
        end

        result = case type
        when "prompt_object"
          create_prompt_object(message, context)
        when "primitive"
          create_primitive(message, context)
        else
          return "Error: type must be 'prompt_object' or 'primitive'"
        end

        # If creation succeeded, add the new capability to the creating PO
        if result && !result.start_with?("Error:")
          added_msg = add_to_creator(cap_name, context)
          result = "#{result} #{added_msg}" if added_msg
        end

        result
      end

      private

      # Add the newly created capability to the PO that created it
      # Returns a message if added, nil otherwise
      def add_to_creator(cap_name, context)
        creator_name = context.calling_po
        return nil unless creator_name

        creator_po = context.env.registry.get(creator_name)
        return nil unless creator_po.is_a?(PromptObject)

        # Add to the creator's capabilities if not already present
        creator_po.config["capabilities"] ||= []
        unless creator_po.config["capabilities"].include?(cap_name)
          creator_po.config["capabilities"] << cap_name
          return "Also added '#{cap_name}' to #{creator_name}'s capabilities."
        end

        nil
      end

      def create_prompt_object(message, context)
        cap_name = message[:name] || message["name"]
        description = message[:description] || message["description"]
        capabilities = message[:capabilities] || message["capabilities"] || []
        identity = message[:identity] || message["identity"] || "You are a helpful assistant."
        behavior = message[:behavior] || message["behavior"] || "Help the user with their request."

        # Build the markdown content
        frontmatter = {
          "name" => cap_name,
          "description" => description,
          "capabilities" => capabilities
        }

        body = <<~MARKDOWN
          # #{cap_name.split('_').map(&:capitalize).join(' ')}

          ## Identity

          #{identity}

          ## Behavior

          #{behavior}
        MARKDOWN

        # to_yaml already includes leading "---\n", so we just need the closing ---
        content = "#{frontmatter.to_yaml}---\n\n#{body}"

        # Write to file
        path = File.join(context.env.objects_dir, "#{cap_name}.md")
        File.write(path, content, encoding: "UTF-8")

        # Load into environment
        context.env.load_prompt_object(path)

        "Created prompt object '#{cap_name}' with capabilities: #{capabilities.join(', ')}. It's now available."
      end

      def create_primitive(message, context)
        cap_name = message[:name] || message["name"]
        description = message[:description] || message["description"]
        params_schema = message[:parameters_schema] || message["parameters_schema"] || {}
        ruby_code = message[:ruby_code] || message["ruby_code"]

        unless ruby_code
          return "Error: ruby_code is required for primitives"
        end

        # Generate the Ruby class
        class_name = cap_name.split('_').map(&:capitalize).join

        ruby_content = <<~RUBY
          # frozen_string_literal: true
          # Auto-generated primitive: #{cap_name}

          module PromptObjects
            module Primitives
              class #{class_name} < Primitive
                def name
                  "#{cap_name}"
                end

                def description
                  "#{description.gsub('"', '\\"')}"
                end

                def parameters
                  #{params_schema.inspect}
                end

                def receive(message, context:)
                  #{ruby_code.gsub(/^/, '      ').strip}
                end
              end
            end
          end
        RUBY

        # Write to primitives directory (uses env.primitives_dir for sandbox support)
        FileUtils.mkdir_p(context.env.primitives_dir)
        path = File.join(context.env.primitives_dir, "#{cap_name}.rb")
        File.write(path, ruby_content, encoding: "UTF-8")

        # Load and register
        begin
          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          context.env.registry.register(klass.new)
          "Created primitive '#{cap_name}'. It's now available. File: #{path}"
        rescue SyntaxError => e
          File.delete(path) if File.exist?(path)
          "Error: Invalid Ruby syntax - #{e.message}"
        rescue StandardError => e
          File.delete(path) if File.exist?(path)
          "Error creating primitive: #{e.message}"
        end
      end
    end
  end
end
