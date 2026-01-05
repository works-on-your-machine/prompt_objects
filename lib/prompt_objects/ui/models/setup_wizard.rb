# frozen_string_literal: true

require "bubbletea"

module PromptObjects
  module UI
    module Models
      # First-run setup wizard for creating the initial environment.
      # A standalone Bubble Tea model that runs before the main app.
      class SetupWizard
        include Bubbletea::Model

        STEP_WELCOME = :welcome
        STEP_NAME = :name
        STEP_TEMPLATE = :template
        STEP_CREATING = :creating
        STEP_DONE = :done

        attr_reader :env_name, :template, :env_path

        def initialize(manager:, templates:)
          @manager = manager
          @templates = templates
          @step = STEP_WELCOME
          @env_name = "default"
          @template = templates.first
          @template_index = 0
          @cursor_pos = @env_name.length
          @env_path = nil
          @width = 80
          @height = 24
          @error = nil
        end

        def init
          [self, nil]
        end

        def update(msg)
          case msg
          when Bubbletea::KeyMessage
            handle_key(msg)
          when Bubbletea::WindowSizeMessage
            @width = msg.width
            @height = msg.height
            [self, nil]
          else
            [self, nil]
          end
        end

        def view
          case @step
          when STEP_WELCOME
            render_welcome
          when STEP_NAME
            render_name_input
          when STEP_TEMPLATE
            render_template_picker
          when STEP_CREATING
            render_creating
          when STEP_DONE
            render_done
          end
        end

        def done?
          @step == STEP_DONE
        end

        private

        def handle_key(msg)
          char = msg.char.to_s

          # Ctrl+C always quits
          if msg.ctrl? && char == "c"
            return [self, Bubbletea.quit]
          end

          case @step
          when STEP_WELCOME
            handle_welcome_key(msg)
          when STEP_NAME
            handle_name_key(msg, char)
          when STEP_TEMPLATE
            handle_template_key(msg, char)
          when STEP_DONE
            handle_done_key(msg)
          else
            [self, nil]
          end
        end

        def handle_welcome_key(msg)
          if msg.enter? || msg.space?
            @step = STEP_NAME
          elsif msg.esc?
            return [self, Bubbletea.quit]
          end
          [self, nil]
        end

        def handle_name_key(msg, char)
          case
          when msg.enter?
            if @env_name.empty?
              @error = "Name cannot be empty"
            elsif !valid_name?(@env_name)
              @error = "Invalid name (use lowercase, numbers, hyphens, underscores)"
            elsif @manager.environment_exists?(@env_name)
              @error = "Environment '#{@env_name}' already exists"
            else
              @error = nil
              @step = STEP_TEMPLATE
            end
          when msg.esc?
            @step = STEP_WELCOME
          when msg.backspace?
            if @cursor_pos > 0
              @env_name = @env_name[0...(@cursor_pos - 1)] + @env_name[@cursor_pos..]
              @cursor_pos -= 1
            end
            @error = nil
          when msg.left?
            @cursor_pos = [@cursor_pos - 1, 0].max
          when msg.right?
            @cursor_pos = [@cursor_pos + 1, @env_name.length].min
          when msg.runes? && !char.empty? && char.match?(/[a-z0-9_-]/i)
            @env_name = @env_name[0...@cursor_pos] + char.downcase + @env_name[@cursor_pos..]
            @cursor_pos += 1
            @error = nil
          end
          [self, nil]
        end

        def handle_template_key(msg, char)
          case
          when msg.enter?
            @template = @templates[@template_index]
            @step = STEP_CREATING
            # Create the environment
            begin
              @env_path = @manager.create(name: @env_name, template: @template[:name])
              @manager.set_default_environment(@env_name)
              @step = STEP_DONE
            rescue StandardError => e
              @error = e.message
              @step = STEP_NAME
            end
          when msg.esc?
            @step = STEP_NAME
          when msg.up? || char == "k"
            @template_index = (@template_index - 1) % @templates.length
          when msg.down? || char == "j"
            @template_index = (@template_index + 1) % @templates.length
          end
          [self, nil]
        end

        def handle_done_key(msg)
          if msg.enter? || msg.space?
            return [self, Bubbletea.quit]
          end
          [self, nil]
        end

        def valid_name?(name)
          name.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)
        end

        # Rendering methods

        def render_welcome
          box_width = 50
          lines = []
          lines << ""
          lines << center(box_top(box_width))
          lines << center(box_line("", box_width))
          lines << center(box_line("Welcome to PromptObjects!", box_width, :center, :bold))
          lines << center(box_line("", box_width))
          lines << center(box_line("Let's set up your first environment.", box_width, :center))
          lines << center(box_line("", box_width))
          lines << center(box_bottom(box_width))
          lines << ""
          lines << ""
          lines << center("#{style_dim('Press')} #{style_key('Enter')} #{style_dim('to continue or')} #{style_key('Esc')} #{style_dim('to quit')}")
          lines.join("\n")
        end

        def render_name_input
          box_width = 50
          lines = []
          lines << ""
          lines << center(box_top(box_width))
          lines << center(box_line("Step 1: Name your environment", box_width, :center, :bold))
          lines << center(box_bottom(box_width))
          lines << ""
          lines << ""

          # Input field with cursor
          input_display = @env_name.dup
          if @cursor_pos < input_display.length
            input_display = input_display[0...@cursor_pos] + style_cursor(input_display[@cursor_pos]) + input_display[(@cursor_pos + 1)..]
          else
            input_display += style_cursor(" ")
          end

          lines << center("Environment name: #{style_input(input_display)}")
          lines << ""

          if @error
            lines << center(style_error(@error))
          else
            lines << center(style_dim("Use lowercase letters, numbers, hyphens, underscores"))
          end

          lines << ""
          lines << center("#{style_key('Enter')} #{style_dim('continue')}  #{style_key('Esc')} #{style_dim('back')}")
          lines.join("\n")
        end

        def render_template_picker
          box_width = 60
          lines = []
          lines << ""
          lines << center(box_top(box_width))
          lines << center(box_line("Step 2: Choose a template", box_width, :center, :bold))
          lines << center(box_bottom(box_width))
          lines << ""
          lines << ""

          @templates.each_with_index do |tmpl, i|
            selected = i == @template_index
            marker = selected ? style_selected("▸ ") : "  "
            icon = tmpl[:icon] || "📦"
            name = tmpl[:name].ljust(12)
            desc = tmpl[:description] || ""

            if selected
              lines << center("#{marker}#{icon} #{style_selected(name)} #{style_dim(desc)}")
            else
              lines << center("#{marker}#{icon} #{name} #{style_dim(desc)}")
            end
          end

          lines << ""
          lines << center("#{style_key('↑/↓')} #{style_dim('select')}  #{style_key('Enter')} #{style_dim('confirm')}  #{style_key('Esc')} #{style_dim('back')}")
          lines.join("\n")
        end

        def render_creating
          lines = []
          lines << ""
          lines << center("Creating environment '#{@env_name}'...")
          lines << center("Using template: #{@template[:name]}")
          lines.join("\n")
        end

        def render_done
          box_width = 55
          lines = []
          lines << ""
          lines << center(box_top(box_width))
          lines << center(box_line("", box_width))
          lines << center(box_line("Environment '#{@env_name}' is ready!", box_width, :center, :bold))
          lines << center(box_line("", box_width))
          lines << center(box_bottom(box_width))
          lines << ""
          lines << center(style_dim("Location: #{@env_path}"))
          lines << ""
          lines << ""
          lines << center("#{style_dim('Press')} #{style_key('Enter')} #{style_dim('to start')}")
          lines.join("\n")
        end

        # Box drawing helpers

        def box_top(width)
          "╭#{'─' * (width - 2)}╮"
        end

        def box_bottom(width)
          "╰#{'─' * (width - 2)}╯"
        end

        def box_line(text, width, align = :left, style = nil)
          inner_width = width - 4
          text = text[0...inner_width] if text.length > inner_width

          case align
          when :center
            padding = inner_width - text.length
            left_pad = padding / 2
            right_pad = padding - left_pad
            content = "#{' ' * left_pad}#{text}#{' ' * right_pad}"
          when :right
            content = text.rjust(inner_width)
          else
            content = text.ljust(inner_width)
          end

          styled_content = style == :bold ? style_bold(content) : content
          "│ #{styled_content} │"
        end

        def center(text)
          # Strip ANSI codes for length calculation
          visible_length = text.gsub(/\e\[[0-9;]*m/, '').length
          padding = [(@width - visible_length) / 2, 0].max
          "#{' ' * padding}#{text}"
        end

        # ANSI styling helpers

        def style_bold(text)
          "\e[1m#{text}\e[0m"
        end

        def style_dim(text)
          "\e[2m#{text}\e[0m"
        end

        def style_key(text)
          "\e[1;38;5;42m#{text}\e[0m"  # Bold green
        end

        def style_selected(text)
          "\e[1;38;5;141m#{text}\e[0m"  # Bold purple
        end

        def style_input(text)
          "\e[38;5;255m#{text}\e[0m"  # White
        end

        def style_cursor(char)
          "\e[7m#{char}\e[0m"  # Reverse video
        end

        def style_error(text)
          "\e[1;38;5;203m#{text}\e[0m"  # Bold red
        end
      end
    end
  end
end
