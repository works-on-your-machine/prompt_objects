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

        # Insert text at cursor
        def insert(char)
          return if char.nil? || char.empty?
          @text = @text[0, @cursor].to_s + char + @text[@cursor..].to_s
          @cursor += char.length
        end

        def delete_char
          return if @cursor == 0
          @text = @text[0, @cursor - 1].to_s + @text[@cursor..].to_s
          @cursor -= 1
        end

        def move_left
          @cursor = [@cursor - 1, 0].max
        end

        def move_right
          @cursor = [@cursor + 1, @text.length].min
        end

        def cursor_home
          @cursor = 0
        end

        def cursor_end
          @cursor = @text.length
        end

        def kill_to_end
          @text = @text[0, @cursor]
        end

        def view(width = @width, mode: :normal)
          # Mode indicator
          if mode == :insert
            mode_indicator = Styles.success.render("-- INSERT --")
            prompt = "#{mode_indicator} "
          else
            prompt = Styles.input_prompt.render("[i]nsert ")
          end

          # Show text with cursor
          display_text = @text
          input_width = width - prompt.gsub(/\e\[[0-9;]*m/, '').length - 2

          if display_text.length > input_width - 1
            # Scroll to show cursor
            start = [@cursor - input_width + 10, 0].max
            display_text = display_text[start, input_width - 1]
          end

          # Add cursor indicator (block in insert mode)
          if mode == :insert
            cursor_pos = [@cursor, display_text.length].min
            before = display_text[0, cursor_pos] || ""
            after = display_text[cursor_pos..] || ""
            cursor_char = "\e[7m \e[0m"  # Inverted space as cursor
            text_part = "#{before}#{cursor_char}#{after}"
          else
            text_part = display_text
          end

          text_styled = Styles.input_text.render(text_part)
          "#{prompt}#{text_styled}"
        end
      end
    end
  end
end
