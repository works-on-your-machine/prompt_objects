# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Displays the conversation history with the active PO
      class Conversation
        attr_accessor :width, :height

        # Glamour style for markdown rendering (dark theme works in all contexts)
        GLAMOUR_STYLE = "dark"

        def initialize
          @po = nil
          @width = 60
          @height = 15
          @scroll_offset = 0
          @pending_message = nil
          @waiting_for_response = false
          @system_message = nil
          @system_message_time = nil
        end

        # Show a temporary system message (auto-clears after display)
        def show_system_message(text)
          @system_message = text
          @system_message_time = Time.now
        end

        def clear_system_message
          @system_message = nil
          @system_message_time = nil
        end

        def set_po(po)
          @po = po
          @scroll_offset = 0
          # Clear pending state when switching POs
          @pending_message = nil
          @waiting_for_response = false
        end

        # Add a message that's being sent (shows immediately before LLM returns)
        def set_pending_message(text)
          @pending_message = text
          @waiting_for_response = true
        end

        # Clear pending state when response arrives
        def clear_pending
          @pending_message = nil
          @waiting_for_response = false
        end

        def waiting?
          @waiting_for_response
        end

        def view_lines(width = @width, height = @height)
          return ["Select a prompt object to start chatting"] unless @po

          lines = []

          # Description (dimmed)
          if @po.description
            desc = @po.description[0, width]
            lines << Styles.thinking.render(desc)
            lines << ""
          end

          # Conversation history
          @po.history.each do |msg|
            msg_lines = format_message(msg, width)
            lines.concat(msg_lines)
          end

          # Show pending message (only if not yet in history)
          if @pending_message && !message_in_history?(@pending_message)
            prefix_text = "You: "
            prefix = Styles.user_message.render(prefix_text)
            prefix_len = prefix_text.length
            wrapped = wrap_text(@pending_message, width - prefix_len)
            lines << "#{prefix}#{wrapped.first}"
            indent = " " * prefix_len
            wrapped[1..].each do |line|
              lines << "#{indent}#{line}"
            end
            lines << ""
          end

          # Show waiting indicator
          if @waiting_for_response
            lines << Styles.thinking.render("  #{@po.name} is thinking...")
            lines << ""
          end

          # Show system message (command feedback)
          if @system_message
            lines << Styles.panel_title.render("  #{@system_message}")
            lines << ""
            # Auto-clear after 5 seconds
            if @system_message_time && (Time.now - @system_message_time) > 5
              clear_system_message
            end
          end

          # If empty history and not waiting
          if @po.history.empty? && !@waiting_for_response && !@pending_message
            lines << ""
            lines << Styles.message_to.render("Press 'i' to enter insert mode and type a message...")
          end

          # Ensure we have enough lines
          while lines.length < height
            lines << ""
          end

          # Return last `height` lines (auto-scroll to bottom)
          # Truncate each line to fit within width
          lines.last(height).map { |line| truncate_line(line, width) }
        end

        def scroll_up
          @scroll_offset += 1
        end

        def scroll_down
          @scroll_offset = [@scroll_offset - 1, 0].max
        end

        private

        def format_message(msg, width)
          lines = []

          case msg[:role]
          when :user
            prefix_text = "You: "
            prefix = Styles.user_message.render(prefix_text)
            prefix_len = prefix_text.length
            content = msg[:content].to_s
            wrapped = wrap_text(content, width - prefix_len)
            lines << "#{prefix}#{wrapped.first}"
            indent = " " * prefix_len
            wrapped[1..].each do |line|
              lines << "#{indent}#{line}"
            end

          when :assistant
            prefix_text = "#{@po.name}: "
            prefix = Styles.assistant_message.render(prefix_text)
            content = msg[:content].to_s
            if content.empty? && msg[:tool_calls]
              # Show tool calls
              msg[:tool_calls].each do |tc|
                lines << Styles.thinking.render("  [calling #{tc.name}...]")
              end
            else
              # Render markdown content with Glamour
              rendered_lines = render_markdown(content, width - 2)
              if rendered_lines.length == 1 && !content.include?("\n") && !looks_like_markdown?(content)
                # Single line, non-markdown: show inline with prefix
                lines << "#{prefix}#{rendered_lines.first}"
              else
                # Multi-line or markdown: show prefix, then content below with indent
                lines << prefix.rstrip
                rendered_lines.each do |line|
                  lines << "  #{line}"
                end
              end
            end

          when :tool
            # Tool results (could show or hide)
            results = msg[:results] || []
            results.each do |r|
              lines << Styles.thinking.render("  [result from #{r[:tool_call_id]}]")
            end
          end

          lines << ""
          lines
        end

        def message_in_history?(text)
          return false unless @po
          @po.history.any? { |msg| msg[:role] == :user && msg[:content] == text }
        end

        def wrap_text(text, width)
          return [""] if text.nil? || text.empty?
          return [""] if width <= 0

          words = text.split(/\s+/)
          lines = []
          current_line = ""

          words.each do |word|
            # Handle words longer than width by splitting them
            while word.length > width
              if current_line.empty?
                lines << word[0, width]
                word = word[width..]
              else
                lines << current_line
                current_line = ""
              end
            end

            if current_line.empty?
              current_line = word
            elsif (current_line.length + word.length + 1) <= width
              current_line += " #{word}"
            else
              lines << current_line
              current_line = word
            end
          end

          lines << current_line unless current_line.empty?
          lines.empty? ? [""] : lines
        end

        # Render markdown content using Glamour
        # Returns an array of lines (already styled with ANSI codes)
        def render_markdown(content, width)
          return [""] if content.nil? || content.empty?
          return [""] if width <= 0

          begin
            # Glamour renders markdown with ANSI codes for styling
            # Use explicit style (not "auto") for non-TTY compatibility
            rendered = Glamour.render(content, style: GLAMOUR_STYLE, width: width)

            # Split into lines and handle any trailing newlines
            lines = rendered.split("\n", -1)

            # Remove leading empty lines (Glamour adds one before content)
            lines.shift while lines.length > 1 && strip_ansi(lines.first).strip.empty?

            # Remove trailing empty lines (Glamour often adds them)
            lines.pop while lines.length > 1 && strip_ansi(lines.last).strip.empty?

            # Strip trailing whitespace from each line (Glamour pads to width)
            lines.map! { |line| rstrip_ansi(line) }

            # Handle lines that are still too wide (code blocks can overflow)
            lines.map! { |line| truncate_ansi_line(line, width) }

            lines.empty? ? [""] : lines
          rescue StandardError => e
            # Fallback to simple wrapping if Glamour fails
            warn "Glamour rendering failed: #{e.message}" if ENV["DEBUG"]
            wrap_text(content, width)
          end
        end

        # Strip ANSI codes from a string (for length calculations)
        def strip_ansi(str)
          str.gsub(/\e\[[0-9;]*m/, "")
        end

        # Strip trailing whitespace while preserving ANSI codes
        def rstrip_ansi(line)
          # Glamour wraps each space in ANSI codes like: \e[38;5;252m \e[0m
          # Remove trailing sequences of (ANSI code + space)* + optional reset
          result = line.dup

          # Keep removing trailing ANSI-styled whitespace until stable
          loop do
            # Pattern matches: ANSI code followed by whitespace, at end of string
            # Also matches trailing resets and plain whitespace
            new_result = result
              .sub(/(\e\[[0-9;]*m\s+)+\e\[0m$/, "") # styled spaces + reset
              .sub(/(\e\[[0-9;]*m)+$/, "")          # trailing ANSI codes
              .sub(/\s+$/, "")                       # plain trailing whitespace

            break if new_result == result
            result = new_result
          end

          result
        end

        # Check if content looks like markdown (has markdown syntax)
        def looks_like_markdown?(content)
          return false if content.nil? || content.empty?

          # Check for common markdown patterns
          content.match?(/
            ^\#{1,6}\s    |  # Headers
            \*\*[^*]+\*\* |  # Bold
            \*[^*]+\*     |  # Italic
            __[^_]+__     |  # Bold (alt)
            _[^_]+_       |  # Italic (alt)
            ^```          |  # Code block
            `[^`]+`       |  # Inline code
            ^\s*[-*+]\s   |  # Bullet list
            ^\s*\d+\.\s   |  # Numbered list
            ^\s*>         |  # Blockquote
            \[[^\]]+\]\(     # Links
          /x)
        end

        # Truncate a line with ANSI codes to fit within width
        def truncate_ansi_line(line, width)
          return line if width <= 0

          visible_length = 0
          result = ""
          i = 0

          while i < line.length
            if line[i] == "\e"
              # ANSI escape sequence - copy it without counting
              end_idx = line.index("m", i)
              if end_idx
                result += line[i..end_idx]
                i = end_idx + 1
              else
                i += 1
              end
            else
              if visible_length < width
                result += line[i]
                visible_length += 1
              end
              i += 1
            end
          end

          # Add reset if we truncated and line had ANSI codes
          result += "\e[0m" if visible_length >= width && line.include?("\e[")
          result
        end

        # Truncate a line to fit within width (accounting for ANSI codes)
        def truncate_line(line, width)
          return line if width <= 0

          # Strip ANSI codes to get visible length
          visible = line.gsub(/\e\[[0-9;]*m/, '')
          return line if visible.length <= width

          # Need to truncate - this is tricky with ANSI codes
          # Simple approach: rebuild string char by char
          result = ""
          visible_count = 0
          i = 0

          while i < line.length && visible_count < width
            if line[i] == "\e"
              # ANSI escape sequence - copy it all
              end_idx = line.index('m', i)
              if end_idx
                result += line[i..end_idx]
                i = end_idx + 1
              else
                i += 1
              end
            else
              result += line[i]
              visible_count += 1
              i += 1
            end
          end

          result + "\e[0m"  # Reset at end
        end
      end
    end
  end
end
