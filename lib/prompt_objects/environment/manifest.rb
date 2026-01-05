# frozen_string_literal: true

require "yaml"
require "time"

module PromptObjects
  module Env
    # Handles environment manifest files (manifest.yml).
    # Contains metadata about the environment: name, description, timestamps,
    # UI customization, and stats.
    class Manifest
      FILENAME = "manifest.yml"
      FORMAT_VERSION = 1  # Increment when manifest schema changes

      attr_accessor :name, :description, :created_at, :updated_at, :last_opened,
                    :icon, :color, :tags, :default_po, :stats, :version,
                    :archived_at, :imported_from, :imported_at

      def initialize(
        name:,
        description: nil,
        created_at: nil,
        updated_at: nil,
        last_opened: nil,
        icon: nil,
        color: nil,
        tags: nil,
        default_po: nil,
        stats: nil,
        version: nil,
        archived_at: nil,
        imported_from: nil,
        imported_at: nil
      )
        @name = name
        @description = description
        @created_at = created_at || Time.now
        @updated_at = updated_at || Time.now
        @last_opened = last_opened
        @icon = icon || "📦"
        @color = color || "#4A90D9"
        @tags = tags || []
        @default_po = default_po
        @stats = stats || { "total_messages" => 0, "total_sessions" => 0, "po_count" => 0 }
        @version = version || FORMAT_VERSION
        @archived_at = archived_at
        @imported_from = imported_from
        @imported_at = imported_at
      end

      # Load manifest from a file path.
      # @param path [String] Path to manifest.yml
      # @return [Manifest]
      def self.load(path)
        raise Error, "Manifest not found: #{path}" unless File.exist?(path)

        data = YAML.safe_load(File.read(path), permitted_classes: [Time, Symbol])
        from_hash(data)
      end

      # Load manifest from an environment directory.
      # @param env_dir [String] Path to environment directory
      # @return [Manifest]
      def self.load_from_dir(env_dir)
        load(File.join(env_dir, FILENAME))
      end

      # Create manifest from a hash (parsed YAML).
      # @param data [Hash]
      # @return [Manifest]
      def self.from_hash(data)
        new(
          name: data["name"],
          description: data["description"],
          created_at: parse_time(data["created_at"]),
          updated_at: parse_time(data["updated_at"]),
          last_opened: parse_time(data["last_opened"]),
          icon: data["icon"],
          color: data["color"],
          tags: data["tags"],
          default_po: data["default_po"],
          stats: data["stats"],
          version: data["version"],
          archived_at: parse_time(data["archived_at"]),
          imported_from: data["imported_from"],
          imported_at: parse_time(data["imported_at"])
        )
      end

      # Parse time from various formats.
      # @param value [String, Time, nil]
      # @return [Time, nil]
      def self.parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)

        Time.parse(value)
      rescue ArgumentError
        nil
      end

      # Convert to hash for YAML serialization.
      # @return [Hash]
      def to_hash
        {
          "version" => @version,
          "name" => @name,
          "description" => @description,
          "created_at" => @created_at&.iso8601,
          "updated_at" => @updated_at&.iso8601,
          "last_opened" => @last_opened&.iso8601,
          "archived_at" => @archived_at&.iso8601,
          "imported_from" => @imported_from,
          "imported_at" => @imported_at&.iso8601,
          "icon" => @icon,
          "color" => @color,
          "tags" => @tags.any? ? @tags : nil,
          "default_po" => @default_po,
          "stats" => @stats
        }.compact
      end

      # Save manifest to a file.
      # @param path [String] Path to save manifest.yml
      def save(path)
        @updated_at = Time.now
        File.write(path, to_hash.to_yaml)
      end

      # Save manifest to an environment directory.
      # @param env_dir [String] Path to environment directory
      def save_to_dir(env_dir)
        save(File.join(env_dir, FILENAME))
      end

      # Mark environment as opened and update timestamp.
      def touch_opened!
        @last_opened = Time.now
        @updated_at = Time.now
      end

      # Update stats from environment data.
      # @param po_count [Integer] Number of prompt objects
      # @param session_count [Integer] Number of sessions
      # @param message_count [Integer] Total messages
      def update_stats(po_count: nil, session_count: nil, message_count: nil)
        @stats["po_count"] = po_count if po_count
        @stats["total_sessions"] = session_count if session_count
        @stats["total_messages"] = message_count if message_count
        @updated_at = Time.now
      end

      # Increment message count.
      def increment_messages!
        @stats["total_messages"] = (@stats["total_messages"] || 0) + 1
      end

      # Mark as archived with timestamp.
      def mark_archived!
        @archived_at = Time.now
        @updated_at = Time.now
      end

      # Check if this environment was imported.
      # @return [Boolean]
      def imported?
        !@imported_from.nil?
      end

      # Check if this environment was archived.
      # @return [Boolean]
      def archived?
        !@archived_at.nil?
      end

      # Display string.
      # @return [String]
      def to_s
        "#{@icon} #{@name}"
      end

      # Detailed info string.
      # @return [String]
      def info
        lines = []
        lines << "#{@icon} #{@name}"
        lines << "  #{@description}" if @description
        lines << ""
        lines << "  Created: #{@created_at&.strftime('%Y-%m-%d %H:%M')}"
        lines << "  Last opened: #{@last_opened&.strftime('%Y-%m-%d %H:%M')}" if @last_opened
        lines << "  Updated: #{@updated_at&.strftime('%Y-%m-%d %H:%M')}" if @updated_at

        if imported?
          lines << ""
          lines << "  Imported from: #{@imported_from}"
          lines << "  Imported at: #{@imported_at&.strftime('%Y-%m-%d %H:%M')}"
        end

        if archived?
          lines << ""
          lines << "  Archived at: #{@archived_at&.strftime('%Y-%m-%d %H:%M')}"
        end

        lines << ""
        lines << "  Stats:"
        lines << "    Objects: #{@stats['po_count'] || 0}"
        lines << "    Sessions: #{@stats['total_sessions'] || 0}"
        lines << "    Messages: #{@stats['total_messages'] || 0}"

        lines << ""
        lines << "  Tags: #{@tags.join(', ')}" if @tags&.any?
        lines << "  Format version: #{@version}"

        lines.join("\n")
      end
    end
  end
end
