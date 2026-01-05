# frozen_string_literal: true

require "sqlite3"
require "json"
require "securerandom"

module PromptObjects
  module Session
    # SQLite-based session storage for conversation history.
    # Each environment has its own sessions.db file (gitignored for privacy).
    class Store
      SCHEMA_VERSION = 1

      # @param db_path [String] Path to the SQLite database file
      def initialize(db_path)
        @db_path = db_path
        @db = SQLite3::Database.new(db_path)
        @db.results_as_hash = true
        setup_schema
      end

      # Close the database connection.
      def close
        @db.close if @db
      end

      # --- Session CRUD ---

      # Create a new session for a PO.
      # @param po_name [String] Name of the prompt object
      # @param name [String, nil] Optional session name
      # @param metadata [Hash] Optional metadata
      # @return [String] Session ID
      def create_session(po_name:, name: nil, metadata: {})
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        @db.execute(<<~SQL, [id, po_name, name, now, now, metadata.to_json])
          INSERT INTO sessions (id, po_name, name, created_at, updated_at, metadata)
          VALUES (?, ?, ?, ?, ?, ?)
        SQL

        id
      end

      # Get a session by ID.
      # @param id [String] Session ID
      # @return [Hash, nil] Session data or nil if not found
      def get_session(id)
        row = @db.get_first_row("SELECT * FROM sessions WHERE id = ?", [id])
        return nil unless row

        parse_session_row(row)
      end

      # Get the most recent session for a PO, or create one if none exists.
      # @param po_name [String] Name of the prompt object
      # @return [Hash] Session data
      def get_or_create_session(po_name:)
        session = get_latest_session(po_name: po_name)
        return session if session

        id = create_session(po_name: po_name)
        get_session(id)
      end

      # Get the most recent session for a PO.
      # @param po_name [String] Name of the prompt object
      # @return [Hash, nil] Session data or nil
      def get_latest_session(po_name:)
        row = @db.get_first_row(<<~SQL, [po_name])
          SELECT * FROM sessions
          WHERE po_name = ?
          ORDER BY updated_at DESC
          LIMIT 1
        SQL

        return nil unless row

        parse_session_row(row)
      end

      # List all sessions for a PO.
      # @param po_name [String] Name of the prompt object
      # @return [Array<Hash>] Session data
      def list_sessions(po_name:)
        rows = @db.execute(<<~SQL, [po_name])
          SELECT * FROM sessions
          WHERE po_name = ?
          ORDER BY updated_at DESC
        SQL

        rows.map { |row| parse_session_row(row) }
      end

      # Update a session's metadata.
      # @param id [String] Session ID
      # @param name [String, nil] New session name
      # @param metadata [Hash, nil] New metadata (merged with existing)
      def update_session(id, name: nil, metadata: nil)
        updates = ["updated_at = ?"]
        params = [Time.now.utc.iso8601]

        if name
          updates << "name = ?"
          params << name
        end

        if metadata
          # Merge with existing metadata
          existing = get_session(id)
          if existing
            merged = (existing[:metadata] || {}).merge(metadata)
            updates << "metadata = ?"
            params << merged.to_json
          end
        end

        params << id
        @db.execute("UPDATE sessions SET #{updates.join(', ')} WHERE id = ?", params)
      end

      # Delete a session and all its messages.
      # @param id [String] Session ID
      def delete_session(id)
        @db.execute("DELETE FROM messages WHERE session_id = ?", [id])
        @db.execute("DELETE FROM sessions WHERE id = ?", [id])
      end

      # --- Message CRUD ---

      # Add a message to a session.
      # @param session_id [String] Session ID
      # @param role [Symbol, String] Message role (:user, :assistant, :tool)
      # @param content [String, nil] Message content
      # @param from_po [String, nil] Source PO for delegation tracking
      # @param tool_calls [Array, nil] Tool calls data
      # @param tool_results [Array, nil] Tool results data
      # @return [Integer] Message ID
      def add_message(session_id:, role:, content: nil, from_po: nil, tool_calls: nil, tool_results: nil)
        now = Time.now.utc.iso8601

        params = [
          session_id,
          role.to_s,
          content,
          from_po,
          tool_calls&.to_json,
          tool_results&.to_json,
          now
        ]

        @db.execute(<<~SQL, params)
          INSERT INTO messages (session_id, role, content, from_po, tool_calls, tool_results, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        SQL

        # Update session's updated_at
        @db.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", [now, session_id])

        @db.last_insert_row_id
      end

      # Get all messages for a session.
      # @param session_id [String] Session ID
      # @return [Array<Hash>] Messages in chronological order
      def get_messages(session_id)
        rows = @db.execute(<<~SQL, [session_id])
          SELECT * FROM messages
          WHERE session_id = ?
          ORDER BY id ASC
        SQL

        rows.map { |row| parse_message_row(row) }
      end

      # Get message count for a session.
      # @param session_id [String] Session ID
      # @return [Integer]
      def message_count(session_id)
        row = @db.get_first_row("SELECT COUNT(*) as count FROM messages WHERE session_id = ?", [session_id])
        row["count"]
      end

      # Clear all messages from a session (but keep the session).
      # @param session_id [String] Session ID
      def clear_messages(session_id)
        @db.execute("DELETE FROM messages WHERE session_id = ?", [session_id])
        @db.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", [Time.now.utc.iso8601, session_id])
      end

      # --- Stats ---

      # Get total message count across all sessions.
      # @return [Integer]
      def total_messages
        row = @db.get_first_row("SELECT COUNT(*) as count FROM messages")
        row["count"]
      end

      # Get total session count.
      # @return [Integer]
      def total_sessions
        row = @db.get_first_row("SELECT COUNT(*) as count FROM sessions")
        row["count"]
      end

      private

      def setup_schema
        # Check if we need to create/migrate
        version = get_schema_version

        if version == 0
          create_schema
          set_schema_version(SCHEMA_VERSION)
        elsif version < SCHEMA_VERSION
          migrate_schema(version)
          set_schema_version(SCHEMA_VERSION)
        end
      end

      def get_schema_version
        @db.get_first_value("PRAGMA user_version") || 0
      end

      def set_schema_version(version)
        @db.execute("PRAGMA user_version = #{version}")
      end

      def create_schema
        @db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            po_name TEXT NOT NULL,
            name TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            metadata TEXT DEFAULT '{}'
          );

          CREATE INDEX IF NOT EXISTS idx_sessions_po_name ON sessions(po_name);
          CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at);

          CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id),
            role TEXT NOT NULL,
            content TEXT,
            from_po TEXT,
            tool_calls TEXT,
            tool_results TEXT,
            created_at TEXT NOT NULL
          );

          CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);
        SQL
      end

      def migrate_schema(from_version)
        # Future migrations go here
        # if from_version < 2
        #   # Migration to version 2
        # end
      end

      def parse_session_row(row)
        {
          id: row["id"],
          po_name: row["po_name"],
          name: row["name"],
          created_at: row["created_at"] ? Time.parse(row["created_at"]) : nil,
          updated_at: row["updated_at"] ? Time.parse(row["updated_at"]) : nil,
          metadata: row["metadata"] ? JSON.parse(row["metadata"], symbolize_names: true) : {}
        }
      end

      def parse_message_row(row)
        {
          id: row["id"],
          session_id: row["session_id"],
          role: row["role"].to_sym,
          content: row["content"],
          from_po: row["from_po"],
          tool_calls: row["tool_calls"] ? JSON.parse(row["tool_calls"], symbolize_names: true) : nil,
          tool_results: row["tool_results"] ? JSON.parse(row["tool_results"], symbolize_names: true) : nil,
          created_at: row["created_at"] ? Time.parse(row["created_at"]) : nil
        }
      end
    end
  end
end
