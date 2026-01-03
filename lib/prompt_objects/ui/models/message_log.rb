# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Displays the message bus log in real-time
      class MessageLog
        attr_accessor :width

        def initialize(bus:)
          @bus = bus
          @width = 40
          @scroll_offset = 0
        end

        def view_lines(width = @width, height = 10)
          entries = @bus.recent(height)
          return ["(no messages yet)"] if entries.empty?

          entries.map do |entry|
            format_entry(entry, width)
          end
        end

        def scroll_up
          @scroll_offset = [@scroll_offset + 1, @bus.log.length - 1].min
        end

        def scroll_down
          @scroll_offset = [@scroll_offset - 1, 0].max
        end

        private

        def format_entry(entry, width)
          time = entry[:timestamp].strftime("%H:%M")
          from = entry[:from].to_s[0, 8]
          to = entry[:to].to_s[0, 8]
          msg = truncate_message(entry[:message], width - 22)

          time_styled = Styles.timestamp.render(time)
          from_styled = Styles.message_from.render(from)
          arrow = Styles.message_to.render("")
          to_styled = Styles.message_to.render(to)

          "#{time_styled} #{from_styled}#{arrow}#{to_styled}"
        end

        def truncate_message(msg, max_length)
          return "" if max_length <= 0
          str = msg.to_s.gsub(/\s+/, " ").strip
          return str if str.length <= max_length
          str[0, max_length - 1] + "…"
        end
      end
    end
  end
end
