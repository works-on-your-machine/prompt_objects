# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Displays the conversation history with the active PO
      class Conversation
        attr_accessor :width, :height

        def initialize
          @po = nil
          @width = 60
          @height = 15
          @scroll_offset = 0
          @pending_message = nil
          @waiting_for_response = false
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
            prefix = Styles.user_message.render("You: ")
            lines << "#{prefix}#{wrap_text(@pending_message, width - 5).first}"
            wrap_text(@pending_message, width - 5)[1..].each do |line|
              lines << "     #{line}"
            end
            lines << ""
          end

          # Show waiting indicator
          if @waiting_for_response
            lines << Styles.thinking.render("  #{@po.name} is thinking...")
            lines << ""
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
            prefix = Styles.user_message.render("You: ")
            content = msg[:content].to_s
            lines << "#{prefix}#{wrap_text(content, width - 5).first}"
            wrap_text(content, width - 5)[1..].each do |line|
              lines << "     #{line}"
            end

          when :assistant
            prefix = Styles.assistant_message.render("#{@po.name}: ")
            content = msg[:content].to_s
            if content.empty? && msg[:tool_calls]
              # Show tool calls
              msg[:tool_calls].each do |tc|
                lines << Styles.thinking.render("  [calling #{tc.name}...]")
              end
            else
              lines << "#{prefix}#{wrap_text(content, width - 5).first}"
              wrap_text(content, width - 5)[1..].each do |line|
                lines << "     #{line}"
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
