# frozen_string_literal: true

# Load Charm libraries via charm-native (single Go runtime)
require_relative "../charm"

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
require_relative "models/setup_wizard"
require_relative "models/env_picker"
require_relative "models/session_picker"
require_relative "models/session_explorer"
require_relative "models/dashboard"
require_relative "models/po_detail"
require_relative "models/chat_panel"

module PromptObjects
  module UI
    # Main TUI application using Bubble Tea
    #
    # IMPORTANT: This app uses a single-program architecture with internal screen states.
    # Bubble Tea best practice is to avoid running multiple sequential programs, as this
    # causes terminal state issues. Instead, we manage picker/wizard/main as screens
    # within one program. See: https://github.com/charmbracelet/bubbletea/discussions/484
    class App
      include Bubbletea::Model

      attr_reader :env, :active_po, :width, :height

      # Screen states - single program manages all screens
      SCREEN_PICKER = :picker
      SCREEN_WIZARD = :wizard
      SCREEN_MAIN = :main

      # Sub-screen states within SCREEN_MAIN (dashboard navigation)
      MAIN_SUBSCREEN_DASHBOARD = :dashboard
      MAIN_SUBSCREEN_PO_DETAIL = :po_detail
      MAIN_SUBSCREEN_SESSION_CHAT = :session_chat

      # Vim-like modes (for main screen)
      MODE_NORMAL = :normal
      MODE_INSERT = :insert

      def initialize(objects_dir: nil, primitives_dir: nil, env_path: nil, manager: nil, dev_mode: false)
        @env_path = env_path
        @objects_dir = objects_dir
        @primitives_dir = primitives_dir
        @manager = manager
        @dev_mode = dev_mode
        @env = nil
        @active_po = nil
        @context = nil

        # Screen state
        @screen = nil  # Set in init based on context

        # Sub-screen state for dashboard navigation (within SCREEN_MAIN)
        @main_subscreen = MAIN_SUBSCREEN_DASHBOARD
        @nav_stack = []  # Navigation history for back button
        @selected_po_for_detail = nil  # PO being viewed in detail
        @selected_session_for_chat = nil  # Session being chatted in

        # Sub-models for picker/wizard
        @picker = nil
        @wizard = nil

        # Sub-models for main screen (chat mode - existing)
        @capability_bar = nil
        @message_log = nil
        @conversation = nil
        @input = nil

        # Sub-models for dashboard mode (new)
        @dashboard = nil
        @po_detail = nil
        @chat_panel = nil

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
        # Determine initial screen based on context
        @screen = determine_initial_screen

        case @screen
        when SCREEN_PICKER
          init_picker
        when SCREEN_WIZARD
          init_wizard
        when SCREEN_MAIN
          init_main
        end

        [self, nil]
      end

      private def determine_initial_screen
        # If env_path is provided, go directly to main
        return SCREEN_MAIN if @env_path

        # If dev mode, go directly to main
        return SCREEN_MAIN if @dev_mode

        # If no manager, we're in legacy mode - go to main
        return SCREEN_MAIN unless @manager

        # First run (no environments) - show wizard
        return SCREEN_WIZARD if @manager.first_run?

        # Otherwise show picker
        SCREEN_PICKER
      end

      private def init_picker
        environments = @manager.list_with_manifests
        @picker = Models::EnvPicker.new(environments: environments)
      end

      private def init_wizard
        templates = PromptObjects::CLI.list_templates
        @wizard = Models::SetupWizard.new(
          manager: @manager,
          templates: templates
        )
      end

      private def init_main
        # Initialize the environment
        if @env_path
          @env = Runtime.new(env_path: @env_path)
          @objects_dir = @env.objects_dir
        elsif @dev_mode && @manager
          env_path = @manager.dev_environment_path
          @env = Runtime.new(env_path: env_path)
          @objects_dir = @env.objects_dir
        else
          @env = Runtime.new(
            objects_dir: @objects_dir || "objects",
            primitives_dir: @primitives_dir
          )
          @objects_dir = @env.objects_dir
        end
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

        # Initialize session polling state
        @session_poll_state = {
          last_check: Time.now,
          session_timestamps: {},  # session_id => updated_at
          mcp_active: false
        }

        # Start session polling thread for live updates
        start_session_polling if @env.session_store

        # Initialize dashboard as the default view
        init_dashboard

        # Activate the first PO if available
        pos = @env.registry.prompt_objects
        if pos.any?
          @active_po = pos.first
          @capability_bar.select(@active_po.name)
          @conversation.set_po(@active_po)
          @context.current_capability = @active_po.name
        end
      end

      def update(msg)
        # Handle window size for all screens
        if msg.is_a?(Bubbletea::WindowSizeMessage)
          @width = msg.width
          @height = msg.height
          # Also pass to picker/wizard if active
          @picker&.instance_variable_set(:@width, @width)
          @picker&.instance_variable_set(:@height, @height)
          @wizard&.instance_variable_set(:@width, @width)
          @wizard&.instance_variable_set(:@height, @height)
        end

        # Route based on current screen
        case @screen
        when SCREEN_PICKER
          update_picker(msg)
        when SCREEN_WIZARD
          update_wizard(msg)
        when SCREEN_MAIN
          update_main(msg)
        else
          [self, nil]
        end
      end

      private def update_picker(msg)
        return [self, nil] unless @picker

        # Let picker handle the message
        @picker.update(msg)

        # Check if picker is done
        if @picker.cancelled?
          return [self, Bubbletea.quit]
        elsif @picker.wants_new_env?
          # Transition to wizard
          @screen = SCREEN_WIZARD
          init_wizard
          return [self, nil]
        elsif @picker.done?
          # Transition to main with selected environment
          @env_path = @manager.environment_path(@picker.selected_env)
          @screen = SCREEN_MAIN
          init_main
          return [self, nil]
        end

        [self, nil]
      end

      private def update_wizard(msg)
        return [self, nil] unless @wizard

        # Let wizard handle the message
        @wizard.update(msg)

        # Check if wizard is done
        if @wizard.done?
          # Transition to main with created environment
          @env_path = @wizard.env_path
          @screen = SCREEN_MAIN
          init_main
          return [self, nil]
        end

        # Check for cancellation (Ctrl+C handled in wizard, Esc on welcome)
        # The wizard itself returns quit command on cancel

        [self, nil]
      end

      private def update_main(msg)
        # Handle window resize for all sub-screens
        if msg.is_a?(Bubbletea::WindowSizeMessage)
          return handle_resize(msg)
        end

        # Handle navigation messages
        case msg
        when Messages::NavigateTo
          navigate_to(msg.screen, msg.data || {})
          return [self, nil]
        when Messages::NavigateBack
          navigate_back
          return [self, nil]
        end

        # Route to sub-screen handler based on current state
        case @main_subscreen
        when MAIN_SUBSCREEN_DASHBOARD
          update_dashboard(msg)
        when MAIN_SUBSCREEN_PO_DETAIL
          update_po_detail(msg)
        else  # MAIN_SUBSCREEN_SESSION_CHAT
          update_session_chat(msg)
        end
      end

      private def update_dashboard(msg)
        return [self, nil] unless msg.is_a?(Bubbletea::KeyMessage)

        char = msg.char.to_s

        # Ctrl+C always quits
        if msg.ctrl? && char == "c"
          return [self, Bubbletea.quit]
        end

        # If chat panel is open, route input there
        if @chat_panel&.visible
          return update_chat_panel(msg)
        end

        case
        when msg.esc? || char == "q"
          [self, Bubbletea.quit]
        when msg.enter?
          po = @dashboard&.selected_po
          if po
            open_chat_panel(po)
          end
          [self, nil]
        when msg.up? || char == "k"
          @dashboard&.move_up
          [self, nil]
        when msg.down? || char == "j"
          @dashboard&.move_down
          [self, nil]
        when msg.left? || char == "h"
          @dashboard&.move_left
          [self, nil]
        when msg.right? || char == "l"
          @dashboard&.move_right
          [self, nil]
        when msg.tab?
          @dashboard&.toggle_focus
          [self, nil]
        when char == "N"
          # Open notification panel
          @notification_panel.set_dimensions(@width, @height)
          @notification_panel.toggle
          [self, nil]
        when char == "?"
          @show_help = !@show_help
          [self, nil]
        else
          [self, nil]
        end
      end

      private def open_chat_panel(po)
        @chat_panel = Models::ChatPanel.new(
          po: po,
          session_store: @env.session_store,
          env: @env,
          context: @context
        )
        # Chat panel gets ~65% of width
        panel_width = (@width * 0.65).to_i
        @chat_panel.set_dimensions(panel_width, @height - 2)
        @active_po = po
        @context.current_capability = po.name
      end

      private def close_chat_panel
        @chat_panel = nil
      end

      private def update_chat_panel(msg)
        return [self, nil] unless @chat_panel

        char = msg.char.to_s

        # Ctrl+C always quits
        if msg.ctrl? && char == "c"
          return [self, Bubbletea.quit]
        end

        case @chat_panel.mode
        when Models::ChatPanel::MODE_INSERT
          handle_chat_insert_mode(msg, char)
        when Models::ChatPanel::MODE_SESSION_SELECT
          handle_chat_session_mode(msg, char)
        else
          handle_chat_normal_mode(msg, char)
        end
      end

      private def handle_chat_normal_mode(msg, char)
        case
        when msg.esc?
          close_chat_panel
          [self, nil]
        when char == "q"
          close_chat_panel
          [self, nil]
        when char == "i" || msg.enter?
          @chat_panel.mode = Models::ChatPanel::MODE_INSERT
          [self, nil]
        when char == "s"
          @chat_panel.mode = Models::ChatPanel::MODE_SESSION_SELECT
          [self, nil]
        when char == "n"
          @chat_panel.create_new_session
          [self, nil]
        when char == "N"
          # Open notification panel
          @notification_panel.set_dimensions(@width, @height)
          @notification_panel.toggle
          [self, nil]
        else
          [self, nil]
        end
      end

      private def handle_chat_insert_mode(msg, char)
        case
        when msg.esc?
          @chat_panel.mode = Models::ChatPanel::MODE_NORMAL
          [self, nil]
        when msg.enter?
          text = @chat_panel.submit_input
          if text && !text.empty?
            send_chat_message(text)
          end
          @chat_panel.mode = Models::ChatPanel::MODE_NORMAL
          [self, nil]
        when msg.backspace?
          @chat_panel.delete_char
          [self, nil]
        when msg.space?
          @chat_panel.insert_char(" ")
          [self, nil]
        when msg.ctrl? && char == "u"
          @chat_panel.clear_input
          [self, nil]
        when msg.runes? && !char.empty?
          @chat_panel.insert_char(char)
          [self, nil]
        else
          [self, nil]
        end
      end

      private def handle_chat_session_mode(msg, char)
        case
        when msg.esc?
          @chat_panel.mode = Models::ChatPanel::MODE_NORMAL
          [self, nil]
        when msg.left? || char == "h"
          @chat_panel.prev_session
          [self, nil]
        when msg.right? || char == "l"
          @chat_panel.next_session
          [self, nil]
        when char == "n"
          @chat_panel.create_new_session
          [self, nil]
        when msg.enter?
          @chat_panel.mode = Models::ChatPanel::MODE_NORMAL
          [self, nil]
        else
          [self, nil]
        end
      end

      private def send_chat_message(text)
        return unless @chat_panel && @active_po

        # Log to message bus
        @env.bus.publish(from: "human", to: @active_po.name, message: text)

        # Show pending state
        @chat_panel.set_pending_message(text)
        @active_po.state = :working

        # Run LLM call in background
        po = @active_po
        context = @context
        env = @env
        chat_panel = @chat_panel

        Thread.new do
          begin
            response = po.receive(text, context: context)
            po.state = :idle
            env.bus.publish(from: po.name, to: "human", message: response)
            Bubbletea.send_message(Messages::POResponse.new(po_name: po.name, text: response))
          rescue StandardError => e
            Bubbletea.send_message(Messages::ErrorOccurred.new(message: e.message))
            po.state = :idle
          end
        end
      end

      private def update_po_detail(msg)
        return [self, nil] unless msg.is_a?(Bubbletea::KeyMessage)
        return [self, nil] unless @po_detail

        char = msg.char.to_s

        # Ctrl+C always quits
        if msg.ctrl? && char == "c"
          return [self, Bubbletea.quit]
        end

        case
        when msg.esc?
          navigate_back
          [self, nil]
        when char == "q"
          [self, Bubbletea.quit]
        when msg.up? || char == "k"
          @po_detail.move_up
          [self, nil]
        when msg.down? || char == "j"
          @po_detail.move_down
          [self, nil]
        when msg.tab?
          @po_detail.cycle_focus
          [self, nil]
        when char == "n"
          # Create new session for this PO
          create_new_session_for_po
          [self, nil]
        when msg.enter?
          # Open selected session in chat
          session = @po_detail.selected_session
          if session
            navigate_to(MAIN_SUBSCREEN_SESSION_CHAT, { session: session })
          end
          [self, nil]
        when char == "?"
          @show_help = !@show_help
          [self, nil]
        else
          [self, nil]
        end
      end

      def create_new_session_for_po
        return unless @selected_po_for_detail && @env.session_store

        name = "Session #{Time.now.strftime('%Y-%m-%d %H:%M')}"
        session_id = @env.session_store.create_session(
          po_name: @selected_po_for_detail.name,
          name: name,
          source: "tui"
        )

        # Refresh po_detail to show new session
        init_po_detail
      end

      private def update_session_chat(msg)
        # Original update_main logic for session chat
        case msg
        when Bubbletea::KeyMessage
          handle_key(msg)
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
        when Messages::SessionsChanged
          handle_sessions_changed(msg)
        else
          [self, nil]
        end
      end

      def handle_sessions_changed(msg)
        # Check if any updated session is the active session
        if @active_po
          active_session_id = @active_po.instance_variable_get(:@session_id)
          updated_session = msg.updated_sessions.find { |s| s[:id] == active_session_id }

          if updated_session
            # Reload the conversation to show new messages
            @active_po.send(:reload_history_from_session) if @active_po.respond_to?(:reload_history_from_session, true)
            @conversation.set_po(@active_po)
          end
        end

        # Refresh session explorer if open
        if @modal&.dig(:type) == :session_explorer && @session_explorer
          @session_explorer.refresh_sessions
        end

        [self, nil]
      end

      def handle_po_response(msg)
        # Clear the pending message and update conversation
        @conversation.clear_pending
        @conversation.set_po(@active_po)

        # Also update chat panel if open
        if @chat_panel&.visible
          @chat_panel.clear_pending
          @chat_panel.refresh_conversation
        end

        @error = nil
        [self, nil]
      end

      def view
        return "" if @width == 0 || @height == 0

        # Route view based on current screen
        case @screen
        when SCREEN_PICKER
          @picker&.view || ""
        when SCREEN_WIZARD
          @wizard&.view || ""
        when SCREEN_MAIN
          view_main
        else
          ""
        end
      end

      private def view_main
        # Route view based on current sub-screen
        output = case @main_subscreen
                 when MAIN_SUBSCREEN_DASHBOARD
                   view_dashboard
                 when MAIN_SUBSCREEN_PO_DETAIL
                   view_po_detail
                 else  # MAIN_SUBSCREEN_SESSION_CHAT
                   view_session_chat
                 end

        # Modal overlay (if any)
        output = render_modal_overlay(output) if @modal

        # Notification panel overlay
        output = render_notification_overlay(output) if @notification_panel&.visible

        # Responder modal overlay (highest priority)
        output = render_responder_overlay(output) if @responder

        output
      end

      private def view_dashboard
        return "" unless @dashboard

        if @chat_panel&.visible
          # Side-by-side: dashboard on left, chat panel on right
          return view_dashboard_with_chat_panel
        end

        @dashboard.set_dimensions(@width, @height)

        lines = []
        lines << render_header
        lines << ""
        lines << @dashboard.view
        lines.join("\n")
      end

      private def view_dashboard_with_chat_panel
        # Calculate widths: chat panel gets 65%, dashboard gets 35%
        chat_width = (@width * 0.65).to_i
        dash_width = @width - chat_width - 1  # -1 for separator

        @dashboard.set_dimensions(dash_width, @height - 2)
        @chat_panel.set_dimensions(chat_width, @height - 2)

        # Get views
        dash_lines = @dashboard.view.split("\n")
        chat_lines = @chat_panel.view.split("\n")

        # Ensure both have same height
        max_lines = @height - 1
        while dash_lines.length < max_lines
          dash_lines << ""
        end
        while chat_lines.length < max_lines
          chat_lines << ""
        end

        # Compose side by side
        lines = [render_header]

        (max_lines - 1).times do |i|
          dash_line = dash_lines[i] || ""
          chat_line = chat_lines[i] || ""

          # Pad dashboard line to width
          dash_visible = dash_line.gsub(/\e\[[0-9;]*m/, '').length
          dash_padded = dash_line + (" " * [dash_width - dash_visible, 0].max)

          lines << "#{dash_padded}│#{chat_line}"
        end

        lines.join("\n")
      end

      private def view_po_detail
        return "" unless @po_detail

        @po_detail.set_dimensions(@width, @height - 1)  # Leave room for header
        lines = []
        lines << render_header
        lines << @po_detail.view
        lines.join("\n")
      end

      private def view_session_chat
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

        lines.join("\n")
      end

      # Class method to run the app
      #
      # Parameters:
      # - objects_dir: Legacy mode - directory containing PO markdown files
      # - primitives_dir: Legacy mode - directory for custom primitives
      # - env_path: Direct path to environment (skips picker/wizard)
      # - manager: Environment manager (enables picker/wizard flow)
      # - dev_mode: Use development environment (skips picker/wizard)
      def self.run(objects_dir: nil, primitives_dir: nil, env_path: nil, manager: nil, dev_mode: false)
        app = new(
          objects_dir: objects_dir,
          primitives_dir: primitives_dir,
          env_path: env_path,
          manager: manager,
          dev_mode: dev_mode
        )
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

      def start_session_polling
        @session_poll_thread = Thread.new do
          loop do
            sleep 2  # Poll every 2 seconds

            begin
              check_for_session_changes
            rescue SQLite3::BusyException
              # Database is locked, skip this poll cycle
              # WAL mode + busy_timeout should prevent this, but handle it gracefully
            rescue StandardError
              # Ignore other errors in polling
            end
          end
        end
      end

      def check_for_session_changes
        return unless @env&.session_store

        # Get all sessions
        sessions = @env.session_store.list_all_sessions

        new_sessions = []
        updated_sessions = []

        sessions.each do |session|
          id = session[:id]
          updated_at = session[:updated_at]

          if @session_poll_state[:session_timestamps][id].nil?
            # New session
            new_sessions << session
            @session_poll_state[:session_timestamps][id] = updated_at
          elsif updated_at && @session_poll_state[:session_timestamps][id] != updated_at
            # Updated session
            updated_sessions << session
            @session_poll_state[:session_timestamps][id] = updated_at
          end
        end

        # Check if any MCP sessions are active (updated in last 30 seconds)
        # Check both source and last_message_source since a TUI session could be messaged via MCP
        mcp_active = sessions.any? do |s|
          mcp_involved = s[:source] == "mcp" || s[:last_message_source] == "mcp"
          recently_active = s[:updated_at] && (Time.now - s[:updated_at]) < 30
          mcp_involved && recently_active
        end

        if mcp_active != @session_poll_state[:mcp_active]
          @session_poll_state[:mcp_active] = mcp_active
        end

        # Send message if there are changes
        if new_sessions.any? || updated_sessions.any?
          Bubbletea.send_message(Messages::SessionsChanged.new(
            new_sessions: new_sessions,
            updated_sessions: updated_sessions
          ))
        end
      end

      def mcp_active?
        @session_poll_state&.dig(:mcp_active) || false
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
        when char == "S"
          # Open session picker (per-PO)
          if @active_po && @env.session_store
            @session_picker = Models::SessionPicker.new(po: @active_po, session_store: @env.session_store)
            @session_picker.set_dimensions(@width, @height)
            @session_picker.show
            @modal = { type: :session_picker, data: @session_picker }
          end
          [self, nil]
        when char == "E"
          # Open session explorer (all sessions across all POs)
          if @env.session_store
            @session_explorer = Models::SessionExplorer.new(session_store: @env.session_store)
            @session_explorer.set_dimensions(@width, @height)
            @session_explorer.show
            @modal = { type: :session_explorer, data: @session_explorer }
          end
          [self, nil]
        when char == "D"
          # Switch to dashboard view
          @main_subscreen = MAIN_SUBSCREEN_DASHBOARD
          @nav_stack = []  # Clear nav stack when explicitly going to dashboard
          init_dashboard
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

        # Handle session picker specially
        if @modal && @modal[:type] == :session_picker && @session_picker
          return handle_session_picker_key(msg, char)
        end

        # Handle session explorer specially
        if @modal && @modal[:type] == :session_explorer && @session_explorer
          return handle_session_explorer_key(msg, char)
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

      def handle_session_picker_key(msg, char)
        # Handle input mode (rename/new)
        if @session_picker.input_mode?
          case
          when msg.esc?
            @session_picker.cancel_action
          when msg.enter?
            @session_picker.confirm_action
            check_session_picker_done
          when msg.backspace?
            @session_picker.delete_char
          when msg.space?
            @session_picker.insert_char(" ")
          when msg.runes? && !char.empty?
            @session_picker.insert_char(char)
          end
          return [self, nil]
        end

        # Handle confirm delete mode
        if @session_picker.confirm_mode?
          case char
          when "y", "Y"
            @session_picker.confirm_action
          when "n", "N"
            @session_picker.cancel_action
          end
          return [self, nil]
        end

        # Normal navigation mode
        case
        when msg.esc?
          close_modal
        when char == "q"
          close_modal
        when char == "j" || msg.down?
          @session_picker.move_down
        when char == "k" || msg.up?
          @session_picker.move_up
        when msg.enter?
          @session_picker.select_current
          check_session_picker_done
        when char == "n"
          @session_picker.start_new_session
        when char == "r"
          @session_picker.start_rename
        when char == "d"
          @session_picker.start_delete
        end

        [self, nil]
      end

      def check_session_picker_done
        return unless @session_picker&.done

        session_id = @session_picker.selected_session_id
        if session_id && @active_po
          @active_po.switch_session(session_id)
          @conversation.set_po(@active_po)
        end

        close_modal
      end

      def handle_session_explorer_key(msg, char)
        # Clear export result on any key
        @session_explorer.clear_export_result if @session_explorer.has_export_result?

        # Handle search mode
        if @session_explorer.search_mode?
          case
          when msg.esc?
            @session_explorer.cancel_search
          when msg.enter?
            @session_explorer.confirm_search
          when msg.backspace?
            @session_explorer.delete_char
          when msg.space?
            @session_explorer.insert_char(" ")
          when msg.runes? && !char.empty?
            @session_explorer.insert_char(char)
          end
          return [self, nil]
        end

        # Handle confirm delete mode
        if @session_explorer.confirm_mode?
          case char
          when "y", "Y"
            @session_explorer.confirm_delete
          when "n", "N"
            @session_explorer.cancel_delete
          end
          return [self, nil]
        end

        # Handle export mode
        if @session_explorer.export_mode?
          case char
          when "j", "J"
            @session_explorer.export_json
          when "m", "M"
            @session_explorer.export_markdown
          end
          if msg.esc?
            @session_explorer.cancel_export
          end
          return [self, nil]
        end

        # Normal navigation mode
        case
        when msg.esc?
          if @session_explorer.search_query && !@session_explorer.search_query.empty?
            @session_explorer.clear_search
          else
            close_modal
          end
        when char == "q"
          close_modal
        when char == "j" || msg.down?
          @session_explorer.move_down
        when char == "k" || msg.up?
          @session_explorer.move_up
        when msg.tab?
          @session_explorer.cycle_filter
        when char == "/"
          @session_explorer.start_search
        when char == "x"
          @session_explorer.start_export
        when char == "d"
          @session_explorer.start_delete
        when msg.enter?
          @session_explorer.select_current
          check_session_explorer_done
        end

        [self, nil]
      end

      def check_session_explorer_done
        return unless @session_explorer&.done

        session = @session_explorer.selected_session
        if session
          # Find the PO for this session
          po = @env.registry.get(session[:po_name])
          if po.is_a?(PromptObject)
            @active_po = po
            @capability_bar.select(po.name)
            @active_po.switch_session(session[:id])
            @conversation.set_po(@active_po)
            @context.current_capability = po.name
          end
        end

        close_modal
      end

      def close_modal
        @modal = nil
        @inspector = nil
        @editor = nil
        @session_picker = nil
        @session_explorer = nil
      end

      # --- Dashboard Navigation Helpers ---

      def navigate_to(subscreen, data = {})
        @nav_stack.push(@main_subscreen)
        @main_subscreen = subscreen

        case subscreen
        when MAIN_SUBSCREEN_DASHBOARD
          init_dashboard
        when MAIN_SUBSCREEN_PO_DETAIL
          @selected_po_for_detail = data[:po]
          init_po_detail
        when MAIN_SUBSCREEN_SESSION_CHAT
          @selected_session_for_chat = data[:session]
          init_session_chat_from_nav
        end
      end

      def navigate_back
        return if @nav_stack.empty?

        previous = @nav_stack.pop
        @main_subscreen = previous

        case @main_subscreen
        when MAIN_SUBSCREEN_DASHBOARD
          @selected_po_for_detail = nil
          @selected_session_for_chat = nil
        when MAIN_SUBSCREEN_PO_DETAIL
          @selected_session_for_chat = nil
          # Refresh the detail view in case sessions changed
          init_po_detail if @selected_po_for_detail
        end
      end

      def init_dashboard
        @dashboard = Models::Dashboard.new(
          registry: @env.registry,
          session_store: @env.session_store,
          human_queue: @env.human_queue
        )
        @dashboard.set_dimensions(@width, @height)
      end

      def init_po_detail
        return unless @selected_po_for_detail

        @po_detail = Models::PODetail.new(
          po: @selected_po_for_detail,
          session_store: @env.session_store,
          human_queue: @env.human_queue
        )
        @po_detail.set_dimensions(@width, @height)
      end

      def init_session_chat_from_nav
        return unless @selected_session_for_chat

        session = @selected_session_for_chat
        po = @env.registry.get(session[:po_name])

        if po.is_a?(PromptObject)
          @active_po = po
          @capability_bar.select(po.name)
          @active_po.switch_session(session[:id])
          @conversation.set_po(@active_po)
          @context.current_capability = po.name
        end
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

        # Handle commands
        if text.start_with?("/")
          return handle_command(text)
        end

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

      # --- Command handling ---

      def handle_command(text)
        parts = text.strip.split(/\s+/, 2)
        command = parts[0].downcase
        args = parts[1]

        case command
        when "/help"
          show_command_help
        when "/sessions"
          list_sessions
        when "/session"
          handle_session_command(args)
        else
          @conversation.show_system_message("Unknown command: #{command}. Type /help for available commands.")
        end

        [self, nil]
      end

      def show_command_help
        help = <<~HELP.strip
          Commands: /sessions (list), /session new [name], /session rename <name>,
          /session switch <name|id>, /session export [json|md], /session info
        HELP
        @conversation.show_system_message(help)
      end

      def list_sessions
        return @conversation.show_system_message("No active PO") unless @active_po
        return @conversation.show_system_message("Sessions not available") unless @env&.session_store

        sessions = @env.session_store.list_sessions(@active_po.name)
        if sessions.empty?
          @conversation.show_system_message("No sessions for #{@active_po.name}")
        else
          current_id = @active_po.instance_variable_get(:@session_id)
          names = sessions.map do |s|
            marker = s[:id] == current_id ? "*" : " "
            "#{marker}#{s[:name] || 'Unnamed'}"
          end
          @conversation.show_system_message("Sessions: #{names.join(', ')}")
        end
      end

      def handle_session_command(args)
        return @conversation.show_system_message("No active PO") unless @active_po
        return @conversation.show_system_message("Sessions not available") unless @env&.session_store

        parts = args&.split(/\s+/, 2) || []
        subcommand = parts[0]&.downcase
        subargs = parts[1]

        case subcommand
        when "new"
          session_new(subargs)
        when "rename"
          session_rename(subargs)
        when "switch"
          session_switch(subargs)
        when "export"
          session_export(subargs)
        when "info"
          session_info
        when nil
          @conversation.show_system_message("Usage: /session <new|rename|switch|export|info> [args]")
        else
          @conversation.show_system_message("Unknown session command: #{subcommand}")
        end
      end

      def session_new(name)
        name = name&.strip
        name = nil if name&.empty?
        name ||= "Session #{Time.now.strftime('%Y-%m-%d %H:%M')}"

        session_id = @env.session_store.create_session(
          po_name: @active_po.name,
          name: name,
          source: "tui"
        )
        @active_po.switch_session(session_id)
        @conversation.set_po(@active_po)
        @conversation.show_system_message("Created and switched to session: #{name}")
      end

      def session_rename(new_name)
        return @conversation.show_system_message("Usage: /session rename <name>") unless new_name && !new_name.strip.empty?

        session_id = @active_po.instance_variable_get(:@session_id)
        return @conversation.show_system_message("No active session") unless session_id

        @env.session_store.rename_session(session_id, new_name.strip)
        @conversation.show_system_message("Renamed session to: #{new_name.strip}")
      end

      def session_switch(identifier)
        return @conversation.show_system_message("Usage: /session switch <name|id>") unless identifier && !identifier.strip.empty?

        identifier = identifier.strip
        sessions = @env.session_store.list_sessions(@active_po.name)

        # Try to find by name first, then by ID prefix
        session = sessions.find { |s| s[:name]&.downcase == identifier.downcase }
        session ||= sessions.find { |s| s[:id].to_s.start_with?(identifier) }

        if session
          @active_po.switch_session(session[:id])
          @conversation.set_po(@active_po)
          @conversation.show_system_message("Switched to: #{session[:name] || 'Unnamed'}")
        else
          @conversation.show_system_message("Session not found: #{identifier}")
        end
      end

      def session_export(format)
        session_id = @active_po.instance_variable_get(:@session_id)
        return @conversation.show_system_message("No active session") unless session_id

        format = (format || "json").strip.downcase
        session = @env.session_store.get_session(session_id)
        safe_name = (session[:name] || "session").gsub(/[^a-zA-Z0-9_-]/, "_")[0, 30]
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")

        case format
        when "json"
          data = @env.session_store.export_session_json(session_id)
          filename = "#{safe_name}_#{timestamp}.json"
          File.write(filename, JSON.pretty_generate(data))
          @conversation.show_system_message("Exported to #{filename}")
        when "md", "markdown"
          content = @env.session_store.export_session_markdown(session_id)
          filename = "#{safe_name}_#{timestamp}.md"
          File.write(filename, content)
          @conversation.show_system_message("Exported to #{filename}")
        else
          @conversation.show_system_message("Unknown format: #{format}. Use 'json' or 'md'")
        end
      rescue StandardError => e
        @conversation.show_system_message("Export error: #{e.message}")
      end

      def session_info
        session_id = @active_po.instance_variable_get(:@session_id)
        return @conversation.show_system_message("No active session") unless session_id

        session = @env.session_store.get_session(session_id)
        return @conversation.show_system_message("Session not found") unless session

        msg_count = @env.session_store.message_count(session_id)
        info = [
          "Name: #{session[:name] || 'Unnamed'}",
          "PO: #{session[:po_name]}",
          "Messages: #{msg_count}",
          "Source: #{session[:source] || 'tui'}",
          "Created: #{session[:created_at]&.strftime('%Y-%m-%d %H:%M')}"
        ].join(" | ")
        @conversation.show_system_message(info)
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
        env_info = if @env_path
                     " [#{@env.name}]"
                   elsif @primitives_dir
                     " [SANDBOX]"
                   else
                     ""
                   end
        "#{title}#{env_info}"
      end

      def conversation_title
        return " Conversation " unless @active_po

        # Get current session name
        session_name = nil
        if @env&.session_store && @active_po.instance_variable_get(:@session_id)
          session_id = @active_po.instance_variable_get(:@session_id)
          session = @env.session_store.get_session(session_id)
          session_name = session[:name] if session && session[:name]
        end

        if session_name
          " #{@active_po.name}: #{session_name} "
        else
          " #{@active_po.name} "
        end
      end

      def render_main_content(height)
        lines = []

        if @show_message_log
          # Split: conversation (60%) | message log (40%)
          conv_width = (@width * 0.6).to_i - 1
          log_width = @width - conv_width - 3

          conv_lines = @conversation.view_lines(conv_width - 4, height - 2)
          log_lines = @message_log.view_lines(log_width - 4, height - 2)

          # Draw conversation box
          conv_title = conversation_title
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

          conv_title = conversation_title
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

        # MCP live indicator
        mcp_indicator = if mcp_active?
                          Styles.panel_title.render(" [MCP LIVE] ")
                        else
                          ""
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
            Styles.help_key.render("D") + " dashboard",
            Styles.help_key.render("S") + " sessions",
            Styles.help_key.render("E") + " explorer",
            Styles.help_key.render(notif_label) + " notifications",
            Styles.help_key.render("I") + " inspect",
            Styles.help_key.render("q") + " quit"
          ]
        end

        Styles.status_bar.render(mcp_indicator + parts.join("  "))
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
        when :session_picker
          if @session_picker
            modal_view = @session_picker.view
            center_modal(base, modal_view)
          else
            base
          end
        when :session_explorer
          if @session_explorer
            modal_view = @session_explorer.view
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
