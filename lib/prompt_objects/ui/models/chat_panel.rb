# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Slide-over chat panel for interacting with a PO
      # Shows session selector, conversation, and input
      class ChatPanel
        attr_reader :po, :width, :height, :visible
        attr_accessor :mode

        MODE_NORMAL = :normal
        MODE_INSERT = :insert
        MODE_SESSION_SELECT = :session_select

        def initialize(po:, session_store: nil, env: nil, context: nil)
          @po = po
          @session_store = session_store
          @env = env
          @context = context
          @width = 60
          @height = 24
          @visible = true
          @mode = MODE_NORMAL

          # Session state
          @sessions_cache = nil
          @session_cursor = 0

          # Conversation state (reuse Conversation model)
          @conversation = Conversation.new
          @conversation.set_po(po)

          # Input state
          @input = Input.new

          refresh_sessions
        end

        def set_dimensions(width, height)
          @width = width
          @height = height
          @conversation.width = width - 4
          @conversation.height = height - 8  # Header + session bar + input + borders
        end

        def show
          @visible = true
          refresh_sessions
        end

        def hide
          @visible = false
        end

        def refresh_sessions
          @sessions_cache = nil
          sessions  # Force cache refresh
        end

        # --- Session Navigation ---

        def sessions
          return [] unless @session_store
          return @sessions_cache if @sessions_cache

          @sessions_cache = @session_store.list_sessions(po_name: @po.name) rescue []
        end

        def current_session
          sessions[@session_cursor]
        end

        def prev_session
          return if sessions.empty?
          @session_cursor = (@session_cursor - 1) % sessions.length
          switch_to_current_session
        end

        def next_session
          return if sessions.empty?
          @session_cursor = (@session_cursor + 1) % sessions.length
          switch_to_current_session
        end

        def switch_to_current_session
          session = current_session
          return unless session

          @po.switch_session(session[:id])
          @conversation.set_po(@po)
        end

        def create_new_session
          return unless @session_store

          name = "Session #{Time.now.strftime('%Y-%m-%d %H:%M')}"
          session_id = @session_store.create_session(
            po_name: @po.name,
            name: name,
            source: "tui"
          )
          @po.switch_session(session_id)
          @conversation.set_po(@po)
          refresh_sessions
          @session_cursor = 0  # New session is at top (most recent)
        end

        # --- Input Handling ---

        def insert_char(char)
          @input.insert(char)
        end

        def delete_char
          @input.delete_char
        end

        def submit_input
          text = @input.submit
          return nil if text.nil? || text.empty?
          text
        end

        def clear_input
          @input.clear
        end

        def input_text
          @input.text
        end

        # --- Conversation State ---

        def set_pending_message(text)
          @conversation.set_pending_message(text)
        end

        def clear_pending
          @conversation.clear_pending
        end

        def waiting?
          @conversation.waiting?
        end

        def refresh_conversation
          @conversation.set_po(@po)
        end

        # --- View Rendering ---

        def view
          return "" unless @visible

          lines = []
          inner_width = @width - 4

          # Top border with PO name
          state_icon = case @po.state
                       when :working then "◐"
                       when :active then "●"
                       when :waiting_for_human then "⚠"
                       else "○"
                       end
          title = " #{state_icon} #{@po.name} "
          lines << Styles.panel_title.render("┌#{title}#{"─" * [inner_width - title.length, 0].max}┐")

          # Session bar
          lines << render_session_bar(inner_width)

          # Separator
          lines << "├#{"─" * inner_width}┤"

          # Conversation area
          conv_height = @height - 7  # Borders + session bar + input + status
          conv_lines = @conversation.view_lines(inner_width - 2, conv_height)
          conv_lines.each do |line|
            visible_len = line.gsub(/\e\[[0-9;]*m/, '').length
            padding = [inner_width - 2 - visible_len, 0].max
            lines << "│ #{line}#{" " * padding} │"
          end

          # Pad conversation area if needed
          while lines.length < @height - 4
            lines << "│#{" " * inner_width}│"
          end

          # Input separator
          lines << "├#{"─" * inner_width}┤"

          # Input line
          lines << render_input_line(inner_width)

          # Bottom border with help
          lines << render_status_bar(inner_width)

          lines.join("\n")
        end

        private

        def render_session_bar(width)
          sess = sessions
          if sess.empty?
            content = " No sessions - press 'n' to create "
            content = Styles.thinking.render(content)
          else
            # Show current session with arrows
            current = sess[@session_cursor]
            name = current[:name] || "Unnamed"
            name = truncate(name, width - 20)
            source_badge = case current[:source]
                           when "mcp" then Styles.panel_title.render("[MCP]")
                           when "api" then Styles.panel_title.render("[API]")
                           else "[TUI]"
                           end

            left_arrow = @session_cursor > 0 ? "◀" : " "
            right_arrow = @session_cursor < sess.length - 1 ? "▶" : " "
            counter = "(#{@session_cursor + 1}/#{sess.length})"

            content = " #{left_arrow} #{source_badge} #{name} #{counter} #{right_arrow} "

            if @mode == MODE_SESSION_SELECT
              content = Styles.help_key.render(content)
            end
          end

          visible_len = content.gsub(/\e\[[0-9;]*m/, '').length
          padding = [width - visible_len, 0].max
          "│#{content}#{" " * padding}│"
        end

        def render_input_line(width)
          prefix = @mode == MODE_INSERT ? "› " : "  "
          text = @input.text || ""
          max_text_width = width - 6

          # Truncate if too long
          if text.length > max_text_width
            text = "…" + text[-(max_text_width - 1)..]
          end

          if @mode == MODE_INSERT
            # Show cursor
            cursor_char = "\e[7m \e[0m"  # Inverted space
            content = "#{prefix}#{text}#{cursor_char}"
            content = Styles.help_key.render(prefix) + text + cursor_char
          else
            display = text.empty? ? "Press 'i' to type..." : text
            content = "#{prefix}#{Styles.thinking.render(display)}"
          end

          visible_len = content.gsub(/\e\[[0-9;]*m/, '').length
          padding = [width - visible_len, 0].max
          "│#{content}#{" " * padding}│"
        end

        def render_status_bar(width)
          parts = case @mode
                  when MODE_INSERT
                    [
                      "#{Styles.help_key.render("Esc")} normal",
                      "#{Styles.help_key.render("Enter")} send"
                    ]
                  when MODE_SESSION_SELECT
                    [
                      "#{Styles.help_key.render("←→")} switch",
                      "#{Styles.help_key.render("n")} new",
                      "#{Styles.help_key.render("Esc")} done"
                    ]
                  else
                    [
                      "#{Styles.help_key.render("i")} type",
                      "#{Styles.help_key.render("s")} sessions",
                      "#{Styles.help_key.render("N")} notifications",
                      "#{Styles.help_key.render("Esc")} close"
                    ]
                  end

          content = " " + parts.join("  ") + " "
          visible_len = content.gsub(/\e\[[0-9;]*m/, '').length
          padding = [width - visible_len, 0].max
          "└#{content}#{"─" * padding}┘"
        end

        def truncate(str, max)
          return "" if str.nil?
          str.length <= max ? str : str[0, max - 1] + "…"
        end
      end
    end
  end
end
