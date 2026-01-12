# frozen_string_literal: true

require "listen"

module PromptObjects
  module Server
    # Watches the environment directory for file changes and notifies subscribers.
    # This enables live updates when POs are created/modified/deleted.
    class FileWatcher
      def initialize(runtime:, env_path:)
        @runtime = runtime
        @env_path = env_path
        @subscribers = []
        @listener = nil
      end

      def start
        objects_dir = File.join(@env_path, "objects")

        unless Dir.exist?(objects_dir)
          puts "FileWatcher: objects directory not found at #{objects_dir}"
          return
        end

        @listener = Listen.to(objects_dir, only: /\.md$/) do |modified, added, removed|
          handle_changes(modified: modified, added: added, removed: removed)
        end

        @listener.start
        puts "FileWatcher: watching #{objects_dir} for changes"
      end

      def stop
        @listener&.stop
      end

      def subscribe(&block)
        @subscribers << block
      end

      def unsubscribe(block)
        @subscribers.delete(block)
      end

      private

      def handle_changes(modified:, added:, removed:)
        # Handle added files
        added.each { |path| handle_po_added(path) }

        # Handle modified files
        modified.each { |path| handle_po_modified(path) }

        # Handle removed files
        removed.each { |path| handle_po_removed(path) }
      end

      def handle_po_added(path)
        name = File.basename(path, ".md")

        # Skip if already loaded (e.g., by create_capability)
        # The on_po_registered callback will have already broadcast
        if @runtime.registry.exists?(name)
          puts "FileWatcher: PO already loaded - #{name} (skipping)"
          return
        end

        puts "FileWatcher: PO added - #{name}"

        begin
          po = @runtime.load_prompt_object(path)
          @runtime.load_dependencies(po)
          notify(:po_added, po)
        rescue StandardError => e
          puts "FileWatcher: Failed to load #{name}: #{e.message}"
        end
      end

      def handle_po_modified(path)
        name = File.basename(path, ".md")
        puts "FileWatcher: PO modified - #{name}"

        begin
          # Remove the old version from registry
          @runtime.registry.unregister(name)

          # Load the new version
          po = @runtime.load_prompt_object(path)
          @runtime.load_dependencies(po)
          notify(:po_modified, po)
        rescue StandardError => e
          puts "FileWatcher: Failed to reload #{name}: #{e.message}"
        end
      end

      def handle_po_removed(path)
        name = File.basename(path, ".md")
        puts "FileWatcher: PO removed - #{name}"

        removed = @runtime.registry.unregister(name)
        notify(:po_removed, { name: name }) if removed
      end

      def notify(event, data)
        @subscribers.each do |subscriber|
          subscriber.call(event, data)
        rescue StandardError => e
          puts "FileWatcher subscriber error: #{e.message}"
        end
      end
    end
  end
end
