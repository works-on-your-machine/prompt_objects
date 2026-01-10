# frozen_string_literal: true

# Color classes for Lipgloss
# Based on marcoroth/lipgloss-ruby v0.2.0

module Lipgloss
  module ANSIColor
    COLORS = {
      black: "0",
      red: "1",
      green: "2",
      yellow: "3",
      blue: "4",
      magenta: "5",
      cyan: "6",
      white: "7",
      bright_black: "8",
      bright_red: "9",
      bright_green: "10",
      bright_yellow: "11",
      bright_blue: "12",
      bright_magenta: "13",
      bright_cyan: "14",
      bright_white: "15"
    }.freeze

    def self.resolve(value)
      case value
      when Symbol then COLORS.fetch(value) { raise ArgumentError, "Unknown ANSI color: #{value.inspect}" }
      when String then value
      when Integer then value.to_s
      else raise ArgumentError, "ANSI color must be a Symbol, String, or Integer, got #{value.class}"
      end
    end
  end

  # Adaptive color that changes based on terminal background
  class AdaptiveColor
    attr_reader :light, :dark

    def initialize(light:, dark:)
      @light = light
      @dark = dark
    end

    def to_h
      { light: @light, dark: @dark }
    end
  end

  # Complete color with explicit values for each color profile
  class CompleteColor
    attr_reader :true_color, :ansi256, :ansi

    def initialize(true_color:, ansi256:, ansi:)
      @true_color = true_color
      @ansi256 = ANSIColor.resolve(ansi256)
      @ansi = ANSIColor.resolve(ansi)
    end

    def to_h
      { true_color: @true_color, ansi256: @ansi256, ansi: @ansi }
    end
  end

  # Complete adaptive color with explicit values for each color profile
  # and separate options for light and dark backgrounds
  class CompleteAdaptiveColor
    attr_reader :light, :dark

    def initialize(light:, dark:)
      @light = light
      @dark = dark
    end

    def to_h
      { light: @light.to_h, dark: @dark.to_h }
    end
  end
end
