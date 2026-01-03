# frozen_string_literal: true

require "bubbletea"

require_relative "styles"
require_relative "messages"
require_relative "models/capability_bar"
require_relative "models/message_log"
require_relative "models/conversation"
require_relative "models/input"

module PromptObjects
  module UI
    # Main TUI application using Bubble Tea
    class App
      include Bubbletea::Model

      attr_reader :env, :active_po, :width, :height

      def initialize(objects_dir: "objects", primitives_dir: nil)
        @objects_dir = objects_dir
        @primitives_dir = primitives_dir
        @env = nil
        @active_po = nil
        @context = nil

        # Sub-models
        @capability_bar = nil
        @message_log = nil
        @conversation = nil
        @input = nil

        # UI state
        @width = 80
        @height = 24
        @show_message_log = true
        @show_help = false
        @modal = nil
        @error = nil
      end

      def init
        # Initialize the environment
        @env = Environment.new(
          objects_dir: @objects_dir,
          primitives_dir: @primitives_dir
        )
        @context = @env.context

        # Load all prompt objects from directory
        load_all_objects

        # Initialize sub-models
        @capability_bar = Models::CapabilityBar.new(registry: @env.registry)
        @message_log = Models::MessageLog.new(bus: @env.bus)
        @conversation = Models::Conversation.new
        @input = Models::Input.new

        # Subscribe to message bus for real-time updates
        @env.bus.subscribe do |entry|
          # This will be called when messages are published
          # In a real async setup, we'd send a message to the update loop
        end

        # Activate the first PO if available
        pos = @env.registry.prompt_objects
        if pos.any?
          @active_po = pos.first
          @capability_bar.select(@active_po.name)
          @conversation.set_po(@active_po)
          @context.current_capability = @active_po.name
        end

        [self, nil]
      end

      def update(msg)
        case msg
        when Bubbletea::KeyMessage
          handle_key(msg)
        when Bubbletea::WindowSizeMessage
          handle_resize(msg)
        when Messages::SelectPO
          handle_select_po(msg.name)
        when Messages::ActivatePO
          handle_activate_po(msg.name)
        when Messages::InputSubmit
          handle_input_submit(msg.text)
        when Messages::TogglePanel
          handle_toggle_panel(msg.panel)
        when Messages::OpenModal
          @modal = { type: msg.modal, data: msg.data }
          [self, nil]
        when Messages::CloseModal
          @modal = nil
          [self, nil]
        when Messages::ErrorOccurred
          @error = msg.message
          [self, nil]
        else
          [self, nil]
        end
      end

      def view
        return "" if @width == 0 || @height == 0

        lines = []

        # Header
        lines << render_header

        # Capability bar
        lines << @capability_bar.view(@width)
        lines << ""

        # Main content area
        content_height = calculate_content_height
        main_content = render_main_content(content_height)
        lines.concat(main_content)

        # Input
        lines << ""
        lines << @input.view(@width)

        # Status bar
        lines << render_status_bar

        # Modal overlay (if any)
        output = lines.join("\n")
        output = render_modal_overlay(output) if @modal

        output
      end

      # Class method to run the app
      def self.run(objects_dir: "objects", primitives_dir: nil)
        app = new(objects_dir: objects_dir, primitives_dir: primitives_dir)
        Bubbletea.run(app, alt_screen: true)
      end

      private

      def load_all_objects
        dir = @objects_dir
        return unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "*.md")).each do |path|
          begin
            @env.load_prompt_object(path)
          rescue StandardError => e
            # Skip invalid objects
          end
        end

        # Load dependencies for each
        @env.registry.prompt_objects.each do |po|
          @env.load_dependencies(po)
        end
      end

      def handle_key(msg)
        # Global keys (when no modal)
        return handle_modal_key(msg) if @modal

        char = msg.char.to_s

        # Always handle these regardless of input state
        case
        when msg.ctrl? && char == "c"
          return [self, Bubbletea.quit]
        when msg.esc?
          # Escape clears input or quits if empty
          if @input.empty?
            return [self, Bubbletea.quit]
          else
            @input.clear
            return [self, nil]
          end
        end

        # Arrow keys always work for navigation
        case
        when msg.left?
          @capability_bar.prev
          select_current_po
          return [self, nil]
        when msg.right?
          @capability_bar.next
          select_current_po
          return [self, nil]
        when msg.enter?
          if @input.empty?
            # Enter with empty input - no action
            return [self, nil]
          else
            # Enter with text sends message
            text = @input.submit
            return handle_input_submit(text)
          end
        end

        # Single-letter shortcuts only when input is empty
        if @input.empty?
          case char
          when "q"
            return [self, Bubbletea.quit]
          when "?"
            @show_help = !@show_help
            return [self, nil]
          when "m"
            @show_message_log = !@show_message_log
            return [self, nil]
          when "i"
            if @active_po
              @modal = { type: :inspector, data: @active_po }
            end
            return [self, nil]
          when "e"
            if @active_po
              @modal = { type: :editor, data: @active_po }
            end
            return [self, nil]
          end
        end

        # Everything else goes to input
        @input.handle_key(msg)
        [self, nil]
      end

      def handle_modal_key(msg)
        char = msg.char.to_s

        case
        when msg.esc?
          @modal = nil
          [self, nil]
        when char == "q"
          @modal = nil
          [self, nil]
        else
          # TODO: Delegate to modal
          [self, nil]
        end
      end

      def handle_resize(msg)
        @width = msg.width
        @height = msg.height
        @capability_bar.width = @width
        @message_log.width = @width
        @conversation.width = @width
        @conversation.height = calculate_content_height
        [self, nil]
      end

      def handle_select_po(name)
        po = @env.registry.get(name)
        return [self, nil] unless po.is_a?(PromptObject)

        @active_po = po
        @capability_bar.select(name)
        @conversation.set_po(po)
        @context.current_capability = po.name
        [self, nil]
      end

      def handle_activate_po(name)
        handle_select_po(name)
      end

      def select_current_po
        name = @capability_bar.selected_name
        return unless name

        po = @env.registry.get(name)
        return unless po.is_a?(PromptObject)

        @active_po = po
        @conversation.set_po(po)
        @context.current_capability = po.name
      end

      def handle_input_submit(text)
        return [self, nil] if text.nil? || text.empty?
        return [self, nil] unless @active_po

        # Log to message bus
        @env.bus.publish(from: "human", to: @active_po.name, message: text)

        # Call the PO
        begin
          @active_po.state = :working
          response = @active_po.receive(text, context: @context)
          @active_po.state = :idle

          # Log response
          @env.bus.publish(from: @active_po.name, to: "human", message: response)

          # Update conversation view
          @conversation.set_po(@active_po)
        rescue StandardError => e
          @error = e.message
          @active_po.state = :idle
        end

        [self, nil]
      end

      def handle_toggle_panel(panel)
        case panel
        when :message_log
          @show_message_log = !@show_message_log
        when :help
          @show_help = !@show_help
        end
        [self, nil]
      end

      def calculate_content_height
        # Header (1) + cap bar (3) + blank (1) + input (1) + status (1) = 7
        available = @height - 7
        available = [available, 5].max
        available
      end

      def render_header
        title = Styles.panel_title.render("PromptObjects")
        sandbox = @primitives_dir ? " [SANDBOX]" : ""
        "#{title}#{sandbox}"
      end

      def render_main_content(height)
        lines = []

        if @show_message_log
          # Split: conversation (60%) | message log (40%)
          conv_width = (@width * 0.6).to_i - 2
          log_width = @width - conv_width - 3

          conv_lines = @conversation.view_lines(conv_width, height)
          log_lines = @message_log.view_lines(log_width, height)

          height.times do |i|
            conv = conv_lines[i] || ""
            log = log_lines[i] || ""
            lines << "#{conv.ljust(conv_width)} | #{log}"
          end
        else
          # Full width conversation
          lines = @conversation.view_lines(@width - 2, height)
        end

        lines
      end

      def render_status_bar
        parts = []
        parts << Styles.help_key.render("Esc") + " quit/clear"
        parts << Styles.help_key.render("Enter") + " send"
        parts << Styles.help_key.render("<-/->") + " switch PO"

        if @input.empty?
          parts << Styles.help_key.render("m") + " messages"
          parts << Styles.help_key.render("i") + " inspect"
        end

        status = parts.join("  ")

        if @error
          status = Styles.error.render("Error: #{@error}")
        end

        Styles.status_bar.render(status)
      end

      def render_modal_overlay(base)
        return base unless @modal

        # For now, just append modal info
        # TODO: Proper overlay rendering
        case @modal[:type]
        when :inspector
          po = @modal[:data]
          modal_content = render_inspector_modal(po)
          "#{base}\n\n#{modal_content}"
        when :editor
          po = @modal[:data]
          "#{base}\n\n[Editor for #{po.name} - Press ESC to close]"
        else
          base
        end
      end

      def render_inspector_modal(po)
        lines = []
        lines << Styles.modal_title.render("INSPECT: #{po.name}")
        lines << ""
        lines << Styles.section_header.render("Description")
        lines << po.description
        lines << ""
        lines << Styles.section_header.render("Capabilities")

        caps = po.config["capabilities"] || []
        universal = UNIVERSAL_CAPABILITIES

        lines << "  Universal: #{universal.join(', ')}"
        lines << "  Declared:  #{caps.empty? ? '(none)' : caps.join(', ')}"
        lines << ""
        lines << "[ESC] Close  [p] View Prompt"

        lines.join("\n")
      end
    end
  end
end
