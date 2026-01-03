# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Modal for editing a PromptObject's capabilities
      class CapabilityEditor
        attr_reader :po, :width, :height

        TAB_STDLIB = :stdlib
        TAB_DELEGATES = :delegates
        TAB_GENERATE = :generate

        def initialize(po:, registry:)
          @po = po
          @registry = registry
          @width = 70
          @height = 20
          @current_tab = TAB_STDLIB
          @cursor = 0
          @input_text = ""
          @input_mode = false
          @changes_made = false

          # Build list of available capabilities
          @stdlib_caps = build_stdlib_list
          @delegate_caps = build_delegate_list
        end

        def set_dimensions(width, height)
          @width = [width - 10, 50].max
          @height = [height - 6, 12].max
        end

        def next_tab
          tabs = [TAB_STDLIB, TAB_DELEGATES, TAB_GENERATE]
          idx = tabs.index(@current_tab) || 0
          @current_tab = tabs[(idx + 1) % tabs.length]
          @cursor = 0
          @input_mode = false
        end

        def prev_tab
          tabs = [TAB_STDLIB, TAB_DELEGATES, TAB_GENERATE]
          idx = tabs.index(@current_tab) || 0
          @current_tab = tabs[(idx - 1) % tabs.length]
          @cursor = 0
          @input_mode = false
        end

        def move_up
          max = current_list_size
          @cursor = (@cursor - 1) % max if max > 0
        end

        def move_down
          max = current_list_size
          @cursor = (@cursor + 1) % max if max > 0
        end

        def toggle_selected
          case @current_tab
          when TAB_STDLIB
            if @cursor < @stdlib_caps.length
              @stdlib_caps[@cursor][:enabled] = !@stdlib_caps[@cursor][:enabled]
              @changes_made = true
            end
          when TAB_DELEGATES
            if @cursor < @delegate_caps.length
              @delegate_caps[@cursor][:enabled] = !@delegate_caps[@cursor][:enabled]
              @changes_made = true
            end
          when TAB_GENERATE
            @input_mode = !@input_mode
          end
        end

        def enter_input_mode
          @input_mode = true
        end

        def exit_input_mode
          @input_mode = false
        end

        def input_mode?
          @input_mode && @current_tab == TAB_GENERATE
        end

        def insert_char(char)
          return unless input_mode?
          @input_text += char
        end

        def delete_char
          return unless input_mode?
          @input_text = @input_text[0..-2] unless @input_text.empty?
        end

        def clear_input
          @input_text = ""
        end

        def changes_made?
          @changes_made
        end

        def save_changes
          return unless @changes_made

          # Update PO config with selected capabilities
          enabled_stdlib = @stdlib_caps.select { |c| c[:enabled] }.map { |c| c[:name] }
          enabled_delegates = @delegate_caps.select { |c| c[:enabled] }.map { |c| c[:name] }

          @po.config["capabilities"] = enabled_stdlib + enabled_delegates
          @changes_made = false
        end

        def view
          lines = []

          # Title bar
          title = " EDIT: #{@po.name} Capabilities "
          changed_marker = @changes_made ? "*" : ""
          title_line = "┌#{title}#{changed_marker}#{'─' * (@width - title.length - changed_marker.length - 2)}┐"
          lines << Styles.modal_title.render(title_line)

          # Tab bar
          lines << render_tab_bar

          # Content area
          content_height = @height - 5
          content_lines = render_content(content_height)
          content_lines.each do |line|
            lines << "│ #{pad_line(line, @width - 4)} │"
          end

          # Bottom bar
          lines << "├#{'─' * (@width - 2)}┤"
          help = help_text
          bottom_line = "│#{pad_line(help, @width - 2)}│"
          lines << Styles.status_bar.render(bottom_line)
          lines << "└#{'─' * (@width - 2)}┘"

          lines.join("\n")
        end

        private

        def build_stdlib_list
          # Get all primitives from registry
          primitives = @registry.primitives
          current_caps = @po.config["capabilities"] || []

          primitives.map do |prim|
            {
              name: prim.name,
              description: prim.description,
              enabled: current_caps.include?(prim.name)
            }
          end
        end

        def build_delegate_list
          # Get all other POs that could be delegates
          pos = @registry.prompt_objects.reject { |p| p.name == @po.name }
          current_caps = @po.config["capabilities"] || []

          pos.map do |delegate_po|
            {
              name: delegate_po.name,
              description: delegate_po.description,
              enabled: current_caps.include?(delegate_po.name)
            }
          end
        end

        def current_list_size
          case @current_tab
          when TAB_STDLIB then @stdlib_caps.length
          when TAB_DELEGATES then @delegate_caps.length
          when TAB_GENERATE then 1
          else 0
          end
        end

        def render_tab_bar
          tabs = [
            { key: TAB_STDLIB, label: "Stdlib" },
            { key: TAB_DELEGATES, label: "Delegates" },
            { key: TAB_GENERATE, label: "Generate" }
          ]

          tab_parts = tabs.map do |tab|
            if tab[:key] == @current_tab
              Styles.help_key.render(" [#{tab[:label]}] ")
            else
              Styles.message_to.render("  #{tab[:label]}  ")
            end
          end

          "│#{tab_parts.join}#{'─' * (@width - 40)}│"
        end

        def render_content(height)
          case @current_tab
          when TAB_STDLIB
            render_checkbox_list(@stdlib_caps, height, "primitives")
          when TAB_DELEGATES
            render_checkbox_list(@delegate_caps, height, "prompt objects")
          when TAB_GENERATE
            render_generate_form(height)
          else
            ["Unknown tab"]
          end
        end

        def render_checkbox_list(items, height, type_name)
          lines = []
          lines << ""

          if items.empty?
            lines << Styles.message_to.render("  No #{type_name} available")
          else
            items.each_with_index do |item, i|
              checkbox = item[:enabled] ? "[x]" : "[ ]"
              checkbox_styled = item[:enabled] ? Styles.success.render(checkbox) : checkbox

              cursor_indicator = i == @cursor ? ">" : " "
              cursor_styled = i == @cursor ? Styles.help_key.render(cursor_indicator) : cursor_indicator

              name = item[:name]
              desc = item[:description].to_s[0, @width - 30]

              line = "#{cursor_styled} #{checkbox_styled} #{name}"
              line += " - #{Styles.message_to.render(desc)}" if desc.length > 0

              lines << line
            end
          end

          pad_to_height(lines, height)
        end

        def render_generate_form(height)
          lines = []
          lines << ""
          lines << Styles.section_header.render("Generate New Primitive")
          lines << ""
          lines << "Describe the capability you want to create:"
          lines << ""

          if @input_mode
            cursor = "_"
            lines << "  > #{@input_text}#{cursor}"
          else
            if @input_text.empty?
              lines << Styles.message_to.render("  (Press Enter to start typing...)")
            else
              lines << "  > #{@input_text}"
            end
          end

          lines << ""
          lines << Styles.thinking.render("  Example: \"HTTP POST request with JSON body\"")
          lines << Styles.thinking.render("  Example: \"Send email via SMTP\"")
          lines << ""

          if @input_text.length > 0 && !@input_mode
            lines << Styles.success.render("  Press 's' to save or Enter to edit")
          end

          pad_to_height(lines, height)
        end

        def help_text
          case @current_tab
          when TAB_GENERATE
            if @input_mode
              " [Esc] Cancel  [Enter] Done "
            else
              " [Tab] Switch  [Enter] Type  [s] Save  [Esc] Close "
            end
          else
            " [Tab] Switch  [j/k] Move  [Space] Toggle  [s] Save  [Esc] Close "
          end
        end

        def pad_line(text, width)
          plain_len = text.gsub(/\e\[[0-9;]*m/, '').length
          padding = [width - plain_len, 0].max
          "#{text}#{' ' * padding}"
        end

        def pad_to_height(lines, height)
          while lines.length < height
            lines << ""
          end
          lines.take(height)
        end
      end
    end
  end
end
