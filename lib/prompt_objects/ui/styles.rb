# frozen_string_literal: true

# NOTE: Lipgloss has Go FFI issues that cause crashes when creating multiple styles.
# Forcing ANSI mode for now until the gem is more stable.
# To try Lipgloss again, set PROMPT_OBJECTS_USE_LIPGLOSS=1

module PromptObjects
  module UI
    # Styling for the TUI - ANSI 256-color mode
    module Styles
      # Lipgloss disabled due to Go FFI crashes
      USE_LIPGLOSS = false

      # ANSI fallback
      module ANSI
        RESET = "\e[0m"
        BOLD = "\e[1m"
        DIM = "\e[2m"
        ITALIC = "\e[3m"
        UNDERLINE = "\e[4m"
        REVERSE = "\e[7m"

        def self.fg(color)
          "\e[38;5;#{color}m"
        end

        # 256-color approximations
        PURPLE = 141
        GREEN = 42
        GRAY = 245
        DARK_GRAY = 240
        RED = 203
        AMBER = 214
        WHITE = 255
      end

      class ANSIStyle
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

      def self.ansi
        ANSIStyle.new
      end

      # Style accessors - use Lipgloss if available, else ANSI
      def self.panel_title
        if USE_LIPGLOSS
          @panel_title
        else
          ansi.bold.fg(ANSI::PURPLE)
        end
      end

      def self.message_from
        if USE_LIPGLOSS
          @message_from
        else
          ansi.bold.fg(ANSI::GREEN)
        end
      end

      def self.message_to
        if USE_LIPGLOSS
          @message_to
        else
          ansi.fg(ANSI::GRAY)
        end
      end

      def self.timestamp
        if USE_LIPGLOSS
          @timestamp
        else
          ansi.dim.fg(ANSI::DARK_GRAY)
        end
      end

      def self.user_message
        if USE_LIPGLOSS
          @user_message
        else
          ansi.bold.fg(ANSI::WHITE)
        end
      end

      def self.assistant_message
        if USE_LIPGLOSS
          @assistant_message
        else
          ansi.fg(ANSI::WHITE)
        end
      end

      def self.thinking
        if USE_LIPGLOSS
          @thinking
        else
          ansi.dim.italic.fg(ANSI::DARK_GRAY)
        end
      end

      def self.input_prompt
        if USE_LIPGLOSS
          @input_prompt
        else
          ansi.bold.fg(ANSI::PURPLE)
        end
      end

      def self.input_text
        if USE_LIPGLOSS
          @input_text
        else
          ansi.fg(ANSI::WHITE)
        end
      end

      def self.section_header
        if USE_LIPGLOSS
          @section_header
        else
          ansi.bold.underline.fg(ANSI::PURPLE)
        end
      end

      def self.error
        if USE_LIPGLOSS
          @error_style
        else
          ansi.bold.fg(ANSI::RED)
        end
      end

      def self.warning
        if USE_LIPGLOSS
          @warning_style
        else
          ansi.fg(ANSI::AMBER)
        end
      end

      def self.success
        if USE_LIPGLOSS
          @success_style
        else
          ansi.fg(ANSI::GREEN)
        end
      end

      def self.status_bar
        if USE_LIPGLOSS
          @status_bar
        else
          ansi.fg(ANSI::DARK_GRAY)
        end
      end

      def self.help_key
        if USE_LIPGLOSS
          @help_key
        else
          ansi.bold.fg(ANSI::GREEN)
        end
      end

      def self.modal_title
        if USE_LIPGLOSS
          @modal_title
        else
          ansi.bold.fg(ANSI::PURPLE)
        end
      end

      def self.capability_box(active: false, state: :idle)
        if USE_LIPGLOSS
          active ? @capability_active : @capability_idle
        else
          case state
          when :working
            ansi.bold.fg(ANSI::AMBER)
          when :waiting_for_human
            ansi.bold.fg(ANSI::RED)
          else
            active ? ansi.bold.fg(ANSI::WHITE) : ansi.fg(ANSI::GRAY)
          end
        end
      end
    end
  end
end
