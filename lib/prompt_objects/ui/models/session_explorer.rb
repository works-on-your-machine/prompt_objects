# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Modal for exploring all sessions across all POs in the environment.
      # Provides filtering, search, and bulk actions.
      class SessionExplorer
        attr_reader :width, :height, :done, :selected_session, :search_query
        attr_accessor :visible

        # Filter modes
        FILTER_ALL = :all
        FILTER_TUI = :tui
        FILTER_MCP = :mcp
        FILTER_API = :api

        FILTERS = [FILTER_ALL, FILTER_TUI, FILTER_MCP, FILTER_API].freeze

        # Modes
        MODE_NORMAL = :normal
        MODE_SEARCH = :search
        MODE_CONFIRM_DELETE = :confirm_delete
        MODE_EXPORT = :export

        def initialize(session_store:)
          @session_store = session_store
          @width = 70
          @height = 20
          @cursor = 0
          @visible = false
          @done = false
          @selected_session = nil
          @mode = MODE_NORMAL
          @filter = FILTER_ALL
          @search_query = ""
          @search_buffer = ""
          @sessions = []
          @scroll_offset = 0
          @export_result = nil  # Holds export status message
        end

        def set_dimensions(width, height)
          @width = [width - 6, 60].max
          @height = [height - 4, 12].max
        end

        def show
          @visible = true
          @done = false
          @cursor = 0
          @scroll_offset = 0
          @mode = MODE_NORMAL
          @search_query = ""
          @search_buffer = ""
          refresh_sessions
        end

        def hide
          @visible = false
          @mode = MODE_NORMAL
        end

        def refresh_sessions
          source_filter = @filter == FILTER_ALL ? nil : @filter.to_s
          @sessions = @session_store.list_all_sessions(source: source_filter)

          # Apply search filter if active
          if @search_query && !@search_query.empty?
            query = @search_query.downcase
            @sessions = @sessions.select do |s|
              (s[:name]&.downcase&.include?(query)) ||
                (s[:po_name]&.downcase&.include?(query))
            end
          end

          # Adjust cursor if needed
          @cursor = [[@cursor, 0].max, [@sessions.length - 1, 0].max].min
          adjust_scroll
        end

        # --- Navigation ---

        def move_up
          return unless @mode == MODE_NORMAL
          @cursor = [@cursor - 1, 0].max
          adjust_scroll
        end

        def move_down
          return unless @mode == MODE_NORMAL
          @cursor = [@cursor + 1, @sessions.length - 1].max
          adjust_scroll
        end

        def cycle_filter
          return unless @mode == MODE_NORMAL
          current_idx = FILTERS.index(@filter) || 0
          @filter = FILTERS[(current_idx + 1) % FILTERS.length]
          @cursor = 0
          @scroll_offset = 0
          refresh_sessions
        end

        # --- Actions ---

        def select_current
          return unless @mode == MODE_NORMAL

          session = current_session
          return unless session

          @selected_session = session
          @done = true
        end

        def start_search
          @mode = MODE_SEARCH
          @search_buffer = @search_query
        end

        def confirm_search
          @search_query = @search_buffer
          @mode = MODE_NORMAL
          @cursor = 0
          @scroll_offset = 0
          refresh_sessions
        end

        def clear_search
          @search_query = ""
          @search_buffer = ""
          @mode = MODE_NORMAL
          @cursor = 0
          refresh_sessions
        end

        def cancel_search
          @search_buffer = @search_query
          @mode = MODE_NORMAL
        end

        def start_delete
          return unless @mode == MODE_NORMAL
          return unless current_session

          @mode = MODE_CONFIRM_DELETE
        end

        def confirm_delete
          return unless @mode == MODE_CONFIRM_DELETE

          session = current_session
          return unless session

          @session_store.delete_session(session[:id])
          @mode = MODE_NORMAL
          refresh_sessions
        end

        def cancel_delete
          @mode = MODE_NORMAL
        end

        def start_export
          return unless @mode == MODE_NORMAL
          return unless current_session

          @mode = MODE_EXPORT
          @export_result = nil
        end

        def export_json
          return unless @mode == MODE_EXPORT

          session = current_session
          return unless session

          data = @session_store.export_session_json(session[:id])
          filename = export_filename(session, "json")
          File.write(filename, JSON.pretty_generate(data))

          @export_result = "Exported to #{filename}"
          @mode = MODE_NORMAL
        rescue StandardError => e
          @export_result = "Error: #{e.message}"
          @mode = MODE_NORMAL
        end

        def export_markdown
          return unless @mode == MODE_EXPORT

          session = current_session
          return unless session

          content = @session_store.export_session_markdown(session[:id])
          filename = export_filename(session, "md")
          File.write(filename, content)

          @export_result = "Exported to #{filename}"
          @mode = MODE_NORMAL
        rescue StandardError => e
          @export_result = "Error: #{e.message}"
          @mode = MODE_NORMAL
        end

        def cancel_export
          @mode = MODE_NORMAL
        end

        def export_mode?
          @mode == MODE_EXPORT
        end

        def clear_export_result
          @export_result = nil
        end

        # --- Input handling ---

        def search_mode?
          @mode == MODE_SEARCH
        end

        def confirm_mode?
          @mode == MODE_CONFIRM_DELETE
        end

        def has_export_result?
          !@export_result.nil?
        end

        def export_result
          @export_result
        end

        def insert_char(char)
          return unless search_mode?
          @search_buffer += char
        end

        def delete_char
          return unless search_mode?
          @search_buffer = @search_buffer[0..-2]
        end

        def current_session
          return nil if @sessions.empty? || @cursor >= @sessions.length
          @sessions[@cursor]
        end

        # --- View ---

        def view
          lines = []

          # Title bar with filter
          filter_text = " [#{@filter.to_s.upcase}] "
          title = " Session Explorer "
          title_line = "┌#{title}#{filter_text}#{'─' * (@width - title.length - filter_text.length - 2)}┐"
          lines << Styles.modal_title.render(title_line)

          # Search bar
          if search_mode?
            search_display = "Search: #{@search_buffer}_"
          elsif !@search_query.empty?
            search_display = "Search: #{@search_query} (/ to edit, Esc to clear)"
          else
            search_display = "Press / to search"
          end
          search_padding = @width - 2 - visible_length(search_display)
          search_styled = search_mode? ? Styles.help_key.render(search_display) : Styles.timestamp.render(search_display)
          lines << "│ #{search_styled}#{' ' * [search_padding - 1, 0].max}│"
          lines << "├#{'─' * (@width - 2)}┤"

          # Content area
          content_height = @height - 7

          if @sessions.empty?
            lines << "│#{' ' * (@width - 2)}│"
            empty_msg = @search_query.empty? ? "No sessions found" : "No sessions match '#{@search_query}'"
            padding = (@width - 2 - empty_msg.length) / 2
            lines << "│#{' ' * padding}#{empty_msg}#{' ' * (@width - 2 - padding - empty_msg.length)}│"
            (content_height - 2).times { lines << "│#{' ' * (@width - 2)}│" }
          else
            # Header row
            header = format_header
            lines << "│#{header}│"
            lines << "│#{'─' * (@width - 2)}│"

            visible_sessions = @sessions[@scroll_offset, content_height - 2] || []
            visible_sessions.each_with_index do |session, i|
              actual_idx = @scroll_offset + i
              is_selected = actual_idx == @cursor
              lines << "│#{format_session_row(session, is_selected)}│"
            end

            # Pad remaining lines
            remaining = content_height - 2 - visible_sessions.length
            remaining.times { lines << "│#{' ' * (@width - 2)}│" }
          end

          # Confirm delete prompt
          if confirm_mode?
            lines << "├#{'─' * (@width - 2)}┤"
            confirm_msg = "Delete this session? [y/n]"
            confirm_padding = (@width - 2 - confirm_msg.length) / 2
            lines << "│#{' ' * confirm_padding}#{Styles.error.render(confirm_msg)}#{' ' * (@width - 2 - confirm_padding - confirm_msg.length)}│"
          end

          # Export mode prompt
          if export_mode?
            lines << "├#{'─' * (@width - 2)}┤"
            export_msg = "Export as: [j]son  [m]arkdown  [Esc] cancel"
            export_padding = (@width - 2 - export_msg.length) / 2
            lines << "│#{' ' * export_padding}#{Styles.help_key.render(export_msg)}#{' ' * (@width - 2 - export_padding - export_msg.length)}│"
          end

          # Export result message
          if has_export_result?
            lines << "├#{'─' * (@width - 2)}┤"
            result_styled = @export_result.start_with?("Error") ? Styles.error.render(@export_result) : Styles.panel_title.render(@export_result)
            result_padding = (@width - 2 - visible_length(@export_result)) / 2
            lines << "│#{' ' * result_padding}#{result_styled}#{' ' * (@width - 2 - result_padding - visible_length(@export_result))}│"
          end

          # Footer
          lines << "├#{'─' * (@width - 2)}┤"
          help = build_help_text
          help_padding = @width - 2 - visible_length(help)
          lines << "│#{help}#{' ' * [help_padding, 0].max}│"

          # Stats line
          stats = " #{@sessions.length} session#{'s' if @sessions.length != 1}"
          stats += " (#{@filter})" if @filter != FILTER_ALL
          stats_padding = @width - 2 - stats.length
          lines << "│#{Styles.timestamp.render(stats)}#{' ' * [stats_padding, 0].max}│"
          lines << "└#{'─' * (@width - 2)}┘"

          lines.join("\n")
        end

        private

        def adjust_scroll
          content_height = @height - 9
          return if content_height <= 0

          if @cursor < @scroll_offset
            @scroll_offset = @cursor
          elsif @cursor >= @scroll_offset + content_height
            @scroll_offset = @cursor - content_height + 1
          end
        end

        def format_header
          po_col = "PO".ljust(15)
          name_col = "Session".ljust(18)
          msgs_col = "Msgs".rjust(5)
          source_col = "Src".center(5)
          time_col = "Updated".rjust(10)

          header = " #{po_col} #{name_col} #{msgs_col} #{source_col} #{time_col} "
          pad = @width - 2 - header.length
          Styles.panel_title.render(header) + " " * [pad, 0].max
        end

        def format_session_row(session, is_selected)
          cursor = is_selected ? "▸" : " "

          po_name = truncate(session[:po_name] || "unknown", 14).ljust(15)
          name = truncate(session[:name] || "Unnamed", 17).ljust(18)
          msg_count = (session[:message_count] || @session_store.message_count(session[:id])).to_s.rjust(5)
          source = (session[:source] || "tui")[0..2].center(5)
          time = format_time(session[:updated_at]).rjust(10)

          content = "#{cursor}#{po_name} #{name} #{msg_count} #{source} #{time}"

          if is_selected
            Styles.help_key.render(content.ljust(@width - 2))
          else
            content.ljust(@width - 2)
          end
        end

        def build_help_text
          case @mode
          when MODE_NORMAL
            parts = [
              "#{Styles.help_key.render('Enter')} select",
              "#{Styles.help_key.render('Tab')} filter",
              "#{Styles.help_key.render('/')} search",
              "#{Styles.help_key.render('x')} export"
            ]
            parts << "#{Styles.help_key.render('d')} delete"
            parts << "#{Styles.help_key.render('Esc')} close"
            " " + parts.join("  ") + " "
          when MODE_SEARCH
            " #{Styles.help_key.render('Enter')} search  #{Styles.help_key.render('Esc')} cancel "
          when MODE_CONFIRM_DELETE
            " #{Styles.help_key.render('y')} yes  #{Styles.help_key.render('n')} no "
          when MODE_EXPORT
            " #{Styles.help_key.render('j')} json  #{Styles.help_key.render('m')} markdown  #{Styles.help_key.render('Esc')} cancel "
          end
        end

        def export_filename(session, ext)
          # Generate a safe filename from session name
          name = session[:name] || "session"
          safe_name = name.gsub(/[^a-zA-Z0-9_-]/, "_").gsub(/_+/, "_")[0, 30]
          timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
          "#{safe_name}_#{timestamp}.#{ext}"
        end

        def truncate(str, max)
          return str if str.nil? || str.length <= max
          str[0, max - 1] + "…"
        end

        def visible_length(str)
          str.to_s.gsub(/\e\[[0-9;]*m/, "").length
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
