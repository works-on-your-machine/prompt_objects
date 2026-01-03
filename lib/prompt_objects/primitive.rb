# frozen_string_literal: true

module PromptObjects
  # Base class for primitive capabilities.
  # Primitives are deterministic Ruby implementations (no LLM interpretation).
  class Primitive < Capability
    # Primitives are always "idle" in terms of state since they execute synchronously
    def initialize
      super
      @state = :idle
    end
  end
end
