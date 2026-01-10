# frozen_string_literal: true

# Charm libraries loaded via app.rb -> charm.rb

module PromptObjects
  module UI
    module Models
      # Environment picker for selecting which environment to open.
      # Shown when multiple environments exist and none is specified.
      class EnvPicker
        include Bubbletea::Model

        attr_reader :selected_env

        def initialize(environments:)
          @environments = environments  # Array of Manifest objects
          @selected_index = 0
          @selected_env = nil
          @width = 80
          @height = 24
          @cancelled = false
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
          lines = []
          lines << ""
          lines << center(box_top(50))
          lines << center(box_line("Select Environment", 50, :center, :bold))
          lines << center(box_bottom(50))
          lines << ""

          @environments.each_with_index do |env, i|
            selected = i == @selected_index
            marker = selected ? style_selected("▸ ") : "  "
            icon = env.icon || "📦"
            name = env.name.ljust(15)

            # Show last opened or object count
            info = if env.last_opened
                     "opened #{format_time_ago(env.last_opened)}"
                   else
                     "#{env.stats['po_count'] || 0} objects"
                   end

            if selected
              lines << center("#{marker}#{icon} #{style_selected(name)} #{style_dim(info)}")
            else
              lines << center("#{marker}#{icon} #{name} #{style_dim(info)}")
            end
          end

          lines << ""
          lines << center("#{style_key('↑/↓')} #{style_dim('select')}  #{style_key('Enter')} #{style_dim('open')}  #{style_key('n')} #{style_dim('new')}  #{style_key('q')} #{style_dim('quit')}")

          lines.join("\n")
        end

        def done?
          !@selected_env.nil?
        end

        def cancelled?
          @cancelled
        end

        def wants_new_env?
          @wants_new_env
        end

        private

        def handle_key(msg)
          char = msg.char.to_s

          if msg.ctrl? && char == "c"
            @cancelled = true
            return [self, Bubbletea.quit]
          end

          case
          when msg.enter?
            @selected_env = @environments[@selected_index].name
            [self, Bubbletea.quit]
          when msg.esc? || char == "q"
            @cancelled = true
            [self, Bubbletea.quit]
          when char == "n"
            @wants_new_env = true
            [self, Bubbletea.quit]
          when msg.up? || char == "k"
            @selected_index = (@selected_index - 1) % @environments.length
            [self, nil]
          when msg.down? || char == "j"
            @selected_index = (@selected_index + 1) % @environments.length
            [self, nil]
          else
            [self, nil]
          end
        end

        def format_time_ago(time)
          return "never" unless time

          seconds = Time.now - time
          case
          when seconds < 60
            "just now"
          when seconds < 3600
            "#{(seconds / 60).to_i}m ago"
          when seconds < 86400
            "#{(seconds / 3600).to_i}h ago"
          when seconds < 604800
            "#{(seconds / 86400).to_i}d ago"
          else
            time.strftime("%Y-%m-%d")
          end
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
          else
            content = text.ljust(inner_width)
          end

          styled_content = style == :bold ? style_bold(content) : content
          "│ #{styled_content} │"
        end

        def center(text)
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
          "\e[1;38;5;42m#{text}\e[0m"
        end

        def style_selected(text)
          "\e[1;38;5;141m#{text}\e[0m"
        end
      end
    end
  end
end
