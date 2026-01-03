# frozen_string_literal: true

module PromptObjects
  module UI
    module Models
      # Horizontal bar showing all registered capabilities
      # POs are selectable, primitives are shown dimmed
      class CapabilityBar
        attr_accessor :width

        STATE_ICONS = {
          idle: "",
          working: "",
          active: "",
          waiting_for_human: ""
        }.freeze

        def initialize(registry:)
          @registry = registry
          @selected_index = 0
          @width = 80
        end

        def select(name)
          pos = prompt_objects
          index = pos.find_index { |po| po.name == name }
          @selected_index = index if index
        end

        def selected_name
          pos = prompt_objects
          return nil if pos.empty?

          pos[@selected_index]&.name
        end

        def next
          pos = prompt_objects
          return if pos.empty?

          @selected_index = (@selected_index + 1) % pos.length
        end

        def prev
          pos = prompt_objects
          return if pos.empty?

          @selected_index = (@selected_index - 1) % pos.length
        end

        def view(width = @width)
          pos = prompt_objects
          return "  No prompt objects loaded" if pos.empty?

          boxes = pos.each_with_index.map do |po, i|
            render_capability_box(po, i == @selected_index)
          end

          # Also show primitives count
          prim_count = @registry.primitives.length
          prim_label = Styles.message_to.render(" [#{prim_count} primitives]")

          boxes.join(" ") + prim_label
        end

        private

        def prompt_objects
          @registry.prompt_objects
        end

        def render_capability_box(po, selected)
          state = po.state || :idle
          icon = STATE_ICONS[state] || STATE_ICONS[:idle]

          name = po.name
          name = name[0, 12] + ".." if name.length > 14

          content = "#{name} #{icon}"

          style = Styles.capability_box(active: selected, state: state)
          style.render(content)
        end
      end
    end
  end
end
