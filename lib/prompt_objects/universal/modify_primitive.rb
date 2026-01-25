# frozen_string_literal: true

require "fileutils"

module PromptObjects
  module Universal
    # Universal capability to modify existing primitives.
    # Allows POs to fix or improve their primitives.
    class ModifyPrimitive < Primitives::Base
      # Stdlib primitives cannot be modified
      STDLIB_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      description "Modify an existing primitive's code. Only custom (environment) primitives can be modified, not stdlib."
      param :name, desc: "Name of the primitive to modify"
      param :code, desc: "New Ruby code for the primitive's execute method"
      param :new_description, desc: "Optional: Update the description"
      param :parameters_schema, desc: "Optional: Update the parameters schema (JSON)"
      param :reason, desc: "Brief explanation of why this change is needed"

      def execute(name:, code:, new_description: nil, parameters_schema: nil, reason: nil)
        prim_name = name
        reason ||= "Updated primitive"

        # Find the primitive
        primitive = registry.get(prim_name)
        unless primitive
          return { error: "Primitive '#{prim_name}' not found." }
        end

        unless ruby_llm_tool_class?(primitive)
          return { error: "'#{prim_name}' is not a primitive." }
        end

        # Check if it's a stdlib primitive
        if STDLIB_PRIMITIVES.include?(prim_name)
          return { error: "Cannot modify stdlib primitive '#{prim_name}'. Stdlib primitives are built into the framework." }
        end

        # Check if it's a universal capability
        if universal_primitive?(primitive)
          return { error: "Cannot modify universal capability '#{prim_name}'." }
        end

        # Find the primitive file
        path = File.join(environment.primitives_dir, "#{prim_name}.rb")
        unless File.exist?(path)
          return { error: "Cannot find primitive file at #{path}. Only custom primitives can be modified." }
        end

        # Validate code syntax
        syntax_error = validate_syntax(code)
        return { error: "Invalid Ruby syntax - #{syntax_error}" } if syntax_error

        # Parse parameters_schema if string
        params_schema = if parameters_schema.is_a?(String)
                          JSON.parse(parameters_schema) rescue nil
                        else
                          parameters_schema
                        end

        # Get current description if not provided
        desc = new_description || (primitive.respond_to?(:description) ? primitive.description : prim_name)

        # Generate updated Ruby class
        class_name = prim_name.split("_").map(&:capitalize).join
        ruby_content = generate_ruby_class(class_name, prim_name, desc, params_schema, code)

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

          # Re-register with the class
          registry.register(klass)

          log("Modified primitive '#{prim_name}': #{reason}")

          "Modified primitive '#{prim_name}'. Changes saved to #{path}."
        rescue SyntaxError => e
          { error: "Invalid Ruby syntax in generated code - #{e.message}" }
        rescue StandardError => e
          { error: "Error reloading primitive: #{e.message}" }
        end
      end

      private

      def ruby_llm_tool_class?(cap)
        cap.is_a?(Class) && defined?(RubyLLM::Tool) && cap < RubyLLM::Tool
      end

      def universal_primitive?(primitive)
        if primitive.is_a?(Class)
          primitive.name&.start_with?("PromptObjects::Universal")
        else
          primitive.class.name&.start_with?("PromptObjects::Universal")
        end
      end

      def validate_syntax(code)
        eval("proc { #{code} }")
        nil
      rescue SyntaxError => e
        e.message.sub(/^\(eval\):\d+: /, "")
      rescue StandardError
        nil
      end

      def generate_ruby_class(class_name, prim_name, desc, params_schema, code)
        escaped_desc = desc.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

        # Build param declarations from schema
        param_lines = []
        if params_schema && params_schema["properties"]
          params_schema["properties"].each do |prop_name, prop_def|
            desc_str = (prop_def["description"] || prop_name).gsub('"', '\\"')
            param_lines << "      param :#{prop_name}, desc: \"#{desc_str}\""
          end
        end

        # Build execute method signature
        param_names = params_schema&.dig("properties")&.keys || []
        required_params = params_schema&.dig("required") || []

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
          # Modified at #{Time.now.iso8601}

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
    end
  end
end
