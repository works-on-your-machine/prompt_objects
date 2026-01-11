# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Main dashboard showing PO cards grid and activity feed
      class Dashboard
        attr_reader :width, :height
        attr_accessor :selected_po

        # Card dimensions
        CARD_WIDTH = 24
        CARD_HEIGHT = 6

        def initialize(registry:, session_store: nil, human_queue: nil)
          @registry = registry
          @session_store = session_store
          @human_queue = human_queue
          @width = 80
          @height = 24
          @cursor_row = 0
          @cursor_col = 0
          @cards_per_row = 3
          @focus = :cards  # :cards or :activity
          @activity_scroll = 0

          # Cache for expensive queries (refreshed on demand)
          @session_counts = {}
          @pending_counts = {}
          @activity_cache = nil
          refresh_cache
        end

        def refresh_cache
          @session_counts = {}
          @pending_counts = {}
          @activity_cache = nil
        end

        def set_dimensions(width, height)
          @width = width
          @height = height
          # Recalculate cards per row based on width
          # Activity feed takes ~30 chars, cards need CARD_WIDTH + 2 padding each
          available_width = @width - 32  # Reserve space for activity feed
          @cards_per_row = [(available_width / (CARD_WIDTH + 2)), 1].max
        end

        # Navigation
        def move_up
          if @focus == :cards
            @cursor_row = [@cursor_row - 1, 0].max
          else
            @activity_scroll = [@activity_scroll - 1, 0].max
          end
        end

        def move_down
          if @focus == :cards
            max_row = (prompt_objects.length - 1) / @cards_per_row
            @cursor_row = [@cursor_row + 1, max_row].min
          else
            @activity_scroll += 1
          end
        end

        def move_left
          @cursor_col = [@cursor_col - 1, 0].max if @focus == :cards
        end

        def move_right
          @cursor_col = [@cursor_col + 1, @cards_per_row - 1].min if @focus == :cards
        end

        def toggle_focus
          @focus = @focus == :cards ? :activity : :cards
        end

        def selected_po
          idx = @cursor_row * @cards_per_row + @cursor_col
          pos = prompt_objects
          idx < pos.length ? pos[idx] : nil
        end

        def view
          lines = []

          # Calculate layout
          activity_width = 30
          cards_width = @width - activity_width - 3
          content_height = @height - 2  # Status bar

          # Render side by side
          card_lines = render_cards_area(cards_width, content_height)
          activity_lines = render_activity_area(activity_width, content_height)

          # Combine horizontally
          content_height.times do |i|
            card_line = card_lines[i] || ""
            activity_line = activity_lines[i] || ""

            # Pad card line to width
            card_visible = card_line.gsub(/\e\[[0-9;]*m/, '').length
            card_padded = card_line + (' ' * [cards_width - card_visible, 0].max)

            lines << "#{card_padded} │ #{activity_line}"
          end

          # Status bar
          lines << render_status_bar

          lines.join("\n")
        end

        private

        def prompt_objects
          @registry.prompt_objects
        end

        def render_cards_area(width, height)
          lines = []
          pos = prompt_objects

          if pos.empty?
            lines << ""
            lines << Styles.message_to.render("  No Prompt Objects found")
            lines << ""
            lines << Styles.thinking.render("  Create .md files in the objects/ directory")
            while lines.length < height
              lines << ""
            end
            return lines
          end

          # Group POs into rows
          rows = pos.each_slice(@cards_per_row).to_a

          rows.each_with_index do |row_pos, row_idx|
            # Render each card in this row
            card_renders = row_pos.each_with_index.map do |po, col_idx|
              is_selected = @focus == :cards && row_idx == @cursor_row && col_idx == @cursor_col
              render_card(po, is_selected)
            end

            # Combine cards horizontally (each card is CARD_HEIGHT lines)
            CARD_HEIGHT.times do |line_idx|
              row_line = card_renders.map { |card| card[line_idx] || "" }.join("  ")
              lines << row_line
            end

            # Add spacing between rows
            lines << ""
          end

          # Pad to height
          while lines.length < height
            lines << ""
          end

          lines.first(height)
        end

        def render_card(po, selected)
          lines = []
          style = selected ? Styles.help_key : Styles.message_to
          inner_width = CARD_WIDTH - 4

          # State indicator
          state_icon = case po.state
                       when :working then "◐"
                       when :active then "●"
                       when :waiting_for_human then "⚠"
                       else "○"
                       end

          # Top border
          if selected
            lines << Styles.help_key.render("┌#{'─' * (CARD_WIDTH - 2)}┐")
          else
            lines << "┌#{'─' * (CARD_WIDTH - 2)}┐"
          end

          # Name line
          name = truncate(po.name, inner_width - 3)
          name_line = "│ #{state_icon} #{name}"
          lines << pad_box_line(name_line, CARD_WIDTH, selected)

          # Session count
          session_count = session_count_for(po.name)
          pending = pending_count_for(po.name)
          info = "#{session_count} session#{'s' if session_count != 1}"
          if pending > 0
            info += " " + Styles.warning.render("[!#{pending}]")
          end
          info_line = "│ #{info}"
          lines << pad_box_line(info_line, CARD_WIDTH, selected)

          # Description (truncated)
          desc = truncate(po.description || "(no description)", inner_width)
          desc_line = "│ #{Styles.thinking.render(desc)}"
          lines << pad_box_line(desc_line, CARD_WIDTH, selected)

          # Empty line
          lines << pad_box_line("│", CARD_WIDTH, selected)

          # Bottom border
          if selected
            lines << Styles.help_key.render("└#{'─' * (CARD_WIDTH - 2)}┘")
          else
            lines << "└#{'─' * (CARD_WIDTH - 2)}┘"
          end

          lines
        end

        def pad_box_line(line, width, selected)
          visible_len = line.gsub(/\e\[[0-9;]*m/, '').length
          padding = [width - visible_len - 1, 0].max
          content = "#{line}#{' ' * padding}│"
          selected ? Styles.help_key.render(content.gsub(/\e\[[0-9;]*m/, '')) : content
        end

        def render_activity_area(width, height)
          lines = []
          inner_width = width - 2

          # Header
          header = " Recent Activity "
          header_line = "─" * ((inner_width - header.length) / 2) + header
          header_line += "─" * (inner_width - header_line.length)
          lines << (@focus == :activity ? Styles.help_key.render(header_line) : Styles.section_header.render(header_line))

          # Get recent sessions as activity
          activities = fetch_recent_activity
          if activities.empty?
            lines << ""
            lines << Styles.thinking.render("No recent activity")
          else
            activities.each do |activity|
              line = format_activity(activity, inner_width)
              lines << line
            end
          end

          # Pad to height
          while lines.length < height
            lines << ""
          end

          lines.first(height)
        end

        def fetch_recent_activity
          return [] unless @session_store

          # Use cached activity if available
          return @activity_cache if @activity_cache

          # Get recently updated sessions
          sessions = @session_store.list_all_sessions(limit: 15) rescue []

          @activity_cache = sessions.map do |session|
            {
              po_name: session[:po_name],
              session_name: session[:name] || "Unnamed",
              source: session[:source] || "tui",
              time: session[:updated_at],
              message_count: session[:message_count] || 0
            }
          end
        end

        def format_activity(activity, width)
          time_str = format_relative_time(activity[:time])
          source = source_badge(activity[:source])
          po = truncate(activity[:po_name], 10)

          "#{time_str} #{source} #{po}"
        end

        def source_badge(source)
          case source
          when "mcp" then Styles.panel_title.render("[MCP]")
          when "api" then Styles.panel_title.render("[API]")
          else "[TUI]"
          end
        end

        def format_relative_time(time)
          return "---" unless time

          diff = Time.now - time
          if diff < 60
            "now".rjust(5)
          elsif diff < 3600
            "#{(diff / 60).to_i}m".rjust(5)
          elsif diff < 86400
            "#{(diff / 3600).to_i}h".rjust(5)
          else
            time.strftime("%m/%d").rjust(5)
          end
        end

        def session_count_for(po_name)
          return 0 unless @session_store

          # Use cached count if available
          return @session_counts[po_name] if @session_counts.key?(po_name)

          @session_counts[po_name] = (@session_store.list_sessions(po_name: po_name) rescue []).length
        end

        def pending_count_for(po_name)
          return 0 unless @human_queue

          # Use cached count if available
          return @pending_counts[po_name] if @pending_counts.key?(po_name)

          @pending_counts[po_name] = (@human_queue.pending_for(po_name) rescue []).length
        end

        def truncate(str, max)
          return "" if str.nil?
          str.length <= max ? str : str[0, max - 1] + "…"
        end

        def render_status_bar
          # Count total pending notifications
          total_pending = 0
          if @human_queue
            total_pending = @human_queue.count rescue 0
          end

          notif_label = total_pending > 0 ? "N (#{total_pending})" : "N"

          parts = [
            "#{Styles.help_key.render('↑↓←→')} navigate",
            "#{Styles.help_key.render('Enter')} select",
            "#{Styles.help_key.render('Tab')} focus",
            "#{Styles.help_key.render(notif_label)} notifications",
            "#{Styles.help_key.render('q')} quit"
          ]

          Styles.status_bar.render(parts.join("  "))
        end
      end
    end
  end
end
