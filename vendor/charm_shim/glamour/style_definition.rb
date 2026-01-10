# frozen_string_literal: true

# StyleDefinition for Glamour custom styles
# Based on marcoroth/glamour-ruby v0.2.1

module Glamour
  class StyleDefinition
    def initialize(&)
      @attributes = {}
      instance_eval(&) if block_given?
    end

    def to_h
      @attributes
    end

    private

    def method_missing(name, value = nil, &)
      @attributes[name] = if block_given?
                            StyleDefinition.new(&).to_h
                          else
                            value
                          end
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end
