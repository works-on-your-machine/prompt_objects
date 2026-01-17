# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability for POs to modify their own or other POs' markdown body (prompt).
    # This enables self-modification of behavior, learning, and identity.
    # Note: This does NOT modify the frontmatter (capabilities, etc.) - use add_capability for that.
    class ModifyPrompt < Primitive
      def name
        "modify_prompt"
      end

      def description
        "Modify a prompt object's markdown body (its identity/behavior prompt). Can append, prepend, replace sections, or do a full rewrite. Does NOT change capabilities - use add_capability for that."
      end

      def parameters
        {
          type: "object",
          properties: {
            target: {
              type: "string",
              description: "Name of the prompt object to modify. Use 'self' for the current PO."
            },
            operation: {
              type: "string",
              enum: ["append", "prepend", "replace_section", "rewrite"],
              description: "Type of modification: 'append' adds to end, 'prepend' adds to beginning, 'replace_section' replaces a specific section, 'rewrite' replaces the entire prompt"
            },
            content: {
              type: "string",
              description: "The new content to add or replace with"
            },
            section: {
              type: "string",
              description: "(For replace_section only) The section heading to replace (e.g., '## Learnings', '## Behavior'). The section and all content until the next heading of same or higher level will be replaced."
            }
          },
          required: ["target", "operation", "content"]
        }
      end

      def receive(message, context:)
        target = message[:target] || message["target"]
        operation = message[:operation] || message["operation"]
        content = message[:content] || message["content"]
        section = message[:section] || message["section"]

        # Resolve 'self' to the calling PO
        target = context.calling_po if target == "self"

        # Find the target PO
        target_po = context.env.registry.get(target)
        unless target_po
          return "Error: Prompt object '#{target}' not found"
        end

        unless target_po.is_a?(PromptObject)
          return "Error: '#{target}' is not a prompt object"
        end

        # Get current body
        current_body = target_po.body || ""

        # Apply the operation
        new_body = case operation
        when "append"
          append_content(current_body, content)
        when "prepend"
          prepend_content(current_body, content)
        when "replace_section"
          unless section
            return "Error: 'section' parameter required for replace_section operation"
          end
          replace_section(current_body, section, content)
        when "rewrite"
          content
        else
          return "Error: Unknown operation '#{operation}'. Use: append, prepend, replace_section, or rewrite"
        end

        # Update the PO's body in memory
        target_po.instance_variable_set(:@body, new_body)

        # Persist to file
        saved = target_po.save

        # Notify for real-time UI update
        context.env.notify_po_modified(target_po)

        if saved
          describe_change(operation, target, section)
        else
          "Modified '#{target}' prompt (in-memory only, could not save to file)."
        end
      end

      private

      def append_content(body, content)
        body.empty? ? content : "#{body.rstrip}\n\n#{content}"
      end

      def prepend_content(body, content)
        body.empty? ? content : "#{content}\n\n#{body.lstrip}"
      end

      def replace_section(body, section_heading, new_content)
        # Normalize section heading (ensure it starts with #)
        heading = section_heading.strip
        heading = "## #{heading}" unless heading.start_with?("#")

        # Determine heading level
        heading_level = heading.match(/^(#+)/)[1].length

        # Find the section
        lines = body.lines
        section_start = nil
        section_end = nil

        lines.each_with_index do |line, i|
          if line.strip.downcase == heading.downcase || line.strip.downcase.start_with?("#{heading.downcase} ")
            section_start = i
          elsif section_start && !section_end
            # Check if this is a heading of same or higher level
            if line.match?(/^(#+)\s/)
              line_level = line.match(/^(#+)/)[1].length
              if line_level <= heading_level
                section_end = i
              end
            end
          end
        end

        unless section_start
          # Section not found - append as new section
          return append_content(body, "#{heading}\n\n#{new_content}")
        end

        # If section_end not found, section goes to end of document
        section_end ||= lines.length

        # Build new body
        before = lines[0...section_start].join
        after = lines[section_end..].join

        "#{before.rstrip}\n\n#{heading}\n\n#{new_content}\n\n#{after.lstrip}".strip
      end

      def describe_change(operation, target, section)
        case operation
        when "append"
          "Appended content to '#{target}' prompt and saved to file."
        when "prepend"
          "Prepended content to '#{target}' prompt and saved to file."
        when "replace_section"
          "Replaced section '#{section}' in '#{target}' prompt and saved to file."
        when "rewrite"
          "Rewrote '#{target}' prompt entirely and saved to file."
        end
      end
    end
  end
end
