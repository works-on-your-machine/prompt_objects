# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Detail view for a single Prompt Object showing sessions and pending requests
      class PODetail
        attr_reader :width, :height, :selected_session

        # Focus areas
        FOCUS_SESSIONS = :sessions
        FOCUS_REQUESTS = :requests

        def initialize(po:, session_store: nil, human_queue: nil)
          @po = po
          @session_store = session_store
          @human_queue = human_queue
          @width = 80
          @height = 24
          @cursor = 0
          @scroll_offset = 0
          @focus = FOCUS_SESSIONS

          # Cache for expensive queries
          @sessions_cache = nil
          @requests_cache = nil
          refresh_cache
        end

        def refresh_cache
          @sessions_cache = nil
          @requests_cache = nil
        end

        def set_dimensions(width, height)
          @width = width
          @height = height
        end

        def po
          @po
        end

        # Navigation
        def move_up
          @cursor = [@cursor - 1, 0].max
          adjust_scroll
        end

        def move_down
          max_cursor = case @focus
                       when FOCUS_SESSIONS then [sessions.length - 1, 0].max
                       when FOCUS_REQUESTS then [pending_requests.length - 1, 0].max
                       else 0
                       end
          @cursor = [@cursor + 1, max_cursor].min
          adjust_scroll
        end

        def cycle_focus
          focuses = [FOCUS_SESSIONS]
          focuses << FOCUS_REQUESTS if pending_requests.any?

          idx = focuses.index(@focus) || 0
          @focus = focuses[(idx + 1) % focuses.length]
          @cursor = 0
          @scroll_offset = 0
        end

        def selected_session
          return nil unless @focus == FOCUS_SESSIONS
          sessions[@cursor]
        end

        def selected_request
          return nil unless @focus == FOCUS_REQUESTS
          pending_requests[@cursor]
        end

        def view
          lines = []

          # Header with PO info
          lines.concat(render_header)

          # Content area
          content_height = @height - 10  # Header takes ~8 lines, status bar 2
          lines.concat(render_content(content_height))

          # Pending requests summary (if any and not in focus)
          if @focus != FOCUS_REQUESTS && pending_requests.any?
            lines << ""
            lines << Styles.warning.render("  [!] #{pending_requests.length} pending request(s) - press Tab to view")
          end

          # Pad to height
          while lines.length < @height - 1
            lines << ""
          end

          # Status bar
          lines << render_status_bar

          lines.join("\n")
        end

        private

        def sessions
          return [] unless @session_store
          return @sessions_cache if @sessions_cache

          @sessions_cache = @session_store.list_sessions(po_name: @po.name) rescue []
        end

        def pending_requests
          return [] unless @human_queue
          return @requests_cache if @requests_cache

          @requests_cache = @human_queue.pending_for(@po.name) rescue []
        end

        def render_header
          lines = []

          # State indicator
          state_icon = case @po.state
                       when :working then "◐"
                       when :active then "●"
                       when :waiting_for_human then "⚠"
                       else "○"
                       end

          # Title line
          title = " ← #{state_icon} #{@po.name} "
          lines << Styles.panel_title.render("═" * 2 + title + "═" * [@width - title.length - 4, 0].max)

          # Description
          desc = @po.description || "(no description)"
          lines << ""
          lines << "  #{desc[0, @width - 6]}"

          # Capabilities summary
          caps = (@po.config["capabilities"] || []).first(5)
          caps_str = caps.join(", ")
          caps_str += "..." if (@po.config["capabilities"] || []).length > 5
          caps_str = "(none)" if caps_str.empty?
          lines << Styles.thinking.render("  Capabilities: #{caps_str[0, @width - 18]}")

          lines << ""
          lines
        end

        def render_content(height)
          case @focus
          when FOCUS_SESSIONS
            render_session_list(height)
          when FOCUS_REQUESTS
            render_request_list(height)
          else
            render_session_list(height)
          end
        end

        def render_session_list(height)
          lines = []
          sess = sessions

          # Section header
          header = " Sessions (#{sess.length}) "
          header_line = "─" * 2 + header + "─" * [@width - header.length - 6, 0].max
          lines << (@focus == FOCUS_SESSIONS ? Styles.help_key.render(header_line) : header_line)
          lines << ""

          if sess.empty?
            lines << Styles.thinking.render("  No sessions yet")
            lines << ""
            lines << Styles.message_to.render("  Press 'n' to create a new session")
          else
            visible_height = height - 4
            visible = sess[@scroll_offset, visible_height] || []

            visible.each_with_index do |session, i|
              actual_idx = @scroll_offset + i
              is_selected = @focus == FOCUS_SESSIONS && actual_idx == @cursor
              lines << render_session_row(session, is_selected)
            end

            # Scroll indicator
            if sess.length > visible_height
              if @scroll_offset > 0
                lines[2] = "  ↑ more above" + lines[2][14..]
              end
              if @scroll_offset + visible_height < sess.length
                lines << Styles.thinking.render("  ↓ more below (#{sess.length - @scroll_offset - visible_height})")
              end
            end
          end

          # Pad to height
          while lines.length < height
            lines << ""
          end

          lines.first(height)
        end

        def render_session_row(session, selected)
          source = session[:source] || "tui"
          badge = case source
                  when "mcp" then Styles.panel_title.render("[MCP]")
                  when "api" then Styles.panel_title.render("[API]")
                  when "web" then Styles.panel_title.render("[WEB]")
                  else "[TUI]"
                  end

          name = session[:name] || "Unnamed"
          name = truncate(name, 25)
          msg_count = session[:message_count] || 0
          time = format_relative_time(session[:updated_at])

          cursor_char = selected ? "▸" : " "
          line = "#{cursor_char} #{badge} #{name.ljust(27)} #{msg_count.to_s.rjust(3)} msgs  #{time}"

          if selected
            Styles.help_key.render(line)
          else
            "  " + line[2..]
          end
        end

        def render_request_list(height)
          lines = []
          reqs = pending_requests

          # Section header
          header = " Pending Requests (#{reqs.length}) "
          header_line = "─" * 2 + header + "─" * [@width - header.length - 6, 0].max
          lines << Styles.warning.render(header_line)
          lines << ""

          if reqs.empty?
            lines << Styles.thinking.render("  No pending requests")
          else
            reqs.each_with_index do |req, i|
              is_selected = i == @cursor
              lines << render_request_row(req, is_selected)
              lines << ""
            end
          end

          # Pad to height
          while lines.length < height
            lines << ""
          end

          lines.first(height)
        end

        def render_request_row(request, selected)
          cursor_char = selected ? "▸" : " "
          question = truncate(request.question, @width - 10)
          age = format_relative_time(request.timestamp)

          line = "#{cursor_char} #{question}"
          line += " (#{age})" if age != "---"

          if selected
            Styles.warning.render(line)
          else
            "  " + line[2..]
          end
        end

        def adjust_scroll
          visible_height = @height - 14
          if @cursor < @scroll_offset
            @scroll_offset = @cursor
          elsif @cursor >= @scroll_offset + visible_height
            @scroll_offset = @cursor - visible_height + 1
          end
        end

        def format_relative_time(time)
          return "---" unless time

          diff = Time.now - time
          if diff < 60
            "now"
          elsif diff < 3600
            "#{(diff / 60).to_i}m ago"
          elsif diff < 86400
            "#{(diff / 3600).to_i}h ago"
          else
            time.strftime("%m/%d")
          end
        end

        def truncate(str, max)
          return "" if str.nil?
          str.length <= max ? str : str[0, max - 1] + "…"
        end

        def render_status_bar
          parts = [
            "#{Styles.help_key.render('Esc')} back",
            "#{Styles.help_key.render('↑↓')} navigate",
            "#{Styles.help_key.render('Enter')} open session",
            "#{Styles.help_key.render('n')} new session"
          ]

          if pending_requests.any?
            parts << "#{Styles.help_key.render('Tab')} toggle focus"
          end

          Styles.status_bar.render(parts.join("  "))
        end
      end
    end
  end
end
