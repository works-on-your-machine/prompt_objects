# frozen_string_literal: true

require "sqlite3"
require "json"
require "securerandom"

module PromptObjects
  module Session
    # SQLite-based session storage for conversation history.
    # Each environment has its own sessions.db file (gitignored for privacy).
    class Store
      SCHEMA_VERSION = 7

      # Thread types for conversation branching
      THREAD_TYPES = %w[root continuation delegation fork].freeze

      # Valid source values for session tracking
      SOURCES = %w[tui mcp api web cli].freeze

      # @param db_path [String] Path to the SQLite database file
      def initialize(db_path)
        @db_path = db_path
        @db = SQLite3::Database.new(db_path)
        @db.results_as_hash = true

        # Enable WAL mode for better concurrent access (TUI + MCP can access simultaneously)
        @db.execute("PRAGMA journal_mode=WAL")

        # Set busy timeout to 5 seconds - wait for locks instead of failing immediately
        @db.busy_timeout = 5000

        setup_schema
      end

      # Close the database connection.
      def close
        @db.close if @db
      end

      # --- Session/Thread CRUD ---

      # Create a new session (thread) for a PO.
      # @param po_name [String] Name of the prompt object
      # @param name [String, nil] Optional session name
      # @param source [String] Source interface (tui, mcp, api, web, cli)
      # @param source_client [String, nil] Client identifier (e.g., "claude-desktop", "cursor")
      # @param metadata [Hash] Optional metadata
      # @param parent_session_id [String, nil] Parent thread ID (for branching)
      # @param parent_message_id [Integer, nil] Message ID that spawned this thread
      # @param parent_po [String, nil] PO that created this thread (for cross-PO delegation)
      # @param thread_type [String] Type of thread: root, continuation, delegation, fork
      # @return [String] Session ID
      def create_session(po_name:, name: nil, source: "tui", source_client: nil, metadata: {},
                         parent_session_id: nil, parent_message_id: nil, parent_po: nil, thread_type: "root")
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        @db.execute(<<~SQL, [id, po_name, name, source, source_client, source, now, now, metadata.to_json, parent_session_id, parent_message_id, parent_po, thread_type])
          INSERT INTO sessions (id, po_name, name, source, source_client, last_message_source, created_at, updated_at, metadata, parent_session_id, parent_message_id, parent_po, thread_type)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL

        id
      end

      # Create a new thread (alias for create_session with thread semantics).
      # @param po_name [String] Name of the prompt object
      # @param parent_session_id [String, nil] Parent thread ID
      # @param parent_message_id [Integer, nil] Message ID that spawned this thread
      # @param parent_po [String, nil] PO that created this thread
      # @param thread_type [String] Type: root, continuation, delegation, fork
      # @param opts [Hash] Additional options passed to create_session
      # @return [String] Thread/Session ID
      def create_thread(po_name:, parent_session_id: nil, parent_message_id: nil, parent_po: nil, thread_type: "root", **opts)
        create_session(
          po_name: po_name,
          parent_session_id: parent_session_id,
          parent_message_id: parent_message_id,
          parent_po: parent_po,
          thread_type: thread_type,
          **opts
        )
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
      # @param source [String] Source interface for new session
      # @param source_client [String, nil] Client identifier for new session
      # @return [Hash] Session data
      def get_or_create_session(po_name:, source: "tui", source_client: nil)
        session = get_latest_session(po_name: po_name)
        return session if session

        id = create_session(po_name: po_name, source: source, source_client: source_client)
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
      # @return [Array<Hash>] Session data with message counts
      def list_sessions(po_name:)
        rows = @db.execute(<<~SQL, [po_name])
          SELECT s.*, COUNT(m.id) as message_count
          FROM sessions s
          LEFT JOIN messages m ON m.session_id = s.id
          WHERE s.po_name = ?
          GROUP BY s.id
          ORDER BY s.updated_at DESC
        SQL

        rows.map { |row| parse_session_row(row, include_count: true) }
      end

      # List all sessions across all POs.
      # @param source [String, nil] Filter by source interface
      # @param limit [Integer, nil] Maximum number of sessions
      # @return [Array<Hash>] Session data with message counts
      def list_all_sessions(source: nil, limit: nil)
        sql = <<~SQL
          SELECT s.*, COUNT(m.id) as message_count
          FROM sessions s
          LEFT JOIN messages m ON m.session_id = s.id
        SQL

        params = []
        if source
          sql += " WHERE s.source = ?"
          params << source
        end

        sql += " GROUP BY s.id ORDER BY s.updated_at DESC"

        if limit
          sql += " LIMIT ?"
          params << limit
        end

        rows = @db.execute(sql, params)
        rows.map { |row| parse_session_row(row, include_count: true) }
      end

      # --- Thread Navigation ---

      # Get all child threads of a session.
      # @param session_id [String] Parent session ID
      # @return [Array<Hash>] Child session data with message counts
      def get_child_threads(session_id)
        rows = @db.execute(<<~SQL, [session_id])
          SELECT s.*, COUNT(m.id) as message_count
          FROM sessions s
          LEFT JOIN messages m ON m.session_id = s.id
          WHERE s.parent_session_id = ?
          GROUP BY s.id
          ORDER BY s.created_at ASC
        SQL

        rows.map { |row| parse_session_row(row, include_count: true) }
      end

      # Get the lineage (path from root) for a thread.
      # @param session_id [String] Session ID
      # @return [Array<Hash>] Ancestors from root to current (inclusive)
      def get_thread_lineage(session_id)
        lineage = []
        current_id = session_id

        while current_id
          session = get_session(current_id)
          break unless session

          lineage.unshift(session)
          current_id = session[:parent_session_id]
        end

        lineage
      end

      # Get the full thread tree starting from a session.
      # @param session_id [String] Root session ID
      # @param max_depth [Integer] Maximum recursion depth
      # @return [Hash] Tree structure with session and children
      def get_thread_tree(session_id, max_depth: 10)
        return nil if max_depth <= 0

        session = get_session(session_id)
        return nil unless session

        # Add message count
        session[:message_count] = message_count(session_id)

        children = get_child_threads(session_id)
        child_trees = children.map { |child| get_thread_tree(child[:id], max_depth: max_depth - 1) }.compact

        {
          session: session,
          children: child_trees
        }
      end

      # Get root threads for a PO (threads with no parent).
      # @param po_name [String] Name of the prompt object
      # @return [Array<Hash>] Root session data with message counts
      def get_root_threads(po_name:)
        rows = @db.execute(<<~SQL, [po_name])
          SELECT s.*, COUNT(m.id) as message_count
          FROM sessions s
          LEFT JOIN messages m ON m.session_id = s.id
          WHERE s.po_name = ? AND s.parent_session_id IS NULL
          GROUP BY s.id
          ORDER BY s.updated_at DESC
        SQL

        rows.map { |row| parse_session_row(row, include_count: true) }
      end

      # Auto-generate a name for a thread from its first message.
      # @param session_id [String] Session ID
      # @param first_message [String] First message content
      # @param max_length [Integer] Maximum name length
      def auto_name_thread(session_id, first_message, max_length: 40)
        return unless first_message

        auto_name = first_message.to_s.gsub(/\s+/, " ").strip[0, max_length]
        auto_name += "..." if first_message.to_s.length > max_length
        update_session(session_id, name: auto_name)
      end

      # Search sessions by message content using full-text search.
      # @param query [String] Search query
      # @param po_name [String, nil] Filter by PO
      # @param source [String, nil] Filter by source
      # @param limit [Integer] Maximum results
      # @return [Array<Hash>] Sessions with match info
      def search_sessions(query, po_name: nil, source: nil, limit: 50)
        return [] if query.nil? || query.strip.empty?

        # Use FTS5 MATCH syntax
        # Escape special characters and add prefix matching
        safe_query = query.gsub(/['"()]/, " ").strip
        fts_query = safe_query.split.map { |term| "#{term}*" }.join(" ")

        # First get matching message IDs from FTS
        sql = <<~SQL
          SELECT DISTINCT s.*, COUNT(m.id) as message_count
          FROM sessions s
          INNER JOIN messages m ON m.session_id = s.id
          INNER JOIN messages_fts ON messages_fts.rowid = m.id
          WHERE messages_fts MATCH ?
        SQL

        params = [fts_query]

        if po_name
          sql += " AND s.po_name = ?"
          params << po_name
        end

        if source
          sql += " AND s.source = ?"
          params << source
        end

        sql += " GROUP BY s.id ORDER BY s.updated_at DESC LIMIT ?"
        params << limit

        rows = @db.execute(sql, params)
        results = rows.map { |row| parse_session_row(row, include_count: true) }

        # Get a snippet from matching messages for each session
        results.each do |session|
          snippet = get_match_snippet(session[:id], query)
          session[:match_snippet] = snippet if snippet
        end

        results
      rescue SQLite3::SQLException => e
        # FTS table might not exist in older databases
        if e.message.include?("no such table")
          search_sessions_fallback(query, po_name: po_name, source: source, limit: limit)
        else
          raise
        end
      end

      # Get a snippet of matching content from a session
      # @param session_id [String] Session ID
      # @param query [String] Search query
      # @return [String, nil] Snippet with match highlighted
      def get_match_snippet(session_id, query)
        # Get first message that matches
        row = @db.get_first_row(<<~SQL, [session_id, "%#{query}%"])
          SELECT content FROM messages
          WHERE session_id = ? AND content LIKE ?
          LIMIT 1
        SQL

        return nil unless row && row["content"]

        content = row["content"]
        # Find match position and extract snippet
        query_lower = query.downcase
        pos = content.downcase.index(query_lower)
        return content[0, 60] + "..." unless pos

        # Extract snippet around match
        start_pos = [pos - 20, 0].max
        end_pos = [pos + query.length + 40, content.length].min
        snippet = content[start_pos, end_pos - start_pos]

        # Add ellipsis if truncated
        snippet = "..." + snippet if start_pos > 0
        snippet = snippet + "..." if end_pos < content.length

        # Highlight match with markers
        snippet.gsub(/#{Regexp.escape(query)}/i) { |m| ">>>#{m}<<<" }
      end

      # Fallback search without FTS (slower but works on older databases)
      # @param query [String] Search query
      # @param po_name [String, nil] Filter by PO
      # @param source [String, nil] Filter by source
      # @param limit [Integer] Maximum results
      # @return [Array<Hash>] Sessions with match info
      def search_sessions_fallback(query, po_name: nil, source: nil, limit: 50)
        return [] if query.nil? || query.strip.empty?

        sql = <<~SQL
          SELECT DISTINCT s.*, COUNT(m.id) as message_count
          FROM sessions s
          INNER JOIN messages m ON m.session_id = s.id
          WHERE m.content LIKE ?
        SQL

        params = ["%#{query}%"]

        if po_name
          sql += " AND s.po_name = ?"
          params << po_name
        end

        if source
          sql += " AND s.source = ?"
          params << source
        end

        sql += " GROUP BY s.id ORDER BY s.updated_at DESC LIMIT ?"
        params << limit

        rows = @db.execute(sql, params)
        rows.map { |row| parse_session_row(row, include_count: true) }
      end

      # Update a session's metadata.
      # @param id [String] Session ID
      # @param name [String, nil] New session name
      # @param metadata [Hash, nil] New metadata (merged with existing)
      # @param last_message_source [String, nil] Source of last message (tui, mcp, api)
      def update_session(id, name: nil, metadata: nil, last_message_source: nil)
        updates = ["updated_at = ?"]
        params = [Time.now.utc.iso8601]

        if name
          updates << "name = ?"
          params << name
        end

        if last_message_source
          updates << "last_message_source = ?"
          params << last_message_source
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
      # @param source [String, nil] Source interface that added this message
      # @return [Integer] Message ID
      def add_message(session_id:, role:, content: nil, from_po: nil, tool_calls: nil, tool_results: nil, usage: nil, source: nil)
        now = Time.now.utc.iso8601

        params = [
          session_id,
          role.to_s,
          content,
          from_po,
          tool_calls&.to_json,
          tool_results&.to_json,
          usage&.to_json,
          now
        ]

        @db.execute(<<~SQL, params)
          INSERT INTO messages (session_id, role, content, from_po, tool_calls, tool_results, usage, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        SQL

        # Update session's updated_at and optionally last_message_source
        if source
          @db.execute("UPDATE sessions SET updated_at = ?, last_message_source = ? WHERE id = ?", [now, source, session_id])
        else
          @db.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", [now, session_id])
        end

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

      # --- Events (Message Bus Persistence) ---

      # Add an event from the message bus.
      # @param entry [Hash] Bus entry with :timestamp, :from, :to, :message, :summary
      # @param session_id [String, nil] Associated session ID
      # @return [Integer] Event ID
      def add_event(entry, session_id: nil)
        message_text = case entry[:message]
                       when Hash then entry[:message].to_json
                       when String then entry[:message]
                       else entry[:message].to_s
                       end

        params = [
          session_id || entry[:session_id],
          entry[:timestamp].iso8601,
          entry[:from],
          entry[:to],
          message_text,
          entry[:summary]
        ]

        @db.execute(<<~SQL, params)
          INSERT INTO events (session_id, timestamp, from_name, to_name, message, summary)
          VALUES (?, ?, ?, ?, ?, ?)
        SQL

        @db.last_insert_row_id
      end

      # Get events for a session.
      # @param session_id [String] Session ID
      # @return [Array<Hash>]
      def get_events(session_id:)
        rows = @db.execute(<<~SQL, [session_id])
          SELECT * FROM events WHERE session_id = ? ORDER BY id ASC
        SQL

        rows.map { |row| parse_event_row(row) }
      end

      # Get events since a timestamp.
      # @param timestamp [String] ISO8601 timestamp
      # @param limit [Integer] Maximum events to return
      # @return [Array<Hash>]
      def get_events_since(timestamp, limit: 500)
        rows = @db.execute(<<~SQL, [timestamp, limit])
          SELECT * FROM events WHERE timestamp > ? ORDER BY id ASC LIMIT ?
        SQL

        rows.map { |row| parse_event_row(row) }
      end

      # Get events between two timestamps.
      # @param start_time [String] ISO8601 start timestamp
      # @param end_time [String] ISO8601 end timestamp
      # @return [Array<Hash>]
      def get_events_between(start_time, end_time)
        rows = @db.execute(<<~SQL, [start_time, end_time])
          SELECT * FROM events WHERE timestamp BETWEEN ? AND ? ORDER BY id ASC
        SQL

        rows.map { |row| parse_event_row(row) }
      end

      # Get recent events.
      # @param count [Integer] Number of events
      # @return [Array<Hash>]
      def get_recent_events(count = 50)
        rows = @db.execute(<<~SQL, [count])
          SELECT * FROM events ORDER BY id DESC LIMIT ?
        SQL

        rows.map { |row| parse_event_row(row) }.reverse
      end

      # Search events by message content.
      # @param query [String] Search text
      # @param limit [Integer] Maximum results
      # @return [Array<Hash>]
      def search_events(query, limit: 100)
        rows = @db.execute(<<~SQL, ["%#{query}%", limit])
          SELECT * FROM events WHERE message LIKE ? ORDER BY id DESC LIMIT ?
        SQL

        rows.map { |row| parse_event_row(row) }
      end

      # Get total event count.
      # @return [Integer]
      def total_events
        row = @db.get_first_row("SELECT COUNT(*) as count FROM events")
        row["count"]
      end

      # --- Environment Data (Shared Key-Value Store) ---

      # Resolve the root thread ID for a session by walking up the delegation chain.
      # @param session_id [String] Any session ID in a delegation chain
      # @return [String] The root thread's session ID
      def resolve_root_thread(session_id)
        lineage = get_thread_lineage(session_id)
        return session_id if lineage.empty?

        lineage.first[:id]
      end

      # Store a key-value pair scoped to a root thread.
      # Uses INSERT OR REPLACE to create or overwrite.
      # @param root_thread_id [String] Root thread scope
      # @param key [String] Data key
      # @param short_description [String] Brief description for discoverability
      # @param value [Object] Data value (will be JSON-serialized)
      # @param stored_by [String] PO name that stored this
      def store_env_data(root_thread_id:, key:, short_description:, value:, stored_by:)
        now = Time.now.utc.iso8601
        json_value = JSON.generate(value)

        @db.execute(<<~SQL, [root_thread_id, key, short_description, json_value, stored_by, now, now])
          INSERT INTO env_data (root_thread_id, key, short_description, value, stored_by, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(root_thread_id, key) DO UPDATE SET
            short_description = excluded.short_description,
            value = excluded.value,
            stored_by = excluded.stored_by,
            updated_at = excluded.updated_at
        SQL
      end

      # Get a single env data entry by key.
      # @param root_thread_id [String] Root thread scope
      # @param key [String] Data key
      # @return [Hash, nil] Entry with parsed value, or nil if not found
      def get_env_data(root_thread_id:, key:)
        row = @db.get_first_row(<<~SQL, [root_thread_id, key])
          SELECT key, short_description, value, stored_by, created_at, updated_at
          FROM env_data
          WHERE root_thread_id = ? AND key = ?
        SQL

        return nil unless row

        {
          key: row["key"],
          short_description: row["short_description"],
          value: JSON.parse(row["value"], symbolize_names: true),
          stored_by: row["stored_by"],
          created_at: row["created_at"],
          updated_at: row["updated_at"]
        }
      end

      # List all env data keys and descriptions for a root thread (no values).
      # @param root_thread_id [String] Root thread scope
      # @return [Array<Hash>] Entries with key and short_description only
      def list_env_data(root_thread_id:)
        rows = @db.execute(<<~SQL, [root_thread_id])
          SELECT key, short_description FROM env_data
          WHERE root_thread_id = ?
          ORDER BY key ASC
        SQL

        rows.map { |row| { key: row["key"], short_description: row["short_description"] } }
      end

      # Update an existing env data entry.
      # @param root_thread_id [String] Root thread scope
      # @param key [String] Data key
      # @param short_description [String, nil] New description (keeps existing if nil)
      # @param value [Object, nil] New value (keeps existing if nil)
      # @param stored_by [String] PO name performing the update
      # @return [Boolean] True if updated, false if key not found
      def update_env_data(root_thread_id:, key:, short_description: nil, value: nil, stored_by:)
        existing = get_env_data(root_thread_id: root_thread_id, key: key)
        return false unless existing

        updates = ["updated_at = ?", "stored_by = ?"]
        params = [Time.now.utc.iso8601, stored_by]

        if short_description
          updates << "short_description = ?"
          params << short_description
        end

        if value
          updates << "value = ?"
          params << JSON.generate(value)
        end

        params << root_thread_id
        params << key

        @db.execute("UPDATE env_data SET #{updates.join(', ')} WHERE root_thread_id = ? AND key = ?", params)
        true
      end

      # Delete an env data entry.
      # @param root_thread_id [String] Root thread scope
      # @param key [String] Data key
      # @return [Boolean] True if deleted, false if key not found
      def delete_env_data(root_thread_id:, key:)
        @db.execute("DELETE FROM env_data WHERE root_thread_id = ? AND key = ?", [root_thread_id, key])
        @db.changes > 0
      end

      # --- Usage Aggregation ---

      # Get total token usage for a session.
      # @param session_id [String] Session ID
      # @return [Hash] Aggregated usage data
      def session_usage(session_id)
        rows = @db.execute(<<~SQL, [session_id])
          SELECT usage FROM messages WHERE session_id = ? AND usage IS NOT NULL
        SQL

        aggregate_usage_rows(rows)
      end

      # Get usage for a full thread tree (session + all descendants).
      # @param session_id [String] Root session ID
      # @return [Hash] Aggregated usage across the tree
      def thread_tree_usage(session_id)
        tree = get_thread_tree(session_id)
        return empty_usage unless tree

        collect_tree_usage(tree)
      end

      # --- Export ---

      # Export a session to JSON format.
      # @param session_id [String] Session ID
      # @return [Hash] Session data with messages
      def export_session_json(session_id)
        session = get_session(session_id)
        return nil unless session

        messages = get_messages(session_id)

        {
          id: session[:id],
          po_name: session[:po_name],
          name: session[:name],
          source: session[:source],
          source_client: session[:source_client],
          created_at: session[:created_at]&.iso8601,
          updated_at: session[:updated_at]&.iso8601,
          metadata: session[:metadata],
          messages: messages.map do |m|
            {
              role: m[:role].to_s,
              content: m[:content],
              from_po: m[:from_po],
              tool_calls: m[:tool_calls],
              tool_results: m[:tool_results],
              created_at: m[:created_at]&.iso8601
            }
          end
        }
      end

      # Export a session to Markdown format.
      # @param session_id [String] Session ID
      # @return [String] Markdown content
      def export_session_markdown(session_id)
        session = get_session(session_id)
        return nil unless session

        messages = get_messages(session_id)

        lines = []
        lines << "# Session: #{session[:name] || 'Unnamed'}"
        lines << ""
        lines << "- **PO**: #{session[:po_name]}"
        lines << "- **Source**: #{session[:source]}"
        lines << "- **Created**: #{session[:created_at]&.strftime('%Y-%m-%d %H:%M')}"
        lines << "- **Updated**: #{session[:updated_at]&.strftime('%Y-%m-%d %H:%M')}"
        lines << "- **Messages**: #{messages.length}"
        lines << ""
        lines << "---"
        lines << ""

        messages.each do |m|
          timestamp = m[:created_at]&.strftime('%H:%M')
          role_label = case m[:role].to_s
                       when "user" then "**User**"
                       when "assistant" then "**#{m[:from_po] || session[:po_name]}**"
                       when "tool" then "*Tool*"
                       else "**#{m[:role]}**"
                       end

          lines << "#{role_label} (#{timestamp}):"
          lines << ""

          if m[:content]
            lines << m[:content]
            lines << ""
          end

          if m[:tool_calls]
            lines << "<details><summary>Tool calls</summary>"
            lines << ""
            lines << "```json"
            lines << JSON.pretty_generate(m[:tool_calls])
            lines << "```"
            lines << "</details>"
            lines << ""
          end

          if m[:tool_results]
            lines << "<details><summary>Tool results</summary>"
            lines << ""
            lines << "```json"
            lines << JSON.pretty_generate(m[:tool_results])
            lines << "```"
            lines << "</details>"
            lines << ""
          end

          lines << "---"
          lines << ""
        end

        lines.join("\n")
      end

      # Export all sessions for a PO.
      # @param po_name [String] PO name
      # @param format [Symbol] :json or :markdown
      # @return [String] Exported content
      def export_all_sessions(po_name:, format: :json)
        sessions = list_sessions(po_name: po_name)

        case format
        when :json
          exported = sessions.map { |s| export_session_json(s[:id]) }
          JSON.pretty_generate(exported)
        when :markdown
          sessions.map { |s| export_session_markdown(s[:id]) }.join("\n\n")
        else
          raise ArgumentError, "Unknown format: #{format}"
        end
      end

      # Export a full thread tree as a single markdown document.
      # Follows all delegation sub-threads recursively.
      # @param session_id [String] Root session ID
      # @return [String, nil] Markdown content
      def export_thread_tree_markdown(session_id)
        tree = get_thread_tree(session_id)
        return nil unless tree

        lines = []
        lines << "# Thread Export"
        lines << ""
        lines << "- **Root PO**: #{tree[:session][:po_name]}"
        lines << "- **Started**: #{tree[:session][:created_at]&.strftime('%Y-%m-%d %H:%M')}"
        lines << "- **Exported**: #{Time.now.strftime('%Y-%m-%d %H:%M')}"
        lines << ""
        lines << "---"
        lines << ""

        render_thread_node(tree, lines, depth: 0)
        lines.join("\n")
      end

      # Export a full thread tree as structured JSON.
      # @param session_id [String] Root session ID
      # @return [Hash, nil] Tree data
      def export_thread_tree_json(session_id)
        tree = get_thread_tree(session_id)
        return nil unless tree

        serialize_tree_for_export(tree)
      end

      # --- Import ---

      # Import a session from JSON data.
      # @param data [Hash] Session data (as returned by export_session_json)
      # @param po_name [String, nil] Override PO name
      # @return [String] New session ID
      def import_session(data, po_name: nil)
        data = data.transform_keys(&:to_sym) if data.is_a?(Hash)

        # Create new session with new ID
        new_id = create_session(
          po_name: po_name || data[:po_name],
          name: "#{data[:name]} (imported)",
          source: "tui",
          metadata: (data[:metadata] || {}).merge(
            imported_from: data[:id],
            imported_at: Time.now.utc.iso8601,
            original_source: data[:source]
          )
        )

        # Import messages
        messages = data[:messages] || []
        messages.each do |m|
          m = m.transform_keys(&:to_sym) if m.is_a?(Hash)
          add_message(
            session_id: new_id,
            role: m[:role],
            content: m[:content],
            from_po: m[:from_po],
            tool_calls: m[:tool_calls],
            tool_results: m[:tool_results]
          )
        end

        new_id
      end

      private

      TOOL_RESULT_TRUNCATE_LIMIT = 10_000

      def render_thread_node(node, lines, depth:)
        session = node[:session]
        messages = get_messages(session[:id])
        indent = "  " * depth
        po_name = session[:po_name]
        children = node[:children] || []

        # Build a lookup: tool_call_name → child delegation node
        # so we can render delegations inline where the tool call happened
        delegation_children = {}
        other_children = []
        children.each do |child|
          child_po = child[:session][:po_name]
          if child[:session][:thread_type] == "delegation"
            delegation_children[child_po] ||= []
            delegation_children[child_po] << child
          else
            other_children << child
          end
        end

        # Thread header
        if depth == 0
          lines << "## #{po_name}"
        else
          type_label = session[:thread_type] == "delegation" ? "Delegation" : (session[:thread_type] || "thread").capitalize
          lines << ""
          lines << "#{indent}### #{type_label} → #{po_name}"
          lines << "#{indent}*Created by #{session[:parent_po]}*" if session[:parent_po]
        end
        lines << ""

        # Messages
        messages.each do |msg|
          case msg[:role]
          when :user
            from = msg[:from_po] || "human"
            lines << "#{indent}**#{from}:**"
            lines << ""
            lines << "#{indent}#{msg[:content]}" if msg[:content]
            lines << ""
          when :assistant
            lines << "#{indent}**#{po_name}:**"
            lines << ""
            if msg[:content]
              msg[:content].each_line { |l| lines << "#{indent}#{l.rstrip}" }
              lines << ""
            end
            if msg[:tool_calls]
              msg[:tool_calls].each do |tc|
                tc_name = tc[:name] || tc["name"]
                tc_args = tc[:arguments] || tc["arguments"] || {}
                lines << "#{indent}<details>"
                lines << "#{indent}<summary>Tool call: <code>#{tc_name}</code></summary>"
                lines << ""
                lines << "#{indent}```json"
                JSON.pretty_generate(tc_args).each_line { |l| lines << "#{indent}#{l.rstrip}" }
                lines << "#{indent}```"
                lines << "#{indent}</details>"
                lines << ""

                # Render delegation sub-thread inline if this tool call targets a PO
                if delegation_children[tc_name]
                  child_node = delegation_children[tc_name].shift
                  if child_node
                    render_thread_node(child_node, lines, depth: depth + 1)
                  end
                end
              end
            end
          when :tool
            results = msg[:tool_results] || msg[:results] || []
            results.each do |r|
              r_name = r[:name] || r["name"] || "tool"
              r_content = r[:content] || r["content"] || ""
              lines << "#{indent}<details>"
              lines << "#{indent}<summary>Result from <code>#{r_name}</code></summary>"
              lines << ""
              lines << "#{indent}```"
              if r_content.to_s.length > TOOL_RESULT_TRUNCATE_LIMIT
                display = r_content.to_s[0, TOOL_RESULT_TRUNCATE_LIMIT] + "\n... (truncated)"
              else
                display = r_content.to_s
              end
              display.each_line { |l| lines << "#{indent}#{l.rstrip}" }
              lines << "#{indent}```"
              lines << "#{indent}</details>"
              lines << ""
            end
          end
        end

        # Render any remaining children that weren't matched to a tool call
        # (e.g., fork threads, or delegations we couldn't match by name)
        remaining = delegation_children.values.flatten + other_children
        remaining.each do |child|
          render_thread_node(child, lines, depth: depth + 1)
        end
      end

      def serialize_tree_for_export(node)
        session = node[:session]
        messages = get_messages(session[:id])

        {
          session: {
            id: session[:id],
            po_name: session[:po_name],
            name: session[:name],
            thread_type: session[:thread_type],
            parent_po: session[:parent_po],
            created_at: session[:created_at]&.iso8601
          },
          messages: messages.map { |m|
            {
              role: m[:role].to_s,
              content: m[:content],
              from_po: m[:from_po],
              tool_calls: m[:tool_calls],
              tool_results: m[:tool_results],
              usage: m[:usage],
              created_at: m[:created_at]&.iso8601
            }
          },
          children: (node[:children] || []).map { |c| serialize_tree_for_export(c) }
        }
      end

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
            source TEXT DEFAULT 'tui',
            source_client TEXT,
            last_message_source TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            metadata TEXT DEFAULT '{}',
            -- Thread/branching support (v4)
            parent_session_id TEXT,
            parent_message_id INTEGER,
            parent_po TEXT,
            thread_type TEXT DEFAULT 'root'
          );

          CREATE INDEX IF NOT EXISTS idx_sessions_po_name ON sessions(po_name);
          CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at);
          CREATE INDEX IF NOT EXISTS idx_sessions_source ON sessions(source);
          CREATE INDEX IF NOT EXISTS idx_sessions_parent ON sessions(parent_session_id);

          CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id),
            role TEXT NOT NULL,
            content TEXT,
            from_po TEXT,
            tool_calls TEXT,
            tool_results TEXT,
            usage TEXT,
            created_at TEXT NOT NULL
          );

          CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages(session_id);

          -- Full-text search index for message content
          CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            content,
            content='messages',
            content_rowid='id'
          );

          -- Triggers to keep FTS in sync
          CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
            INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
          END;

          CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.id, old.content);
          END;

          CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.id, old.content);
            INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
          END;

          -- Event log for message bus persistence (v5)
          CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            timestamp TEXT NOT NULL,
            from_name TEXT NOT NULL,
            to_name TEXT NOT NULL,
            message TEXT NOT NULL,
            summary TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          );

          CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
          CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);

          -- Shared environment data for delegation chains (v7)
          CREATE TABLE IF NOT EXISTS env_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            root_thread_id TEXT NOT NULL,
            key TEXT NOT NULL,
            short_description TEXT NOT NULL,
            value TEXT NOT NULL,
            stored_by TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(root_thread_id, key)
          );

          CREATE INDEX IF NOT EXISTS idx_env_data_root ON env_data(root_thread_id);
        SQL
      end

      def migrate_schema(from_version)
        if from_version < 2
          # Add source tracking columns
          @db.execute_batch(<<~SQL)
            ALTER TABLE sessions ADD COLUMN source TEXT DEFAULT 'tui';
            ALTER TABLE sessions ADD COLUMN source_client TEXT;
            ALTER TABLE sessions ADD COLUMN last_message_source TEXT;
            CREATE INDEX IF NOT EXISTS idx_sessions_source ON sessions(source);
          SQL
        end

        if from_version < 3
          # Add full-text search for messages
          @db.execute_batch(<<~SQL)
            -- Full-text search index for message content
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
              content,
              content='messages',
              content_rowid='id'
            );

            -- Triggers to keep FTS in sync
            CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
              INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
            END;

            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
              INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.id, old.content);
            END;

            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
              INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.id, old.content);
              INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
            END;
          SQL

          # Populate FTS with existing messages
          @db.execute("INSERT INTO messages_fts(rowid, content) SELECT id, content FROM messages WHERE content IS NOT NULL")
        end

        if from_version < 4
          # Add thread/branching support columns
          @db.execute_batch(<<~SQL)
            ALTER TABLE sessions ADD COLUMN parent_session_id TEXT;
            ALTER TABLE sessions ADD COLUMN parent_message_id INTEGER;
            ALTER TABLE sessions ADD COLUMN parent_po TEXT;
            ALTER TABLE sessions ADD COLUMN thread_type TEXT DEFAULT 'root';
            CREATE INDEX IF NOT EXISTS idx_sessions_parent ON sessions(parent_session_id);
          SQL
        end

        if from_version < 5
          # Add event log table for message bus persistence
          @db.execute_batch(<<~SQL)
            CREATE TABLE IF NOT EXISTS events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT,
              timestamp TEXT NOT NULL,
              from_name TEXT NOT NULL,
              to_name TEXT NOT NULL,
              message TEXT NOT NULL,
              summary TEXT,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
            CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
          SQL
        end

        if from_version < 6
          # Add usage column for token tracking
          @db.execute("ALTER TABLE messages ADD COLUMN usage TEXT")
        end

        if from_version < 7
          # Add shared environment data table for delegation chains
          @db.execute_batch(<<~SQL)
            CREATE TABLE IF NOT EXISTS env_data (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              root_thread_id TEXT NOT NULL,
              key TEXT NOT NULL,
              short_description TEXT NOT NULL,
              value TEXT NOT NULL,
              stored_by TEXT NOT NULL,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
              UNIQUE(root_thread_id, key)
            );

            CREATE INDEX IF NOT EXISTS idx_env_data_root ON env_data(root_thread_id);
          SQL
        end
      end

      def empty_usage
        { input_tokens: 0, output_tokens: 0, total_tokens: 0, estimated_cost_usd: 0.0, calls: 0, by_model: {} }
      end

      def aggregate_usage_rows(rows)
        totals = empty_usage

        rows.each do |row|
          usage = JSON.parse(row["usage"], symbolize_names: true)
          input = usage[:input_tokens] || 0
          output = usage[:output_tokens] || 0
          model = usage[:model] || "unknown"

          totals[:input_tokens] += input
          totals[:output_tokens] += output
          totals[:total_tokens] += input + output
          totals[:estimated_cost_usd] += LLM::Pricing.calculate(model: model, input_tokens: input, output_tokens: output)
          totals[:calls] += 1

          # Breakdown by model
          totals[:by_model][model] ||= { input_tokens: 0, output_tokens: 0, estimated_cost_usd: 0.0, calls: 0 }
          totals[:by_model][model][:input_tokens] += input
          totals[:by_model][model][:output_tokens] += output
          totals[:by_model][model][:estimated_cost_usd] += LLM::Pricing.calculate(model: model, input_tokens: input, output_tokens: output)
          totals[:by_model][model][:calls] += 1
        end

        totals
      end

      def collect_tree_usage(node)
        # Get usage for this node's session
        session_rows = @db.execute(<<~SQL, [node[:session][:id]])
          SELECT usage FROM messages WHERE session_id = ? AND usage IS NOT NULL
        SQL

        totals = aggregate_usage_rows(session_rows)

        # Recurse into children
        (node[:children] || []).each do |child|
          child_usage = collect_tree_usage(child)
          totals[:input_tokens] += child_usage[:input_tokens]
          totals[:output_tokens] += child_usage[:output_tokens]
          totals[:total_tokens] += child_usage[:total_tokens]
          totals[:estimated_cost_usd] += child_usage[:estimated_cost_usd]
          totals[:calls] += child_usage[:calls]

          # Merge by_model
          child_usage[:by_model].each do |model, data|
            totals[:by_model][model] ||= { input_tokens: 0, output_tokens: 0, estimated_cost_usd: 0.0, calls: 0 }
            totals[:by_model][model][:input_tokens] += data[:input_tokens]
            totals[:by_model][model][:output_tokens] += data[:output_tokens]
            totals[:by_model][model][:estimated_cost_usd] += data[:estimated_cost_usd]
            totals[:by_model][model][:calls] += data[:calls]
          end
        end

        totals
      end

      def parse_session_row(row, include_count: false)
        result = {
          id: row["id"],
          po_name: row["po_name"],
          name: row["name"],
          source: row["source"] || "tui",
          source_client: row["source_client"],
          last_message_source: row["last_message_source"],
          created_at: row["created_at"] ? Time.parse(row["created_at"]) : nil,
          updated_at: row["updated_at"] ? Time.parse(row["updated_at"]) : nil,
          metadata: row["metadata"] ? JSON.parse(row["metadata"], symbolize_names: true) : {},
          # Thread fields (v4)
          parent_session_id: row["parent_session_id"],
          parent_message_id: row["parent_message_id"],
          parent_po: row["parent_po"],
          thread_type: row["thread_type"] || "root"
        }
        result[:message_count] = row["message_count"] if include_count && row["message_count"]
        result
      end

      def parse_event_row(row)
        {
          id: row["id"],
          session_id: row["session_id"],
          timestamp: row["timestamp"] ? Time.parse(row["timestamp"]) : nil,
          from: row["from_name"],
          to: row["to_name"],
          message: row["message"],
          summary: row["summary"],
          created_at: row["created_at"] ? Time.parse(row["created_at"]) : nil
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
          usage: row["usage"] ? JSON.parse(row["usage"], symbolize_names: true) : nil,
          created_at: row["created_at"] ? Time.parse(row["created_at"]) : nil
        }
      end
    end
  end
end
