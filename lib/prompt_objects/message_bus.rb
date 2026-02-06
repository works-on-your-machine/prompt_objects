# frozen_string_literal: true

module PromptObjects
  # Message bus for routing and logging all inter-capability communication.
  # This makes the semantic binding visible - you can see natural language
  # being transformed into capability calls.
  #
  # Each entry stores the full message content and a truncated summary.
  # Use :summary for compact log displays, :message for full inspection.
  class MessageBus
    attr_reader :log

    # @param session_store [Session::Store, nil] Optional store for persistent event logging
    def initialize(session_store: nil)
      @log = []
      @subscribers = []
      @store = session_store
    end

    # Log a message between capabilities.
    # @param from [String] Source capability name
    # @param to [String] Destination capability name
    # @param message [String, Hash] The message content (stored in full)
    # @param session_id [String, nil] Optional session ID for event persistence
    # @return [Hash] The log entry
    def publish(from:, to:, message:, session_id: nil)
      entry = {
        timestamp: Time.now,
        from: from,
        to: to,
        message: message,
        summary: summarize(message)
      }

      @log << entry
      persist_event(entry, session_id: session_id)
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

    # Format log entries for compact display.
    # @param count [Integer] Number of entries to format
    # @return [String]
    def format_log(count = 20)
      recent(count).map do |entry|
        time = entry[:timestamp].strftime("%H:%M:%S")
        from = entry[:from]
        to = entry[:to]
        msg = entry[:summary]

        "#{time}  #{from} → #{to}: #{msg}"
      end.join("\n")
    end

    private

    def notify_subscribers(entry)
      @subscribers.each { |s| s.call(entry) }
    end

    # Persist event to the session store (if available).
    def persist_event(entry, session_id: nil)
      return unless @store

      @store.add_event(entry, session_id: session_id)
    rescue StandardError => e
      # Don't let persistence failures break the bus
      warn "Warning: Failed to persist event: #{e.message}"
    end

    # Create a short summary for compact log displays.
    def summarize(message, max_length = 200)
      str = case message
            when Hash
              message.to_json
            when String
              message
            else
              message.to_s
            end

      # Collapse whitespace for single-line display
      str = str.gsub(/\s+/, " ").strip

      if str.length > max_length
        str[0, max_length] + "..."
      else
        str
      end
    end
  end
end
