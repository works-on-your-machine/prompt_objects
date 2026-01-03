# frozen_string_literal: true

module PromptObjects
  # Message bus for routing and logging all inter-capability communication.
  # This makes the semantic binding visible - you can see natural language
  # being transformed into capability calls.
  class MessageBus
    attr_reader :log

    def initialize
      @log = []
      @subscribers = []
    end

    # Log a message between capabilities.
    # @param from [String] Source capability name
    # @param to [String] Destination capability name
    # @param message [String, Hash] The message content
    # @return [Hash] The log entry
    def publish(from:, to:, message:)
      entry = {
        timestamp: Time.now,
        from: from,
        to: to,
        message: truncate_message(message)
      }

      @log << entry
      notify_subscribers(entry)
      entry
    end

    # Subscribe to message events.
    # @yield [Hash] Called with each new message entry
    def subscribe(&block)
      @subscribers << block
    end

    # Unsubscribe from message events.
    # @param block [Proc] The subscriber to remove
    def unsubscribe(block)
      @subscribers.delete(block)
    end

    # Get recent log entries.
    # @param count [Integer] Number of entries to return
    # @return [Array<Hash>]
    def recent(count = 20)
      @log.last(count)
    end

    # Clear the log.
    def clear
      @log.clear
    end

    # Format log entries for display.
    # @param count [Integer] Number of entries to format
    # @return [String]
    def format_log(count = 20)
      recent(count).map do |entry|
        time = entry[:timestamp].strftime("%H:%M:%S")
        from = entry[:from]
        to = entry[:to]
        msg = entry[:message]

        "#{time}  #{from} → #{to}: #{msg}"
      end.join("\n")
    end

    private

    def notify_subscribers(entry)
      @subscribers.each { |s| s.call(entry) }
    end

    def truncate_message(message, max_length = 100)
      str = case message
            when Hash
              message.to_json
            when String
              message
            else
              message.to_s
            end

      # Remove newlines for cleaner log display
      str = str.gsub(/\s+/, " ").strip

      if str.length > max_length
        str[0, max_length] + "..."
      else
        str
      end
    end
  end
end
