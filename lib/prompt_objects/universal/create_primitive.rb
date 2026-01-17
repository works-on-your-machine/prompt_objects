# frozen_string_literal: true

require "fileutils"

module PromptObjects
  module Universal
    # Universal capability to create new primitives (deterministic Ruby code).
    # This enables POs to create their own tools at runtime.
    class CreatePrimitive < Primitive
      def name
        "create_primitive"
      end

      def description
        "Create a new primitive (deterministic Ruby tool). The primitive will be saved to the environment and added to your capabilities."
      end

      def parameters
        {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Name for the primitive (lowercase, underscores allowed, e.g., 'parse_json')"
            },
            description: {
              type: "string",
              description: "Brief description of what this primitive does"
            },
            code: {
              type: "string",
              description: "Ruby code for the primitive's receive method. Has access to 'message' (Hash with parameters) and 'context'. Should return a String result."
            },
            parameters_schema: {
              type: "object",
              description: "Optional JSON Schema for the parameters this primitive accepts"
            }
          },
          required: ["name", "description", "code"]
        }
      end

      def receive(message, context:)
        prim_name = message[:name] || message["name"]
        description = message[:description] || message["description"]
        code = message[:code] || message["code"]
        params_schema = message[:parameters_schema] || message["parameters_schema"] || default_params_schema

        # Validate name
        unless prim_name && prim_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return "Error: Name must be lowercase letters, numbers, and underscores, starting with a letter."
        end

        # Check if already exists
        if context.env.registry.exists?(prim_name)
          return "Error: A capability named '#{prim_name}' already exists. Use modify_primitive to update it."
        end

        # Validate code syntax
        syntax_error = validate_syntax(code)
        return "Error: Invalid Ruby syntax - #{syntax_error}" if syntax_error

        # Generate the Ruby class
        class_name = prim_name.split("_").map(&:capitalize).join
        ruby_content = generate_ruby_class(class_name, prim_name, description, params_schema, code)

        # Write to primitives directory
        FileUtils.mkdir_p(context.env.primitives_dir)
        path = File.join(context.env.primitives_dir, "#{prim_name}.rb")
        File.write(path, ruby_content, encoding: "UTF-8")

        # Load and register
        begin
          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          context.env.registry.register(klass.new)
        rescue SyntaxError => e
          File.delete(path) if File.exist?(path)
          return "Error: Invalid Ruby syntax in generated code - #{e.message}"
        rescue StandardError => e
          File.delete(path) if File.exist?(path)
          return "Error creating primitive: #{e.message}"
        end

        # Auto-add to the creating PO
        added_msg = add_to_caller(prim_name, context)

        result = "Created primitive '#{prim_name}' at #{path}."
        result += " #{added_msg}" if added_msg
        result
      end

      private

      def default_params_schema
        {
          type: "object",
          properties: {},
          required: []
        }
      end

      def validate_syntax(code)
        # Try to parse the code to check for syntax errors
        eval("proc { #{code} }")
        nil
      rescue SyntaxError => e
        e.message.sub(/^\(eval\):\d+: /, "")
      rescue StandardError
        nil # Other errors are OK at this stage
      end

      def generate_ruby_class(class_name, prim_name, description, params_schema, code)
        # Escape description for string literal
        escaped_desc = description.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

        <<~RUBY
          # frozen_string_literal: true
          # Auto-generated primitive: #{prim_name}
          # Created by PO at #{Time.now.iso8601}

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

      def add_to_caller(prim_name, context)
        caller_name = context.calling_po
        return nil unless caller_name

        caller_po = context.env.registry.get(caller_name)
        return nil unless caller_po.is_a?(PromptObject)

        caller_po.config["capabilities"] ||= []
        unless caller_po.config["capabilities"].include?(prim_name)
          caller_po.config["capabilities"] << prim_name
          saved = caller_po.save ? " and saved to file" : ""

          # Notify for real-time UI update
          context.env.notify_po_modified(caller_po)

          return "Added '#{prim_name}' to your capabilities#{saved}."
        end

        nil
      end
    end
  end
end
