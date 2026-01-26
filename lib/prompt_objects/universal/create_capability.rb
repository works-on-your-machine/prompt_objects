# frozen_string_literal: true

require "yaml"
require "fileutils"

module PromptObjects
  module Universal
    # Universal capability to create new capabilities at runtime.
    # Can create both prompt objects (markdown) and primitives (Ruby code).
    # This enables self-modification - the system can create new specialists and tools.
    class CreateCapability < Primitives::Base
      description "Create a new capability. Use type='prompt_object' for LLM-backed specialists, or type='primitive' for deterministic Ruby tools."
      param :type, desc: "Type of capability: 'prompt_object' for LLM specialists, 'primitive' for Ruby tools"
      param :name, desc: "Name for the capability (lowercase, underscores allowed)"
      param :description, desc: "Brief description of what this capability does"
      param :capabilities, desc: "(prompt_object only) Comma-separated list of capabilities this PO can use"
      param :identity, desc: "(prompt_object only) Who is this prompt object? Their personality and role."
      param :behavior, desc: "(prompt_object only) How should this prompt object behave?"
      param :parameters_schema, desc: "(primitive only) JSON Schema for the parameters this primitive accepts"
      param :ruby_code, desc: "(primitive only) Ruby code for the execute method body."

      def execute(type:, name:, description:, capabilities: nil, identity: nil, behavior: nil, parameters_schema: nil, ruby_code: nil)
        cap_name = name

        # Validate name
        unless cap_name && cap_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return { error: "Name must be lowercase letters, numbers, and underscores, starting with a letter." }
        end

        # Check if already exists
        if registry.exists?(cap_name)
          return { error: "A capability named '#{cap_name}' already exists." }
        end

        result = case type.to_s
        when "prompt_object"
          create_prompt_object(cap_name, description, capabilities, identity, behavior)
        when "primitive"
          create_primitive(cap_name, description, parameters_schema, ruby_code)
        else
          return { error: "type must be 'prompt_object' or 'primitive'" }
        end

        # If creation succeeded, add the new capability to the creating PO
        if result.is_a?(String) && !result.start_with?("Error:")
          added_msg = add_to_creator(cap_name)
          result = "#{result} #{added_msg}" if added_msg
        end

        result
      end

      private

      # Add the newly created capability to the PO that created it
      def add_to_creator(cap_name)
        creator_name = context&.calling_po
        return nil unless creator_name

        creator_po = registry.get(creator_name)
        return nil unless creator_po.is_a?(PromptObject)

        # Add to the creator's capabilities if not already present
        creator_po.config["capabilities"] ||= []
        unless creator_po.config["capabilities"].include?(cap_name)
          creator_po.config["capabilities"] << cap_name
          saved = creator_po.save ? " and saved" : ""
          environment&.notify_po_modified(creator_po)
          return "Also added '#{cap_name}' to #{creator_name}'s capabilities#{saved}."
        end

        nil
      end

      def create_prompt_object(cap_name, desc, capabilities, identity, behavior)
        # Parse capabilities if string
        caps_array = if capabilities.is_a?(String)
                       capabilities.split(",").map(&:strip)
                     else
                       capabilities || []
                     end

        identity ||= "You are a helpful assistant."
        behavior ||= "Help the user with their request."

        # Build the markdown content
        frontmatter = {
          "name" => cap_name,
          "description" => desc,
          "capabilities" => caps_array
        }

        body = <<~MARKDOWN
          # #{cap_name.split('_').map(&:capitalize).join(' ')}

          ## Identity

          #{identity}

          ## Behavior

          #{behavior}
        MARKDOWN

        content = "#{frontmatter.to_yaml}---\n\n#{body}"

        # Write to file
        path = File.join(environment.objects_dir, "#{cap_name}.md")
        File.write(path, content, encoding: "UTF-8")

        # Load into environment
        environment.load_prompt_object(path)

        "Created prompt object '#{cap_name}' with capabilities: #{caps_array.join(', ')}. It's now available."
      end

      def create_primitive(cap_name, desc, parameters_schema, ruby_code)
        unless ruby_code
          return { error: "ruby_code is required for primitives" }
        end

        # Parse parameters_schema if string (JSON)
        params_hash = if parameters_schema.is_a?(String)
                        JSON.parse(parameters_schema) rescue {}
                      else
                        parameters_schema || {}
                      end

        # Generate the Ruby class - using new RubyLLM::Tool format
        class_name = cap_name.split('_').map(&:capitalize).join

        # Build param declarations from schema
        param_lines = []
        if params_hash["properties"]
          params_hash["properties"].each do |prop_name, prop_def|
            desc_str = (prop_def["description"] || prop_name).gsub('"', '\\"')
            param_lines << "      param :#{prop_name}, desc: \"#{desc_str}\""
          end
        end

        # Build execute method signature
        param_names = params_hash["properties"]&.keys || []
        required_params = params_hash["required"] || []

        exec_params = param_names.map do |p|
          if required_params.include?(p)
            "#{p}:"
          else
            "#{p}: nil"
          end
        end.join(", ")

        ruby_content = <<~RUBY
          # frozen_string_literal: true
          # Auto-generated primitive: #{cap_name}

          module PromptObjects
            module Primitives
              class #{class_name} < Base
                description "#{desc.gsub('"', '\\"')}"
          #{param_lines.join("\n")}

                def execute(#{exec_params})
                  #{ruby_code.gsub(/^/, '          ').strip}
                end
              end
            end
          end
        RUBY

        # Write to primitives directory
        FileUtils.mkdir_p(environment.primitives_dir)
        path = File.join(environment.primitives_dir, "#{cap_name}.rb")
        File.write(path, ruby_content, encoding: "UTF-8")

        # Load and register
        begin
          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          registry.register(klass)
          "Created primitive '#{cap_name}'. It's now available. File: #{path}"
        rescue SyntaxError => e
          File.delete(path) if File.exist?(path)
          { error: "Invalid Ruby syntax - #{e.message}" }
        rescue StandardError => e
          File.delete(path) if File.exist?(path)
          { error: "Error creating primitive: #{e.message}" }
        end
      end
    end
  end
end
