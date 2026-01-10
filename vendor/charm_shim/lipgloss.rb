# frozen_string_literal: true

# Lipgloss shim for charm-native
#
# This file adds Ruby-only helper classes on top of charm-native's Lipgloss module.
# Based on marcoroth/lipgloss-ruby v0.2.0

# charm-native should already be loaded (provides Lipgloss module)
# Just add the Ruby helpers

require_relative "lipgloss/position"
require_relative "lipgloss/border"
require_relative "lipgloss/color"

module Lipgloss
  VERSION = "0.2.0"

  TOP = Position::TOP
  BOTTOM = Position::BOTTOM
  LEFT = Position::LEFT
  RIGHT = Position::RIGHT
  CENTER = Position::CENTER

  NORMAL_BORDER = Border::NORMAL
  ROUNDED_BORDER = Border::ROUNDED
  THICK_BORDER = Border::THICK
  DOUBLE_BORDER = Border::DOUBLE
  HIDDEN_BORDER = Border::HIDDEN
  BLOCK_BORDER = Border::BLOCK
  ASCII_BORDER = Border::ASCII

  NO_TAB_CONVERSION = -1

  class << self
    def join_horizontal(position, *strings)
      _join_horizontal(Position.resolve(position), strings)
    end

    def join_vertical(position, *strings)
      _join_vertical(Position.resolve(position), strings)
    end

    def place(width, height, horizontal, vertical, string, **opts)
      _place(width, height, Position.resolve(horizontal), Position.resolve(vertical), string, **opts)
    end

    def place_horizontal(width, position, string)
      _place_horizontal(width, Position.resolve(position), string)
    end

    def place_vertical(height, position, string)
      _place_vertical(height, Position.resolve(position), string)
    end
  end
end
