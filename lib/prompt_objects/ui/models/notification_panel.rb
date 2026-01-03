# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Panel showing pending HumanRequests across all POs
      class NotificationPanel
        attr_reader :width, :height
        attr_accessor :visible

        def initialize(human_queue:)
          @human_queue = human_queue
          @width = 60
          @height = 12
          @cursor = 0
          @visible = false
        end

        def set_dimensions(width, height)
          @width = [width - 10, 40].max
          @height = [height - 6, 8].max
        end

        def toggle
          @visible = !@visible
          @cursor = 0 if @visible
        end

        def show
          @visible = true
          @cursor = 0
        end

        def hide
          @visible = false
        end

        def move_up
          @cursor = [@cursor - 1, 0].max
        end

        def move_down
          requests = @human_queue.all_pending
          @cursor = [@cursor + 1, requests.length - 1].max
        end

        def selected_request
          requests = @human_queue.all_pending
          return nil if requests.empty? || @cursor >= requests.length
          requests[@cursor]
        end

        def count
          @human_queue.count
        end

        def empty?
          @human_queue.count == 0
        end

        def view
          requests = @human_queue.all_pending
          lines = []

          # Title bar
          count_str = requests.empty? ? "No pending requests" : "#{requests.length} pending"
          title = " NOTIFICATIONS (#{count_str}) "
          title_line = "┌#{title}#{'─' * (@width - title.length - 2)}┐"
          lines << Styles.modal_title.render(title_line)

          # Content area
          content_height = @height - 4

          if requests.empty?
            lines << "│#{' ' * (@width - 2)}│"
            empty_msg = "No pending requests from any PO"
            padding = (@width - 2 - empty_msg.length) / 2
            lines << "│#{' ' * padding}#{Styles.message_to.render(empty_msg)}#{' ' * (@width - 2 - padding - empty_msg.length)}│"
            (content_height - 2).times { lines << "│#{' ' * (@width - 2)}│" }
          else
            lines << "│#{' ' * (@width - 2)}│"

            requests.each_with_index do |req, i|
              break if i >= content_height - 1

              cursor_indicator = i == @cursor ? "▸" : " "
              cursor_styled = i == @cursor ? Styles.help_key.render(cursor_indicator) : cursor_indicator

              capability = truncate(req.capability.to_s, 12)
              question = truncate(req.question.to_s, @width - 30)
              age = req.age_string

              # Style based on selection
              if i == @cursor
                cap_styled = Styles.help_key.render(capability)
                q_styled = question
              else
                cap_styled = Styles.message_from.render(capability)
                q_styled = Styles.message_to.render(question)
              end

              line_content = "#{cursor_styled} #{cap_styled}  #{q_styled}"
              age_styled = Styles.timestamp.render(age.rjust(4))

              # Calculate visible length
              visible_len = visible_length(line_content) + visible_length(age_styled) + 2
              padding = @width - 4 - visible_len

              lines << "│ #{line_content}#{' ' * [padding, 1].max}#{age_styled} │"
            end

            # Pad remaining lines
            remaining = content_height - 1 - [requests.length, content_height - 1].min
            remaining.times { lines << "│#{' ' * (@width - 2)}│" }
          end

          # Bottom bar
          lines << "├#{'─' * (@width - 2)}┤"
          if requests.empty?
            help = " [Esc] Close "
          else
            help = " [Enter] Respond  [j/k] Navigate  [Esc] Close "
          end
          help_padding = @width - 2 - help.length
          lines << "│#{Styles.status_bar.render(help)}#{' ' * help_padding}│"
          lines << "└#{'─' * (@width - 2)}┘"

          lines.join("\n")
        end

        private

        def truncate(str, max)
          return str if str.length <= max
          str[0, max - 1] + "…"
        end

        def visible_length(str)
          str.gsub(/\e\[[0-9;]*m/, '').length
        end
      end
    end
  end
end
