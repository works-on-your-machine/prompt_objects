# frozen_string_literal: true

# Glamour shim for charm-native
#
# This file adds Ruby-only helper classes on top of charm-native's Glamour module.
# Based on marcoroth/glamour-ruby v0.2.1

require "json"

# charm-native should already be loaded (provides Glamour module)
# Just add the Ruby helpers

require_relative "glamour/style_definition"
require_relative "glamour/style"

module Glamour
  VERSION = "0.2.1"

  class << self
    alias render_native render

    def render(markdown, style: "auto", width: 0, **options)
      if style_class?(style)
        render_with_style_class(markdown, style, width: width, **options)
      else
        render_native(markdown, style: style, width: width, **options)
      end
    end

    def render_with_style(markdown, style, width: 0)
      json_style = style_to_json(style)
      render_with_json(markdown, json_style, width: width)
    end

    private

    def style_class?(style)
      style.is_a?(Class) && style.respond_to?(:glamour_style?) && style.glamour_style?
    end

    def style_to_json(style)
      case style
      when Class
        raise ArgumentError, "Expected Glamour::Style subclass, got #{style}" unless style_class?(style)

        style.to_json
      when Hash
        JSON.generate(style)
      when String
        style
      else
        raise ArgumentError, "Expected Style class, Hash, or JSON string, got #{style.class}"
      end
    end

    def render_with_style_class(markdown, style_class, width: 0, **_options)
      styles = style_class.to_h

      if styles.empty?
        render_native(markdown, style: "auto", width: width)
      else
        render_with_json(markdown, JSON.generate(styles), width: width)
      end
    end
  end
end
