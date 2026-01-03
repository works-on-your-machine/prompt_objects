# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Modal view for inspecting a PromptObject's details
      class POInspector
        attr_reader :po, :width, :height

        TAB_OVERVIEW = :overview
        TAB_PROMPT = :prompt
        TAB_CAPABILITIES = :capabilities
        TAB_HISTORY = :history

        def initialize(po:)
          @po = po
          @width = 70
          @height = 20
          @current_tab = TAB_OVERVIEW
          @scroll_offset = 0
        end

        def set_dimensions(width, height)
          @width = [width - 10, 50].max
          @height = [height - 6, 10].max
        end

        def next_tab
          tabs = [TAB_OVERVIEW, TAB_PROMPT, TAB_CAPABILITIES, TAB_HISTORY]
          idx = tabs.index(@current_tab) || 0
          @current_tab = tabs[(idx + 1) % tabs.length]
          @scroll_offset = 0
        end

        def prev_tab
          tabs = [TAB_OVERVIEW, TAB_PROMPT, TAB_CAPABILITIES, TAB_HISTORY]
          idx = tabs.index(@current_tab) || 0
          @current_tab = tabs[(idx - 1) % tabs.length]
          @scroll_offset = 0
        end

        def scroll_up
          @scroll_offset = [@scroll_offset + 1, 0].max
        end

        def scroll_down
          @scroll_offset = [@scroll_offset - 1, 0].max
        end

        def view
          lines = []

          # Title bar
          title = " INSPECT: #{@po.name} "
          title_line = "┌#{title}#{'─' * (@width - title.length - 2)}┐"
          lines << Styles.modal_title.render(title_line)

          # Tab bar
          lines << render_tab_bar

          # Content area
          content_height = @height - 4
          content_lines = render_content(content_height)
          content_lines.each do |line|
            lines << "│ #{pad_line(line, @width - 4)} │"
          end

          # Bottom bar
          lines << "├#{'─' * (@width - 2)}┤"
          help = " [Tab] Switch  [j/k] Scroll  [Esc] Close "
          bottom_line = "│#{pad_line(help, @width - 2)}│"
          lines << Styles.status_bar.render(bottom_line)
          lines << "└#{'─' * (@width - 2)}┘"

          lines.join("\n")
        end

        private

        def render_tab_bar
          tabs = [
            { key: TAB_OVERVIEW, label: "Overview" },
            { key: TAB_PROMPT, label: "Prompt" },
            { key: TAB_CAPABILITIES, label: "Capabilities" },
            { key: TAB_HISTORY, label: "History" }
          ]

          tab_parts = tabs.map do |tab|
            if tab[:key] == @current_tab
              Styles.help_key.render(" [#{tab[:label]}] ")
            else
              Styles.message_to.render("  #{tab[:label]}  ")
            end
          end

          "│#{tab_parts.join}#{'─' * 5}│"
        end

        def render_content(height)
          case @current_tab
          when TAB_OVERVIEW
            render_overview(height)
          when TAB_PROMPT
            render_prompt(height)
          when TAB_CAPABILITIES
            render_capabilities(height)
          when TAB_HISTORY
            render_history(height)
          else
            ["Unknown tab"]
          end
        end

        def render_overview(height)
          lines = []
          lines << ""
          lines << Styles.section_header.render("Name")
          lines << "  #{@po.name}"
          lines << ""
          lines << Styles.section_header.render("Description")
          desc = @po.description || "(no description)"
          wrap_text(desc, @width - 6).each do |line|
            lines << "  #{line}"
          end
          lines << ""
          lines << Styles.section_header.render("State")
          lines << "  #{@po.state || :idle}"
          lines << ""
          lines << Styles.section_header.render("History")
          lines << "  #{@po.history.length} messages"

          pad_to_height(lines, height)
        end

        def render_prompt(height)
          lines = []
          lines << ""
          lines << Styles.section_header.render("System Prompt (Markdown Body)")
          lines << ""

          body = @po.body || "(empty)"
          body.split("\n").each do |line|
            wrap_text(line, @width - 6).each do |wrapped|
              lines << "  #{wrapped}"
            end
          end

          # Apply scroll offset
          scrolled = apply_scroll(lines, height)
          pad_to_height(scrolled, height)
        end

        def render_capabilities(height)
          lines = []
          lines << ""

          universal = PromptObjects::UNIVERSAL_CAPABILITIES
          declared = @po.config["capabilities"] || []

          lines << Styles.section_header.render("Universal Capabilities")
          lines << "  (Available to all Prompt Objects)"
          universal.each do |cap|
            lines << "  #{Styles.success.render('•')} #{cap}"
          end

          lines << ""
          lines << Styles.section_header.render("Declared Capabilities")
          if declared.empty?
            lines << "  (none declared)"
          else
            declared.each do |cap|
              lines << "  #{Styles.help_key.render('•')} #{cap}"
            end
          end

          pad_to_height(lines, height)
        end

        def render_history(height)
          lines = []
          lines << ""

          if @po.history.empty?
            lines << Styles.message_to.render("  (no conversation history)")
          else
            @po.history.each_with_index do |msg, i|
              role = msg[:role].to_s.capitalize
              content = msg[:content].to_s[0, 50]
              content += "..." if msg[:content].to_s.length > 50

              case msg[:role]
              when :user
                lines << "  #{Styles.user_message.render(role)}: #{content}"
              when :assistant
                lines << "  #{Styles.assistant_message.render(role)}: #{content}"
              when :tool
                results = msg[:results] || []
                lines << "  #{Styles.thinking.render("Tool")}: #{results.length} result(s)"
              end
            end
          end

          scrolled = apply_scroll(lines, height)
          pad_to_height(scrolled, height)
        end

        def wrap_text(text, width)
          return [""] if text.nil? || text.empty?

          words = text.split(/\s+/)
          lines = []
          current = ""

          words.each do |word|
            if current.empty?
              current = word
            elsif current.length + word.length + 1 <= width
              current += " #{word}"
            else
              lines << current
              current = word
            end
          end

          lines << current unless current.empty?
          lines.empty? ? [""] : lines
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

        def apply_scroll(lines, height)
          start = [@scroll_offset, [lines.length - height, 0].max].min
          lines.drop(start)
        end
      end
    end
  end
end
