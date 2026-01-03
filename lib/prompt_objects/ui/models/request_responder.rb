# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Modal for responding to a HumanRequest
      class RequestResponder
        attr_reader :request, :width, :height
        attr_accessor :visible

        def initialize(request:)
          @request = request
          @width = 60
          @height = 15
          @cursor = 0
          @input_text = ""
          @input_mode = false
          @visible = true
        end

        def set_dimensions(width, height)
          @width = [width - 10, 50].max
          @height = [height - 4, 10].max
        end

        def has_options?
          @request.options && !@request.options.empty?
        end

        def move_up
          return unless has_options?
          @cursor = [@cursor - 1, 0].max
        end

        def move_down
          return unless has_options?
          @cursor = [@cursor + 1, @request.options.length - 1].min
        end

        def enter_input_mode
          @input_mode = true unless has_options?
        end

        def exit_input_mode
          @input_mode = false
        end

        def input_mode?
          @input_mode
        end

        def insert_char(char)
          return unless @input_mode
          @input_text += char
        end

        def delete_char
          return unless @input_mode
          @input_text = @input_text[0..-2] unless @input_text.empty?
        end

        def clear_input
          @input_text = ""
        end

        # Get the response value (selected option or input text)
        def response_value
          if has_options?
            @request.options[@cursor]
          else
            @input_text
          end
        end

        def can_submit?
          if has_options?
            true
          else
            !@input_text.empty?
          end
        end

        def view
          lines = []

          # Title bar
          cap_name = truncate(@request.capability.to_s, 20)
          title = " #{cap_name} asks "
          title_line = "┌#{title}#{'─' * (@width - title.length - 2)}┐"
          lines << Styles.modal_title.render(title_line)

          # Question
          lines << "│#{' ' * (@width - 2)}│"
          question_lines = wrap_text(@request.question, @width - 6)
          question_lines.each do |q_line|
            padded = pad_line("  #{q_line}", @width - 4)
            lines << "│ #{padded} │"
          end
          lines << "│#{' ' * (@width - 2)}│"

          # Options or text input
          if has_options?
            lines << "│ #{Styles.section_header.render('Choose one:')}#{' ' * (@width - 15)}│"
            @request.options.each_with_index do |opt, i|
              indicator = i == @cursor ? "▸" : " "
              indicator_styled = i == @cursor ? Styles.help_key.render(indicator) : indicator
              opt_styled = i == @cursor ? Styles.success.render(opt) : opt
              line_content = "#{indicator_styled} #{opt_styled}"
              padded = pad_line("  #{line_content}", @width - 4)
              lines << "│ #{padded} │"
            end
          else
            lines << "│ #{Styles.section_header.render('Your response:')}#{' ' * (@width - 18)}│"
            if @input_mode
              cursor_char = "█"
              input_display = "  > #{@input_text}#{cursor_char}"
            else
              if @input_text.empty?
                input_display = Styles.message_to.render("  (Press Enter to type...)")
              else
                input_display = "  > #{@input_text}"
              end
            end
            padded = pad_line(input_display, @width - 4)
            lines << "│ #{padded} │"
          end

          # Pad to height
          content_lines = lines.length
          while lines.length < @height - 3
            lines << "│#{' ' * (@width - 2)}│"
          end

          # Bottom bar
          lines << "├#{'─' * (@width - 2)}┤"
          if has_options?
            help = " [Enter] Select  [j/k] Navigate  [Esc] Cancel "
          else
            if @input_mode
              help = " [Enter] Submit  [Esc] Cancel "
            else
              help = " [Enter] Type  [Esc] Cancel "
            end
          end
          help_padded = pad_line(help, @width - 2)
          lines << "│#{Styles.status_bar.render(help_padded)}│"
          lines << "└#{'─' * (@width - 2)}┘"

          lines.join("\n")
        end

        private

        def truncate(str, max)
          return str if str.length <= max
          str[0, max - 1] + "…"
        end

        def pad_line(text, width)
          visible_len = text.gsub(/\e\[[0-9;]*m/, '').length
          padding = [width - visible_len, 0].max
          "#{text}#{' ' * padding}"
        end

        def wrap_text(text, width)
          return [""] if text.nil? || text.empty?

          words = text.split(/\s+/)
          lines = []
          current = ""

          words.each do |word|
            if current.empty?
              current = word
            elsif current.length + word.length + 1 <= width
              current += " #{word}"
            else
              lines << current
              current = word
            end
          end

          lines << current unless current.empty?
          lines.empty? ? [""] : lines
        end
      end
    end
  end
end
