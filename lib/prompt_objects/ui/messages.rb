# frozen_string_literal: true

module PromptObjects
  module UI
    # Custom message types for the Bubble Tea event loop
    module Messages
      # Message bus entry received
      BusEntry = Struct.new(:entry, keyword_init: true)

      # LLM response received
      POResponse = Struct.new(:po_name, :text, keyword_init: true)

      # User selected a different PO
      SelectPO = Struct.new(:name, keyword_init: true)

      # User activated a PO (enter key)
      ActivatePO = Struct.new(:name, keyword_init: true)

      # Open a modal (inspector, editor, notifications)
      OpenModal = Struct.new(:modal, :data, keyword_init: true)

      # Close the current modal
      CloseModal = Struct.new(:result, keyword_init: true)

      # Toggle a panel (message log, help)
      TogglePanel = Struct.new(:panel, keyword_init: true)

      # User input submitted
      InputSubmit = Struct.new(:text, keyword_init: true)

      # LLM call started (show spinner)
      LLMStart = Struct.new(:po_name, keyword_init: true)

      # LLM call completed
      LLMComplete = Struct.new(:po_name, keyword_init: true)

      # Error occurred
      ErrorOccurred = Struct.new(:message, keyword_init: true)

      # Notification badge update
      NotificationUpdate = Struct.new(:po_name, :count, keyword_init: true)

      # Tick for animations (spinners)
      Tick = Struct.new(:time, keyword_init: true)

      # Session poll tick (for detecting MCP changes)
      SessionPollTick = Struct.new(:time, keyword_init: true)

      # Sessions changed (from another connector)
      SessionsChanged = Struct.new(:new_sessions, :updated_sessions, keyword_init: true)
    end
  end
end
