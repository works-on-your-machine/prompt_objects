# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to request a primitive from the human.
    # Similar to ask_human but specifically for requesting new tools.
    # The human can approve, modify, or reject the request.
    class RequestPrimitive < Primitive
      def name
        "request_primitive"
      end

      def description
        "Request a new primitive from the human. Use this when you need a tool that doesn't exist. The human can approve and create it, or reject the request."
      end

      def parameters
        {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Suggested name for the primitive (lowercase, underscores)"
            },
            description: {
              type: "string",
              description: "What this primitive should do"
            },
            reason: {
              type: "string",
              description: "Why you need this primitive"
            },
            suggested_code: {
              type: "string",
              description: "Optional: Your suggested Ruby implementation for the receive method"
            },
            parameters_schema: {
              type: "object",
              description: "Optional: Suggested JSON Schema for parameters"
            }
          },
          required: ["name", "description", "reason"]
        }
      end

      def receive(message, context:)
        prim_name = message[:name] || message["name"]
        description = message[:description] || message["description"]
        reason = message[:reason] || message["reason"]
        suggested_code = message[:suggested_code] || message["suggested_code"]
        params_schema = message[:parameters_schema] || message["parameters_schema"]

        # Validate name format
        unless prim_name && prim_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return "Error: Name must be lowercase letters, numbers, and underscores, starting with a letter."
        end

        # Check if already exists
        if context.env.registry.exists?(prim_name)
          return "Error: A capability named '#{prim_name}' already exists."
        end

        # In TUI mode, use the human queue
        if context.tui_mode && context.human_queue
          return receive_tui(prim_name, description, reason, suggested_code, params_schema, context)
        end

        # REPL mode - use stdin directly
        receive_repl(prim_name, description, reason, suggested_code, params_schema, context)
      end

      private

      def receive_tui(prim_name, description, reason, suggested_code, params_schema, context)
        # Build the question with all details
        question = build_request_question(prim_name, description, reason, suggested_code)

        # Queue the request
        request = context.human_queue.enqueue(
          capability: context.current_capability,
          question: question,
          options: ["approve", "reject"]
        )

        # Log to message bus
        context.bus.publish(
          from: context.current_capability,
          to: "human",
          message: "[primitive request] #{prim_name}: #{description}"
        )

        # Wait for response
        response = request.wait_for_response

        # Handle the response
        handle_response(response, prim_name, description, suggested_code, params_schema, context)
      end

      def receive_repl(prim_name, description, reason, suggested_code, params_schema, context)
        puts
        puts "┌─ Primitive Request ─────────────────────────────────────────┐"
        puts "│"
        puts "│  From: #{context.calling_po || context.current_capability}"
        puts "│  Requested: #{prim_name}"
        puts "│"
        puts "│  Description: #{description}"
        puts "│"
        puts "│  Reason: #{reason}"
        puts "│"

        if suggested_code
          puts "│  Suggested Code:"
          suggested_code.lines.each { |line| puts "│    #{line}" }
          puts "│"
        end

        puts "├─────────────────────────────────────────────────────────────┤"
        puts "│  [a] Approve (use suggested code)"
        puts "│  [e] Edit (provide different code)"
        puts "│  [r] Reject"
        puts "└─────────────────────────────────────────────────────────────┘"
        print "Your choice: "

        choice = $stdin.gets&.chomp&.downcase

        case choice
        when "a", "approve"
          if suggested_code
            create_and_register(prim_name, description, suggested_code, params_schema, context)
          else
            puts "No suggested code provided. Please enter the code (end with 'END' on its own line):"
            code = read_multiline_input
            create_and_register(prim_name, description, code, params_schema, context)
          end
        when "e", "edit"
          puts "Enter the Ruby code for the receive method (end with 'END' on its own line):"
          code = read_multiline_input
          create_and_register(prim_name, description, code, params_schema, context)
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

      def handle_response(response, prim_name, description, suggested_code, params_schema, context)
        case response.to_s.downcase
        when "approve", "approved", "yes", "y"
          if suggested_code
            create_and_register(prim_name, description, suggested_code, params_schema, context)
          else
            "Request approved but no code provided. Human should create the primitive manually."
          end
        when "reject", "rejected", "no", "n"
          "Request rejected by human."
        else
          # Treat anything else as custom code provided by human
          if response && !response.strip.empty?
            create_and_register(prim_name, description, response, params_schema, context)
          else
            "Request deferred."
          end
        end
      end

      def create_and_register(prim_name, description, code, params_schema, context)
        params_schema ||= { type: "object", properties: {}, required: [] }

        # Validate syntax
        begin
          eval("proc { #{code} }")
        rescue SyntaxError => e
          return "Error: Invalid Ruby syntax - #{e.message}"
        end

        # Generate and write the file
        class_name = prim_name.split("_").map(&:capitalize).join
        ruby_content = generate_ruby_class(class_name, prim_name, description, params_schema, code)

        FileUtils.mkdir_p(context.env.primitives_dir)
        path = File.join(context.env.primitives_dir, "#{prim_name}.rb")
        File.write(path, ruby_content, encoding: "UTF-8")

        # Load and register
        begin
          load(path)
          klass = PromptObjects::Primitives.const_get(class_name)
          context.env.registry.register(klass.new)
        rescue StandardError => e
          File.delete(path) if File.exist?(path)
          return "Error creating primitive: #{e.message}"
        end

        # Auto-add to the requesting PO
        saved = false
        if context.calling_po
          caller_po = context.env.registry.get(context.calling_po)
          if caller_po.is_a?(PromptObject)
            caller_po.config["capabilities"] ||= []
            unless caller_po.config["capabilities"].include?(prim_name)
              caller_po.config["capabilities"] << prim_name
              saved = caller_po.save
            end
          end
        end

        # Log to bus
        context.bus.publish(
          from: "human",
          to: context.current_capability,
          message: "[approved] Created primitive '#{prim_name}'"
        )

        save_msg = saved ? " and saved to file" : ""
        "Primitive '#{prim_name}' created and added to your capabilities#{save_msg}."
      end

      def generate_ruby_class(class_name, prim_name, description, params_schema, code)
        escaped_desc = description.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

        <<~RUBY
          # frozen_string_literal: true
          # Requested primitive: #{prim_name}
          # Created at #{Time.now.iso8601}

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
