# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Modal for managing sessions for a PromptObject.
      # Allows switching, creating, renaming, and deleting sessions.
      class SessionPicker
        attr_reader :width, :height, :done, :selected_session_id
        attr_accessor :visible

        # Input modes for rename functionality
        MODE_NORMAL = :normal
        MODE_RENAME = :rename
        MODE_NEW = :new
        MODE_CONFIRM_DELETE = :confirm_delete

        def initialize(po:, session_store:)
          @po = po
          @session_store = session_store
          @width = 50
          @height = 14
          @cursor = 0
          @visible = false
          @done = false
          @selected_session_id = nil
          @mode = MODE_NORMAL
          @input_buffer = ""
          @sessions = []
          refresh_sessions
        end

        def set_dimensions(width, height)
          @width = [width - 10, 45].max
          @height = [height - 6, 10].max
        end

        def show
          @visible = true
          @done = false
          @cursor = 0
          @mode = MODE_NORMAL
          @input_buffer = ""
          refresh_sessions
          select_current_session
        end

        def hide
          @visible = false
          @mode = MODE_NORMAL
        end

        def refresh_sessions
          @sessions = @session_store.list_sessions(po_name: @po.name)
        end

        # Select the row matching the PO's current session
        def select_current_session
          current_id = @po.instance_variable_get(:@session_id)
          return unless current_id

          idx = @sessions.find_index { |s| s[:id] == current_id }
          @cursor = idx if idx
        end

        def move_up
          return unless @mode == MODE_NORMAL
          @cursor = [@cursor - 1, 0].max
        end

        def move_down
          return unless @mode == MODE_NORMAL
          @cursor = [@cursor + 1, @sessions.length - 1].max
        end

        def selected_session
          return nil if @sessions.empty? || @cursor >= @sessions.length
          @sessions[@cursor]
        end

        # --- Actions ---

        def select_current
          return unless @mode == MODE_NORMAL

          session = selected_session
          return unless session

          @selected_session_id = session[:id]
          @done = true
        end

        def start_new_session
          @mode = MODE_NEW
          @input_buffer = ""
        end

        def start_rename
          return unless @mode == MODE_NORMAL

          session = selected_session
          return unless session

          @mode = MODE_RENAME
          @input_buffer = session[:name] || ""
        end

        def start_delete
          return unless @mode == MODE_NORMAL
          return if @sessions.length <= 1  # Can't delete the only session

          @mode = MODE_CONFIRM_DELETE
        end

        def confirm_action
          case @mode
          when MODE_NEW
            create_new_session
          when MODE_RENAME
            rename_current_session
          when MODE_CONFIRM_DELETE
            delete_current_session
          end
        end

        def cancel_action
          @mode = MODE_NORMAL
          @input_buffer = ""
        end

        def input_mode?
          @mode == MODE_RENAME || @mode == MODE_NEW
        end

        def confirm_mode?
          @mode == MODE_CONFIRM_DELETE
        end

        def insert_char(char)
          return unless input_mode?
          @input_buffer += char
        end

        def delete_char
          return unless input_mode?
          @input_buffer = @input_buffer[0..-2]
        end

        private

        def create_new_session
          name = @input_buffer.strip
          name = nil if name.empty?

          new_id = @session_store.create_session(po_name: @po.name, name: name)
          @selected_session_id = new_id
          @done = true
          @mode = MODE_NORMAL
        end

        def rename_current_session
          session = selected_session
          return unless session

          name = @input_buffer.strip
          name = nil if name.empty?

          @session_store.update_session(session[:id], name: name)
          @mode = MODE_NORMAL
          @input_buffer = ""
          refresh_sessions
        end

        def delete_current_session
          session = selected_session
          return unless session

          @session_store.delete_session(session[:id])
          @mode = MODE_NORMAL
          refresh_sessions
          @cursor = [@cursor, @sessions.length - 1].min
          @cursor = 0 if @cursor < 0
        end

        public

        def view
          lines = []

          # Title bar
          title = " Sessions: #{@po.name} "
          title_line = "┌#{title}#{'─' * (@width - title.length - 2)}┐"
          lines << Styles.modal_title.render(title_line)

          # Content area
          content_height = @height - 4

          if @sessions.empty?
            lines << "│#{' ' * (@width - 2)}│"
            empty_msg = "No sessions found"
            padding = (@width - 2 - empty_msg.length) / 2
            lines << "│#{' ' * padding}#{empty_msg}#{' ' * (@width - 2 - padding - empty_msg.length)}│"
            (content_height - 2).times { lines << "│#{' ' * (@width - 2)}│" }
          else
            lines << "│#{' ' * (@width - 2)}│"

            current_session_id = @po.instance_variable_get(:@session_id)

            @sessions.each_with_index do |session, i|
              break if i >= content_height - 1

              cursor_indicator = i == @cursor ? "▸" : " "
              current_marker = session[:id] == current_session_id ? "*" : " "

              name = session[:name] || "Unnamed"
              name = truncate(name, @width - 35)

              # Get message count
              msg_count = @session_store.message_count(session[:id])
              count_str = "#{msg_count} msg#{'s' if msg_count != 1}"

              # Format time
              time_str = format_time(session[:updated_at])

              # Style based on selection
              if i == @cursor
                name_styled = Styles.help_key.render(name)
                marker_styled = current_marker == "*" ? Styles.help_key.render("*") : " "
              else
                name_styled = session[:id] == current_session_id ? Styles.panel_title.render(name) : name
                marker_styled = current_marker == "*" ? Styles.panel_title.render("*") : " "
              end

              count_styled = Styles.timestamp.render(count_str)
              time_styled = Styles.timestamp.render(time_str)

              line_content = "#{cursor_indicator}#{marker_styled} #{name_styled}"
              right_content = "#{count_styled}  #{time_styled}"

              visible_left = visible_length(line_content)
              visible_right = visible_length(right_content)
              padding = @width - 4 - visible_left - visible_right

              lines << "│ #{line_content}#{' ' * [padding, 1].max}#{right_content} │"
            end

            # Pad remaining lines
            remaining = content_height - 1 - [@sessions.length, content_height - 1].min
            remaining.times { lines << "│#{' ' * (@width - 2)}│" }
          end

          # Input line for rename/new modes
          if input_mode?
            lines << "├#{'─' * (@width - 2)}┤"
            prompt = @mode == MODE_NEW ? "Name: " : "Rename: "
            input_display = "#{prompt}#{@input_buffer}_"
            input_padding = @width - 2 - input_display.length
            lines << "│#{Styles.help_key.render(input_display)}#{' ' * [input_padding, 0].max}│"
          elsif confirm_mode?
            lines << "├#{'─' * (@width - 2)}┤"
            confirm_msg = "Delete session? [y/n]"
            confirm_padding = (@width - 2 - confirm_msg.length) / 2
            lines << "│#{' ' * confirm_padding}#{Styles.error.render(confirm_msg)}#{' ' * (@width - 2 - confirm_padding - confirm_msg.length)}│"
          end

          # Bottom bar
          lines << "├#{'─' * (@width - 2)}┤"
          help = build_help_text
          help_padding = @width - 2 - visible_length(help)
          lines << "│#{help}#{' ' * [help_padding, 0].max}│"
          lines << "└#{'─' * (@width - 2)}┘"

          lines.join("\n")
        end

        private

        def build_help_text
          case @mode
          when MODE_NORMAL
            parts = [
              "#{Styles.help_key.render('Enter')} select",
              "#{Styles.help_key.render('n')} new",
              "#{Styles.help_key.render('r')} rename"
            ]
            parts << "#{Styles.help_key.render('d')} delete" if @sessions.length > 1
            parts << "#{Styles.help_key.render('Esc')} close"
            " " + parts.join("  ") + " "
          when MODE_RENAME, MODE_NEW
            " #{Styles.help_key.render('Enter')} confirm  #{Styles.help_key.render('Esc')} cancel "
          when MODE_CONFIRM_DELETE
            " #{Styles.help_key.render('y')} yes  #{Styles.help_key.render('n')} no "
          end
        end

        def truncate(str, max)
          return str if str.nil? || str.length <= max
          str[0, max - 1] + "…"
        end

        def visible_length(str)
          str.to_s.gsub(/\e\[[0-9;]*m/, '').length
        end

        def format_time(time)
          return "never" unless time

          now = Time.now
          diff = now - time

          if diff < 60
            "now"
          elsif diff < 3600
            "#{(diff / 60).to_i}m ago"
          elsif diff < 86400
            "#{(diff / 3600).to_i}h ago"
          elsif diff < 604800
            "#{(diff / 86400).to_i}d ago"
          else
            time.strftime("%m/%d")
          end
        end
      end
    end
  end
end
