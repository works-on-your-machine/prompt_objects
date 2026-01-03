# frozen_string_literal: true

require "bubbletea"

require_relative "styles"
require_relative "messages"
require_relative "models/capability_bar"
require_relative "models/message_log"
require_relative "models/conversation"
require_relative "models/input"
require_relative "models/po_inspector"
require_relative "models/capability_editor"
require_relative "models/notification_panel"
require_relative "models/request_responder"

module PromptObjects
  module UI
    # Main TUI application using Bubble Tea
    class App
      include Bubbletea::Model

      attr_reader :env, :active_po, :width, :height

      # Vim-like modes
      MODE_NORMAL = :normal
      MODE_INSERT = :insert

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
        @mode = MODE_NORMAL
      end

      def init
        # Initialize the environment
        @env = Environment.new(
          objects_dir: @objects_dir,
          primitives_dir: @primitives_dir
        )
        # Create context with TUI mode enabled
        @context = @env.context(tui_mode: true)

        # Load all prompt objects from directory
        load_all_objects

        # Initialize sub-models
        @capability_bar = Models::CapabilityBar.new(
          registry: @env.registry,
          human_queue: @env.human_queue
        )
        @message_log = Models::MessageLog.new(bus: @env.bus)
        @conversation = Models::Conversation.new
        @input = Models::Input.new
        @notification_panel = Models::NotificationPanel.new(human_queue: @env.human_queue)
        @responder = nil  # Set when responding to a request

        # Subscribe to message bus for real-time updates
        @env.bus.subscribe do |entry|
          # This will be called when messages are published
          # In a real async setup, we'd send a message to the update loop
        end

        # Subscribe to human queue for notification updates
        @env.human_queue.subscribe do |event, request|
          # Could send a message to trigger UI update
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
        when Messages::POResponse
          handle_po_response(msg)
        when Messages::ErrorOccurred
          @error = msg.message
          @conversation.clear_pending
          [self, nil]
        else
          [self, nil]
        end
      end

      def handle_po_response(msg)
        # Clear the pending message and update conversation
        @conversation.clear_pending
        @conversation.set_po(@active_po)
        @error = nil
        [self, nil]
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
        lines << @input.view(@width, mode: @mode)

        # Status bar
        lines << render_status_bar

        # Modal overlay (if any)
        output = lines.join("\n")
        output = render_modal_overlay(output) if @modal

        # Notification panel overlay
        output = render_notification_overlay(output) if @notification_panel.visible

        # Responder modal overlay (highest priority)
        output = render_responder_overlay(output) if @responder

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
        char = msg.char.to_s

        # Ctrl+C always quits
        if msg.ctrl? && char == "c"
          return [self, Bubbletea.quit]
        end

        # Handle responder modal first (highest priority)
        return handle_responder_key(msg, char) if @responder

        # Handle notification panel
        return handle_notification_key(msg, char) if @notification_panel.visible

        # Handle other modals
        return handle_modal_key(msg) if @modal

        # Mode-specific handling
        if @mode == MODE_INSERT
          handle_insert_mode(msg, char)
        else
          handle_normal_mode(msg, char)
        end
      end

      def handle_insert_mode(msg, char)
        case
        when msg.esc?
          # Escape returns to normal mode
          @mode = MODE_NORMAL
          [self, nil]
        when msg.enter?
          # Send message and return to normal mode
          text = @input.submit
          @mode = MODE_NORMAL
          handle_input_submit(text)
        when msg.ctrl? && char == "a"
          @input.cursor_home
          [self, nil]
        when msg.ctrl? && char == "e"
          @input.cursor_end
          [self, nil]
        when msg.ctrl? && char == "u"
          @input.clear
          [self, nil]
        when msg.ctrl? && char == "k"
          @input.kill_to_end
          [self, nil]
        when msg.backspace?
          @input.delete_char
          [self, nil]
        when msg.left?
          @input.move_left
          [self, nil]
        when msg.right?
          @input.move_right
          [self, nil]
        when msg.space?
          @input.insert(" ")
          [self, nil]
        when msg.runes? && !char.empty?
          @input.insert(char)
          [self, nil]
        else
          [self, nil]
        end
      end

      def handle_normal_mode(msg, char)
        case
        when msg.esc?
          [self, Bubbletea.quit]
        when char == "i" || msg.enter?
          # Enter insert mode
          @mode = MODE_INSERT
          [self, nil]
        when char == "q"
          [self, Bubbletea.quit]
        when char == "?"
          @show_help = !@show_help
          [self, nil]
        when char == "m"
          @show_message_log = !@show_message_log
          [self, nil]
        when char == "n"
          # Toggle notification panel
          @notification_panel.set_dimensions(@width, @height)
          @notification_panel.toggle
          [self, nil]
        when char == "I"
          # Inspect current PO
          if @active_po
            @inspector = Models::POInspector.new(po: @active_po)
            @inspector.set_dimensions(@width, @height)
            @modal = { type: :inspector, data: @inspector }
          end
          [self, nil]
        when char == "e"
          # Edit current PO capabilities
          if @active_po
            @editor = Models::CapabilityEditor.new(po: @active_po, registry: @env.registry)
            @editor.set_dimensions(@width, @height)
            @modal = { type: :editor, data: @editor }
          end
          [self, nil]
        when msg.left? || char == "h"
          @capability_bar.prev
          select_current_po
          [self, nil]
        when msg.right? || char == "l"
          @capability_bar.next
          select_current_po
          [self, nil]
        else
          [self, nil]
        end
      end

      def handle_modal_key(msg)
        char = msg.char.to_s

        # Handle editor input mode specially
        if @modal && @modal[:type] == :editor && @editor&.input_mode?
          return handle_editor_input_mode(msg, char)
        end

        case
        when msg.esc?
          close_modal
          [self, nil]
        when char == "q"
          close_modal
          [self, nil]
        else
          if @modal && @modal[:type] == :inspector && @inspector
            handle_inspector_key(msg, char)
          elsif @modal && @modal[:type] == :editor && @editor
            handle_editor_key(msg, char)
          end
          [self, nil]
        end
      end

      def handle_inspector_key(msg, char)
        case
        when msg.tab?
          @inspector.next_tab
        when char == "j" || msg.down?
          @inspector.scroll_down
        when char == "k" || msg.up?
          @inspector.scroll_up
        when char == "h" || msg.left?
          @inspector.prev_tab
        when char == "l" || msg.right?
          @inspector.next_tab
        end
      end

      def handle_editor_key(msg, char)
        case
        when msg.tab?
          @editor.next_tab
        when char == "j" || msg.down?
          @editor.move_down
        when char == "k" || msg.up?
          @editor.move_up
        when char == "h" || msg.left?
          @editor.prev_tab
        when char == "l" || msg.right?
          @editor.next_tab
        when msg.space?
          @editor.toggle_selected
        when msg.enter?
          @editor.toggle_selected
        when char == "s"
          @editor.save_changes
        end
      end

      def handle_editor_input_mode(msg, char)
        case
        when msg.esc?
          @editor.exit_input_mode
          [self, nil]
        when msg.enter?
          @editor.exit_input_mode
          [self, nil]
        when msg.backspace?
          @editor.delete_char
          [self, nil]
        when msg.space?
          @editor.insert_char(" ")
          [self, nil]
        when msg.runes? && !char.empty?
          @editor.insert_char(char)
          [self, nil]
        else
          [self, nil]
        end
      end

      def close_modal
        @modal = nil
        @inspector = nil
        @editor = nil
      end

      def handle_notification_key(msg, char)
        case
        when msg.esc?
          @notification_panel.hide
          [self, nil]
        when char == "q"
          @notification_panel.hide
          [self, nil]
        when char == "j" || msg.down?
          @notification_panel.move_down
          [self, nil]
        when char == "k" || msg.up?
          @notification_panel.move_up
          [self, nil]
        when msg.enter?
          # Open responder for selected request
          request = @notification_panel.selected_request
          if request
            @responder = Models::RequestResponder.new(request: request)
            @responder.set_dimensions(@width, @height)
            @notification_panel.hide
          end
          [self, nil]
        else
          [self, nil]
        end
      end

      def handle_responder_key(msg, char)
        # Handle input mode for text responses
        if @responder.input_mode?
          return handle_responder_input_mode(msg, char)
        end

        case
        when msg.esc?
          @responder = nil
          [self, nil]
        when char == "q"
          @responder = nil
          [self, nil]
        when char == "j" || msg.down?
          @responder.move_down
          [self, nil]
        when char == "k" || msg.up?
          @responder.move_up
          [self, nil]
        when msg.enter?
          if @responder.has_options?
            # Submit selected option
            submit_response
          else
            # Enter input mode for text
            @responder.enter_input_mode
          end
          [self, nil]
        else
          [self, nil]
        end
      end

      def handle_responder_input_mode(msg, char)
        case
        when msg.esc?
          @responder.exit_input_mode
          [self, nil]
        when msg.enter?
          # Submit the text response
          if @responder.can_submit?
            submit_response
          end
          [self, nil]
        when msg.backspace?
          @responder.delete_char
          [self, nil]
        when msg.space?
          @responder.insert_char(" ")
          [self, nil]
        when msg.runes? && !char.empty?
          @responder.insert_char(char)
          [self, nil]
        else
          [self, nil]
        end
      end

      def submit_response
        return unless @responder

        request = @responder.request
        value = @responder.response_value

        # Submit to human queue (this will unblock the waiting thread)
        @env.human_queue.respond(request.id, value)

        # Clear responder
        @responder = nil
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

        # Show the message immediately
        @conversation.set_pending_message(text)
        @active_po.state = :working

        # Run LLM call in background thread
        po = @active_po
        context = @context
        env = @env
        conversation = @conversation

        Thread.new do
          begin
            response = po.receive(text, context: context)
            po.state = :idle

            # Log response
            env.bus.publish(from: po.name, to: "human", message: response)

            # Send message to update UI (Bubbletea will pick this up)
            Bubbletea.send_message(Messages::POResponse.new(po_name: po.name, text: response))
          rescue StandardError => e
            Bubbletea.send_message(Messages::ErrorOccurred.new(message: e.message))
            po.state = :idle
          end
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
          conv_width = (@width * 0.6).to_i - 1
          log_width = @width - conv_width - 3

          conv_lines = @conversation.view_lines(conv_width - 4, height - 2)
          log_lines = @message_log.view_lines(log_width - 2, height - 2)

          # Draw conversation box
          conv_title = @active_po ? " #{@active_po.name} " : " Conversation "
          conv_top = Styles.panel_title.render("┌#{conv_title}#{'─' * (conv_width - conv_title.length - 2)}┐")
          log_top = " ┌─ Messages #{'─' * (log_width - 13)}┐"

          lines << "#{conv_top}#{log_top}"

          (height - 2).times do |i|
            conv = conv_lines[i] || ""
            log = log_lines[i] || ""
            # Strip ANSI codes for length calculation
            conv_plain_len = conv.gsub(/\e\[[0-9;]*m/, '').length
            log_plain_len = log.gsub(/\e\[[0-9;]*m/, '').length

            conv_padded = conv + (' ' * [0, conv_width - 4 - conv_plain_len].max)
            log_padded = log + (' ' * [0, log_width - 4 - log_plain_len].max)

            lines << "│ #{conv_padded} │ │ #{log_padded} │"
          end

          conv_bottom = "└#{'─' * (conv_width - 2)}┘"
          log_bottom = " └#{'─' * (log_width - 2)}┘"
          lines << "#{conv_bottom}#{log_bottom}"
        else
          # Full width conversation with box
          conv_width = @width - 2
          conv_lines = @conversation.view_lines(conv_width - 4, height - 2)

          conv_title = @active_po ? " #{@active_po.name} " : " Conversation "
          lines << Styles.panel_title.render("┌#{conv_title}#{'─' * (conv_width - conv_title.length - 2)}┐")

          (height - 2).times do |i|
            conv = conv_lines[i] || ""
            conv_plain_len = conv.gsub(/\e\[[0-9;]*m/, '').length
            conv_padded = conv + (' ' * [0, conv_width - 4 - conv_plain_len].max)
            lines << "│ #{conv_padded} │"
          end

          lines << "└#{'─' * (conv_width - 2)}┘"
        end

        lines
      end

      def render_status_bar
        if @error
          return Styles.error.render("Error: #{@error}")
        end

        if @mode == MODE_INSERT
          parts = [
            Styles.help_key.render("Esc") + " normal mode",
            Styles.help_key.render("Enter") + " send",
            Styles.help_key.render("Ctrl+U") + " clear"
          ]
        else
          # Show notification count if any pending
          pending = @env.human_queue.count
          notif_label = pending > 0 ? "n (#{pending})" : "n"

          parts = [
            Styles.help_key.render("i") + " insert",
            Styles.help_key.render("h/l") + " switch PO",
            Styles.help_key.render(notif_label) + " notifications",
            Styles.help_key.render("I") + " inspect",
            Styles.help_key.render("q") + " quit"
          ]
        end

        Styles.status_bar.render(parts.join("  "))
      end

      def render_modal_overlay(base)
        return base unless @modal

        case @modal[:type]
        when :inspector
          if @inspector
            # Center the modal over the base view
            modal_view = @inspector.view
            center_modal(base, modal_view)
          else
            base
          end
        when :editor
          if @editor
            modal_view = @editor.view
            center_modal(base, modal_view)
          else
            base
          end
        else
          base
        end
      end

      def center_modal(base, modal)
        base_lines = base.split("\n")
        modal_lines = modal.split("\n")

        modal_width = modal_lines.map { |l| l.gsub(/\e\[[0-9;]*m/, '').length }.max || 0
        modal_height = modal_lines.length

        # Calculate offsets to center
        start_row = [(@height - modal_height) / 2, 1].max
        start_col = [(@width - modal_width) / 2, 0].max

        # Overlay modal on base
        result = base_lines.map(&:dup)

        modal_lines.each_with_index do |modal_line, i|
          row = start_row + i
          next if row >= result.length

          # Replace part of the line with modal content
          if start_col > 0
            # Get visible part of base line (accounting for ANSI codes)
            base_visible = result[row].gsub(/\e\[[0-9;]*m/, '')
            prefix = base_visible[0, start_col] || ""
            result[row] = "#{' ' * start_col}#{modal_line}"
          else
            result[row] = modal_line
          end
        end

        result.join("\n")
      end

      def render_notification_overlay(base)
        @notification_panel.set_dimensions(@width, @height)
        modal_view = @notification_panel.view
        center_modal(base, modal_view)
      end

      def render_responder_overlay(base)
        @responder.set_dimensions(@width, @height)
        modal_view = @responder.view
        center_modal(base, modal_view)
      end
    end
  end
end
