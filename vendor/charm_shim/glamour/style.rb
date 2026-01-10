# frozen_string_literal: true

# Style base class for Glamour custom styles
# Based on marcoroth/glamour-ruby v0.2.1

require "json"
require_relative "style_definition"

module Glamour
  class Style
    class << self
      def style(element, &)
        styles[element.to_sym] = StyleDefinition.new(&).to_h
      end

      def styles
        @styles ||= {}
      end

      def to_h
        styles.transform_keys(&:to_s)
      end

      def to_json(*_args)
        JSON.generate(to_h)
      end

      def render(markdown, width: 0, **options)
        Glamour.render(markdown, style: self, width: width, **options)
      end

      def glamour_style?
        true
      end
    end
  end
end
