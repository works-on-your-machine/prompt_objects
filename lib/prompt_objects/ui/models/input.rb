# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Text input component at the bottom of the screen
      class Input
        attr_reader :text
        attr_accessor :width

        def initialize
          @text = ""
          @cursor = 0
          @width = 80
          @history = []
          @history_index = -1
        end

        def empty?
          @text.empty?
        end

        def clear
          @text = ""
          @cursor = 0
        end

        def submit
          return nil if @text.empty?

          submitted = @text
          @history << submitted
          @text = ""
          @cursor = 0
          @history_index = -1
          submitted
        end

        def handle_key(msg)
          char = msg.char.to_s

          case
          when msg.backspace?
            delete_char
          when msg.left? && !msg.ctrl?
            move_left
          when msg.right? && !msg.ctrl?
            move_right
          when msg.ctrl? && char == "a"
            @cursor = 0
          when msg.ctrl? && char == "e"
            @cursor = @text.length
          when msg.up?
            history_prev
          when msg.down?
            history_next
          when msg.ctrl? && char == "u"
            # Clear line
            @text = ""
            @cursor = 0
          when msg.ctrl? && char == "k"
            # Kill to end of line
            @text = @text[0, @cursor]
          when msg.runes? && !char.empty?
            # Regular character input
            insert_char(char)
          end
        end

        def view(width = @width)
          prompt = Styles.input_prompt.render("You: ")
          input_width = width - 5

          # Show text with cursor
          display_text = @text
          if display_text.length > input_width - 1
            # Scroll to show cursor
            start = [@cursor - input_width + 10, 0].max
            display_text = display_text[start, input_width - 1]
          end

          # Add cursor indicator
          cursor_pos = [@cursor, display_text.length].min
          before = display_text[0, cursor_pos] || ""
          after = display_text[cursor_pos..] || ""
          cursor_char = ""

          text_styled = Styles.input_text.render("#{before}#{cursor_char}#{after}")

          "#{prompt}#{text_styled}"
        end

        private

        def insert_char(char)
          return if char.nil? || char.empty?

          @text = @text[0, @cursor].to_s + char + @text[@cursor..].to_s
          @cursor += char.length
        end

        def delete_char
          return if @cursor == 0

          @text = @text[0, @cursor - 1].to_s + @text[@cursor..].to_s
          @cursor -= 1
        end

        def delete_forward
          return if @cursor >= @text.length

          @text = @text[0, @cursor].to_s + @text[@cursor + 1..].to_s
        end

        def move_left
          @cursor = [@cursor - 1, 0].max
        end

        def move_right
          @cursor = [@cursor + 1, @text.length].min
        end

        def history_prev
          return if @history.empty?

          if @history_index == -1
            @history_index = @history.length - 1
          elsif @history_index > 0
            @history_index -= 1
          end

          @text = @history[@history_index] || ""
          @cursor = @text.length
        end

        def history_next
          return if @history_index == -1

          @history_index += 1
          if @history_index >= @history.length
            @history_index = -1
            @text = ""
          else
            @text = @history[@history_index] || ""
          end
          @cursor = @text.length
        end

      end
    end
  end
end
