# frozen_string_literal: true

require "fileutils"

module PromptObjects
  module Universal
    # Universal capability to request a primitive from the human.
    # Similar to ask_human but specifically for requesting new tools.
    # The human can approve, modify, or reject the request.
    class RequestPrimitive < Primitives::Base
      description "Request a new primitive from the human. Use this when you need a tool that doesn't exist. The human can approve and create it, or reject the request."
      param :name, desc: "Suggested name for the primitive (lowercase, underscores)"
      param :primitive_description, desc: "What this primitive should do"
      param :reason, desc: "Why you need this primitive"
      param :suggested_code, desc: "Optional: Your suggested Ruby implementation for the execute method"
      param :parameters_schema, desc: "Optional: Suggested JSON Schema for parameters"

      def execute(name:, primitive_description:, reason:, suggested_code: nil, parameters_schema: nil)
        prim_name = name

        # Validate name format
        unless prim_name && prim_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return { error: "Name must be lowercase letters, numbers, and underscores, starting with a letter." }
        end

        # Check if already exists
        if registry.exists?(prim_name)
          return { error: "A capability named '#{prim_name}' already exists." }
        end

        # Parse parameters_schema if string
        params_schema = if parameters_schema.is_a?(String)
                          JSON.parse(parameters_schema) rescue nil
                        else
                          parameters_schema
                        end

        # In TUI mode, use the human queue
        if context&.tui_mode && human_queue
          return receive_tui(prim_name, primitive_description, reason, suggested_code, params_schema)
        end

        # REPL mode - use stdin directly
        receive_repl(prim_name, primitive_description, reason, suggested_code, params_schema)
      end

      private

      def receive_tui(prim_name, description, reason, suggested_code, params_schema)
        # Build the question with all details
        question = build_request_question(prim_name, description, reason, suggested_code)

        # Queue the request
        request = human_queue.enqueue(
          capability: current_capability,
          question: question,
          options: ["approve", "reject"]
        )

        # Log to message bus
        log("[primitive request] #{prim_name}: #{description}", to: "human")

        # Wait for response
        response = request.wait_for_response

        # Handle the response
        handle_response(response, prim_name, description, suggested_code, params_schema)
      end

      def receive_repl(prim_name, description, reason, suggested_code, params_schema)
        puts <<~PROMPT

          ┌─ Primitive Request ─────────────────────────────────────────┐
          │
          │  From: #{context&.calling_po || current_capability}
          │  Requested: #{prim_name}
          │
          │  Description: #{description}
          │
          │  Reason: #{reason}
          │
        PROMPT

        if suggested_code
          puts "│  Suggested Code:"
          suggested_code.lines.each { |line| puts "│    #{line}" }
          puts "│"
        end

        puts <<~CHOICES
          ├─────────────────────────────────────────────────────────────┤
          │  [a] Approve (use suggested code)
          │  [e] Edit (provide different code)
          │  [r] Reject
          └─────────────────────────────────────────────────────────────┘
        CHOICES
        print "Your choice: "

        choice = $stdin.gets&.chomp&.downcase

        case choice
        when "a", "approve"
          if suggested_code
            create_and_register(prim_name, description, suggested_code, params_schema)
          else
            puts "No suggested code provided. Please enter the code (end with 'END' on its own line):"
            code = read_multiline_input
            create_and_register(prim_name, description, code, params_schema)
          end
        when "e", "edit"
          puts "Enter the Ruby code for the execute method (end with 'END' on its own line):"
          code = read_multiline_input
          create_and_register(prim_name, description, code, params_schema)
        when "r", "reject"
          "Request rejected by human."
        else
          "Request deferred."
        end
      end

      def build_request_question(prim_name, description, reason, suggested_code)
        lines = []
        lines << "**Primitive Request: #{prim_name}**"
        lines << ""
        lines << "**Description:** #{description}"
        lines << ""
        lines << "**Reason:** #{reason}"

        if suggested_code
          lines << ""
          lines << "**Suggested Code:**"
          lines << "```ruby"
          lines << suggested_code
          lines << "```"
        end

        lines.join("\n")
      end

      def handle_response(response, prim_name, description, suggested_code, params_schema)
        case response.to_s.downcase
        when "approve", "approved", "yes", "y"
          if suggested_code
            create_and_register(prim_name, description, suggested_code, params_schema)
          else
            "Request approved but no code provided. Human should create the primitive manually."
          end
        when "reject", "rejected", "no", "n"
          "Request rejected by human."
        else
          # Treat anything else as custom code provided by human
          if response && !response.strip.empty?
            create_and_register(prim_name, description, response, params_schema)
          else
            "Request deferred."
          end
        end
      end

      def create_and_register(prim_name, description, code, params_schema)
        params_schema ||= { "type" => "object", "properties" => {} }

        # Validate syntax
        begin
          eval("proc { #{code} }")
        rescue SyntaxError => e
          return { error: "Invalid Ruby syntax - #{e.message}" }
        end

        # Generate and write the file
        class_name = prim_name.split("_").map(&:capitalize).join
        ruby_content = generate_ruby_class(class_name, prim_name, description, params_schema, code)

        FileUtils.mkdir_p(environment.primitives_dir)
        path = File.join(environment.primitives_dir, "#{prim_name}.rb")
        File.write(path, ruby_content, encoding: "UTF-8")

        # Load and register
        begin
          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          registry.register(klass)
        rescue StandardError => e
          File.delete(path) if File.exist?(path)
          return { error: "Error creating primitive: #{e.message}" }
        end

        # Auto-add to the requesting PO
        saved = false
        if context&.calling_po
          caller_po = registry.get(context.calling_po)
          if caller_po.is_a?(PromptObject)
            caller_po.config["capabilities"] ||= []
            unless caller_po.config["capabilities"].include?(prim_name)
              caller_po.config["capabilities"] << prim_name
              saved = caller_po.save
              environment&.notify_po_modified(caller_po)
            end
          end
        end

        # Log to bus
        log("[approved] Created primitive '#{prim_name}'", to: current_capability)

        save_msg = saved ? " and saved to file" : ""
        "Primitive '#{prim_name}' created and added to your capabilities#{save_msg}."
      end

      def generate_ruby_class(class_name, prim_name, description, params_schema, code)
        escaped_desc = description.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

        # Build param declarations from schema
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
          # Requested primitive: #{prim_name}
          # Created at #{Time.now.iso8601}

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

      def read_multiline_input
        lines = []
        loop do
          line = $stdin.gets
          break if line.nil? || line.strip == "END"

          lines << line
        end
        lines.join
      end
    end
  end
end
