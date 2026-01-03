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
          return ["  (no messages)"] if entries.empty?

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
          time = entry[:timestamp].strftime("%H:%M:%S")
          from = entry[:from]
          to = entry[:to]
          msg = truncate_message(entry[:message], width - 25)

          time_styled = Styles.timestamp.render(time)
          from_styled = Styles.message_from.render(from)
          to_styled = Styles.message_to.render(to)

          "#{time_styled} #{from_styled}#{to_styled}: #{msg}"
        end

        def truncate_message(msg, max_length)
          str = msg.to_s.gsub(/\s+/, " ").strip
          return str if str.length <= max_length

          str[0, max_length - 3] + "..."
        end
      end
    end
  end
end
