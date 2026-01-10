# frozen_string_literal: true

module PromptObjects
  module Connectors
    # Base class for connectors that provide different interfaces to environments.
    # Each connector (MCP, API, Web, etc.) inherits from this class.
    class Base
      attr_reader :runtime, :config

      # @param runtime [Runtime] The environment runtime
      # @param config [Hash] Connector-specific configuration
      def initialize(runtime:, config: {})
        @runtime = runtime
        @config = config
        @running = false
      end

      # Start the connector (may be blocking or non-blocking depending on implementation)
      def start
        raise NotImplementedError, "#{self.class} must implement #start"
      end

      # Stop the connector gracefully
      def stop
        @running = false
      end

      # Whether the connector is currently running
      def running?
        @running
      end

      # Connector identifier for session source tracking
      # @return [String] e.g., "mcp", "api", "web"
      def source_name
        raise NotImplementedError, "#{self.class} must implement #source_name"
      end

      protected

      # Helper to get or create a session for a PO with source tracking
      # @param po [PromptObject] The prompt object
      # @param session_name [String, nil] Optional session name
      # @return [String] Session ID
      def get_or_create_session(po, session_name: nil)
        return nil unless runtime.session_store

        # Check if PO already has a session
        session_id = po.instance_variable_get(:@session_id)
        return session_id if session_id

        # Create new session with source tracking
        session_id = runtime.session_store.create_session(
          po_name: po.name,
          name: session_name || "#{source_name.upcase} Session #{Time.now.strftime('%H:%M')}",
          source: source_name
        )

        # Attach to PO
        po.instance_variable_set(:@session_id, session_id)
        session_id
      end

      # Update last_message_source when a message is sent
      # @param session_id [String] Session ID
      def update_session_source(session_id)
        return unless runtime.session_store && session_id

        runtime.session_store.update_session(session_id, last_message_source: source_name)
      end
    end
  end
end
