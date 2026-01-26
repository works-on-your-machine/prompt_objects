# frozen_string_literal: true

require "fileutils"

module PromptObjects
  module Universal
    # Universal capability to create new primitives (deterministic Ruby code).
    # This enables POs to create their own tools at runtime.
    class CreatePrimitive < Primitives::Base
      description "Create a new primitive (deterministic Ruby tool). The primitive will be saved to the environment and added to your capabilities."
      param :name, desc: "Name for the primitive (lowercase, underscores allowed, e.g., 'parse_json')"
      param :description, desc: "Brief description of what this primitive does"
      param :code, desc: "Ruby code for the primitive's execute method. Has access to keyword parameters defined in schema. Should return a String result."
      param :parameters_schema, desc: "Optional JSON Schema for the parameters this primitive accepts"

      def execute(name:, description:, code:, parameters_schema: nil)
        prim_name = name
        params_schema = parameters_schema || default_params_schema

        # Parse params_schema if string
        params_schema = JSON.parse(params_schema) if params_schema.is_a?(String)

        # Validate name
        unless prim_name && prim_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return { error: "Name must be lowercase letters, numbers, and underscores, starting with a letter." }
        end

        # Check if already exists
        if registry.exists?(prim_name)
          return { error: "A capability named '#{prim_name}' already exists. Use modify_primitive to update it." }
        end

        # Validate code syntax
        syntax_error = validate_syntax(code)
        return { error: "Invalid Ruby syntax - #{syntax_error}" } if syntax_error

        # Generate the Ruby class
        class_name = prim_name.split("_").map(&:capitalize).join
        ruby_content = generate_ruby_class(class_name, prim_name, description, params_schema, code)

        # Write to primitives directory
        FileUtils.mkdir_p(environment.primitives_dir)
        path = File.join(environment.primitives_dir, "#{prim_name}.rb")
        File.write(path, ruby_content, encoding: "UTF-8")

        # Load and register
        begin
          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          registry.register(klass)
        rescue SyntaxError => e
          File.delete(path) if File.exist?(path)
          return { error: "Invalid Ruby syntax in generated code - #{e.message}" }
        rescue StandardError => e
          File.delete(path) if File.exist?(path)
          return { error: "Error creating primitive: #{e.message}" }
        end

        # Auto-add to the calling PO
        added_msg = add_to_caller(prim_name)

        result = "Created primitive '#{prim_name}' at #{path}."
        result += " #{added_msg}" if added_msg
        result
      end

      private

      def default_params_schema
        { "type" => "object", "properties" => {} }
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

      def generate_ruby_class(class_name, prim_name, desc, params_schema, code)
        # Escape description for string literal
        escaped_desc = desc.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

        # Build param declarations
        param_lines = []
        if params_schema["properties"]
          params_schema["properties"].each do |prop_name, prop_def|
            desc_str = (prop_def["description"] || prop_name).gsub('"', '\\"')
            param_lines << "      param :#{prop_name}, desc: \"#{desc_str}\""
          end
        end

        # Build execute method signature
        param_names = params_schema["properties"]&.keys || []
        required_params = params_schema["required"] || []

        exec_params = param_names.map do |p|
          if required_params.include?(p)
            "#{p}:"
          else
            "#{p}: nil"
          end
        end.join(", ")

        <<~RUBY
          # frozen_string_literal: true
          # Auto-generated primitive: #{prim_name}
          # Created by PO at #{Time.now.iso8601}

          module PromptObjects
            module Primitives
              class #{class_name} < Base
                description "#{escaped_desc}"
          #{param_lines.join("\n")}

                def execute(#{exec_params})
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

      def add_to_caller(prim_name)
        caller_name = context&.calling_po
        return nil unless caller_name

        caller_po = registry.get(caller_name)
        return nil unless caller_po.is_a?(PromptObject)

        caller_po.config["capabilities"] ||= []
        unless caller_po.config["capabilities"].include?(prim_name)
          caller_po.config["capabilities"] << prim_name
          saved = caller_po.save ? " and saved to file" : ""
          environment&.notify_po_modified(caller_po)
          return "Added '#{prim_name}' to your capabilities#{saved}."
        end

        nil
      end
    end
  end
end
