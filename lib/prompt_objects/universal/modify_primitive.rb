# frozen_string_literal: true

require "fileutils"

module PromptObjects
  module Universal
    # Universal capability to modify existing primitives.
    # Allows POs to fix or improve their primitives.
    class ModifyPrimitive < Primitive
      # Stdlib primitives cannot be modified
      STDLIB_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      def name
        "modify_primitive"
      end

      def description
        "Modify an existing primitive's code. Only custom (environment) primitives can be modified, not stdlib."
      end

      def parameters
        {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Name of the primitive to modify"
            },
            code: {
              type: "string",
              description: "New Ruby code for the primitive's receive method"
            },
            description: {
              type: "string",
              description: "Optional: Update the description"
            },
            parameters_schema: {
              type: "object",
              description: "Optional: Update the parameters schema"
            },
            reason: {
              type: "string",
              description: "Brief explanation of why this change is needed (for commit message)"
            }
          },
          required: ["name", "code"]
        }
      end

      def receive(message, context:)
        prim_name = message[:name] || message["name"]
        new_code = message[:code] || message["code"]
        new_description = message[:description] || message["description"]
        new_params_schema = message[:parameters_schema] || message["parameters_schema"]
        reason = message[:reason] || message["reason"] || "Updated primitive"

        # Find the primitive
        primitive = context.env.registry.get(prim_name)
        unless primitive
          return "Error: Primitive '#{prim_name}' not found."
        end

        unless primitive.is_a?(Primitive)
          return "Error: '#{prim_name}' is not a primitive."
        end

        # Check if it's a stdlib primitive
        if STDLIB_PRIMITIVES.include?(prim_name)
          return "Error: Cannot modify stdlib primitive '#{prim_name}'. Stdlib primitives are built into the framework."
        end

        # Check if it's a universal capability
        if universal_primitive?(primitive)
          return "Error: Cannot modify universal capability '#{prim_name}'."
        end

        # Find the primitive file
        path = File.join(context.env.primitives_dir, "#{prim_name}.rb")
        unless File.exist?(path)
          return "Error: Cannot find primitive file at #{path}. Only custom primitives can be modified."
        end

        # Validate code syntax
        syntax_error = validate_syntax(new_code)
        return "Error: Invalid Ruby syntax - #{syntax_error}" if syntax_error

        # Get current values if not provided
        description = new_description || primitive.description
        params_schema = new_params_schema || primitive.parameters

        # Generate updated Ruby class
        class_name = prim_name.split("_").map(&:capitalize).join
        ruby_content = generate_ruby_class(class_name, prim_name, description, params_schema, new_code)

        # Write the updated file
        File.write(path, ruby_content, encoding: "UTF-8")

        # Reload the primitive
        begin
          # Remove old constant to allow re-definition
          if PromptObjects::Primitives.const_defined?(class_name)
            PromptObjects::Primitives.send(:remove_const, class_name)
          end

          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          new_instance = klass.new

          # Re-register with the new instance
          context.env.registry.register(new_instance)

          # Auto-commit if in environment mode
          if context.env.environment? && context.env.auto_commit
            commit_message = "Modified primitive '#{prim_name}': #{reason}"
            context.env.save(commit_message)
          end

          "Modified primitive '#{prim_name}'. Changes saved to #{path}."
        rescue SyntaxError => e
          "Error: Invalid Ruby syntax in generated code - #{e.message}"
        rescue StandardError => e
          "Error reloading primitive: #{e.message}"
        end
      end

      private

      def universal_primitive?(primitive)
        primitive.class.name&.start_with?("PromptObjects::Universal")
      end

      def validate_syntax(code)
        eval("proc { #{code} }")
        nil
      rescue SyntaxError => e
        e.message.sub(/^\(eval\):\d+: /, "")
      rescue StandardError
        nil
      end

      def generate_ruby_class(class_name, prim_name, description, params_schema, code)
        escaped_desc = description.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

        <<~RUBY
          # frozen_string_literal: true
          # Auto-generated primitive: #{prim_name}
          # Modified at #{Time.now.iso8601}

          module PromptObjects
            module Primitives
              class #{class_name} < Primitive
                def name
                  "#{prim_name}"
                end

                def description
                  "#{escaped_desc}"
                end

                def parameters
                  #{params_schema.inspect}
                end

                def receive(message, context:)
                  #{indent_code(code, 10)}
                end
              end
            end
          end
        RUBY
      end

      def indent_code(code, spaces)
        code.lines.map.with_index do |line, i|
          i.zero? ? line.rstrip : (" " * spaces) + line.rstrip
        end.join("\n")
      end
    end
  end
end
