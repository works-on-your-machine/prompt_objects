# frozen_string_literal: true

module PromptObjects
  module UI
    # ANSI-based styling for the TUI
    # Fallback from Lipgloss due to early release FFI issues
    module Styles
      # ANSI escape codes
      module ANSI
        RESET = "\e[0m"
        BOLD = "\e[1m"
        DIM = "\e[2m"
        ITALIC = "\e[3m"
        UNDERLINE = "\e[4m"

        # Foreground colors (256-color mode)
        def self.fg(color)
          "\e[38;5;#{color}m"
        end

        # Background colors (256-color mode)
        def self.bg(color)
          "\e[48;5;#{color}m"
        end

        # Color palette (256-color approximations)
        PURPLE = 135       # Primary
        GREEN = 42         # Secondary/Success
        GRAY = 245         # Muted
        RED = 196          # Error
        AMBER = 214        # Warning
        WHITE = 255        # Text
        DARK_GRAY = 240    # Text muted
      end

      # Simple style wrapper
      class Style
        def initialize
          @codes = []
        end

        def bold
          @codes << ANSI::BOLD
          self
        end

        def dim
          @codes << ANSI::DIM
          self
        end

        def italic
          @codes << ANSI::ITALIC
          self
        end

        def underline
          @codes << ANSI::UNDERLINE
          self
        end

        def fg(color)
          @codes << ANSI.fg(color)
          self
        end

        def render(text)
          return text if @codes.empty?

          "#{@codes.join}#{text}#{ANSI::RESET}"
        end
      end

      def self.style
        Style.new
      end

      # Capability bar
      def self.capability_box(active: false, state: :idle)
        s = style
        case state
        when :working then s.fg(ANSI::AMBER)
        when :active then s.fg(ANSI::GREEN)
        when :waiting_for_human then s.fg(ANSI::RED)
        else s.fg(ANSI::GRAY)
        end
        s.bold if active
        s
      end

      # Panel styles
      def self.panel_title
        style.bold.fg(ANSI::PURPLE)
      end

      # Message styles
      def self.message_from
        style.bold.fg(ANSI::GREEN)
      end

      def self.message_to
        style.fg(ANSI::DARK_GRAY)
      end

      def self.message_content
        style.fg(ANSI::WHITE)
      end

      def self.timestamp
        style.dim.fg(ANSI::DARK_GRAY)
      end

      # Conversation styles
      def self.user_message
        style.bold.fg(ANSI::WHITE)
      end

      def self.assistant_message
        style.fg(ANSI::WHITE)
      end

      def self.thinking
        style.dim.italic.fg(ANSI::DARK_GRAY)
      end

      # Input styles
      def self.input_prompt
        style.bold.fg(ANSI::PURPLE)
      end

      def self.input_text
        style.fg(ANSI::WHITE)
      end

      # Modal styles
      def self.modal_title
        style.bold.underline.fg(ANSI::PURPLE)
      end

      # Status bar
      def self.status_bar
        style.fg(ANSI::DARK_GRAY)
      end

      def self.help_key
        style.bold.fg(ANSI::GREEN)
      end

      # Section headers
      def self.section_header
        style.bold.underline.fg(ANSI::PURPLE)
      end

      # Error/warning styles
      def self.error
        style.bold.fg(ANSI::RED)
      end

      def self.warning
        style.fg(ANSI::AMBER)
      end

      def self.success
        style.fg(ANSI::GREEN)
      end
    end
  end
end
