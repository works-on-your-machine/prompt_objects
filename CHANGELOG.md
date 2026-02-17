# Changelog

All notable changes to PromptObjects are documented in this file.

## [0.6.0] - 2026-02-17

### Added

- **Shared environment data** — 5 new universal capabilities (`store_env_data`, `get_env_data`, `list_env_data`, `update_env_data`, `delete_env_data`) provide a thread-scoped key-value store for delegation chains. Data is scoped to the root thread so separate conversations stay isolated. Entries include a `short_description` for lightweight LLM discovery without fetching full values.
- **Live environment data pane** — New collapsible pane in the Inspector shows shared env data updating in real-time as POs store and modify entries during delegation chains. WebSocket broadcasting (`env_data_changed`, `env_data_list`), a REST endpoint (`GET /api/sessions/:id/env_data`), and env data rendering in the Thread Explorer.
- **Delegation context** — POs now receive context about their delegation chain. An expanded system prompt teaches POs about their nature, a delegation preamble prepends caller context to delegated messages, and the full delegation chain is built from thread lineage.
- **Capability guard** — `execute_tool_calls` now rejects tools not in a PO's allowed set (declared capabilities + universals). Previously the LLM could hallucinate calls to any registered tool and they would execute. Now it receives an error directing it to use `add_capability` first.
- **Env data in thread exports** — `serialize_tree_for_export` includes env data entries at the root level of exported thread trees. Thread Explorer renders these in an amber-colored section.

### Fixed

- **Root font-size causing undersized text** — Removed a `font-size: 14px` on the root `html` element that made all rem-based Tailwind sizes ~12% smaller than intended (e.g. `text-xs` computed to 10.5px instead of 12px).
- **Invisible resize handle boundaries** — Added border styling to horizontal and vertical resize handles so pane boundaries are visible without hovering.
- **Stale MCP tools tests** — Fixed test expectations broken by PO serialization centralization in 0.5.0.

## [0.5.0] - 2026-02-13

### Added

- **Smalltalk System Browser redesign** — Complete frontend overhaul replacing the chat-app UI with a multi-pane object browser. POs are treated as live objects in a running image: permanent ObjectList (left pane), multi-pane Inspector with MethodList + SourcePane, REPL-style Workspace, and bottom Transcript. Warm charcoal + amber palette with Geist fonts. All panels resizable via drag handles.
- **Collapsible inspector top pane** — The Methods + Source pane has a thin header bar with a collapse/expand toggle. When collapsed, the Workspace fills the full inspector height. Collapse state persists across PO switches.
- **Source entry in method list** — A "Source" entry at the top of the method list provides a clear way to navigate back to the PO's prompt after inspecting a capability.
- **Dynamic Ollama model discovery** — LLM config now queries the Ollama API for installed models instead of using a static list.

### Fixed

- **Capabilities disappearing on file save** — `po_modified` events were sending capabilities as plain string names instead of rich objects, overwriting the store. All serialization paths now emit consistent `{name, description, parameters}` objects.
- **Centralized PO serialization** — Moved duplicated state/message/session serialization from WebSocketHandler and API routes into `PromptObject` (`to_state_hash`, `to_summary_hash`, `to_inspect_hash`). Eliminates inconsistent serialization as a class of bug.
- **Missing items field in array tool schemas** — LLM APIs reject array parameters without an `items` field. Added a defensive sanitizer in `Capability#descriptor` as a fallback.
- **OpenAI adapter error details** — 4xx errors from Ollama now surface the actual rejection reason instead of just "status 400".
- **All WebSocket message types handled** — Added frontend handlers for `prompt_updated`, `llm_error`, `session_created`, and `session_switched`. Removed defensive normalization workarounds.

## [0.4.0] - 2026-02-11

### Added

- **Spatial Canvas** — Three.js 2D visualization at `/canvas` showing POs as glowing hexagonal nodes with force-directed layout, tool call diamonds, animated message arcs with traveling particles, and click-to-inspect side panels. Real-time updates from the same WebSocket feed as the dashboard. Zoom, pan, and keyboard shortcuts (F to fit, Escape to deselect).
- **PO-to-PO delegation broadcasting** — Server now broadcasts `po_delegation_started` and `po_delegation_completed` WebSocket events when one PO calls another. Delegated POs show as active in both the canvas (cyan glow, "called by X" status) and dashboard views. Replaces client-side inference from message history scanning.
- **Ruby 4 support** — CI now tests against Ruby 4. Fixed empty required parameter handling for compatibility. Thanks to [@radanskoric](https://github.com/radanskoric) for the contribution! ([#2](https://github.com/works-on-your-machine/prompt_objects/pull/2))

### Fixed

- **WebSocket reconnection lifecycle** — Fixed duplicate connections on page refresh caused by zombie `onclose` handlers. Added socket identity guards, close-before-reconnect, and `handleMessageRef` pattern to prevent stale closures.
- **Stale state on disconnect** — PO statuses now reset to idle when WebSocket disconnects, preventing stuck "thinking" indicators and stale streaming content.
- **Chat input locked on disconnect** — Chat input is now only disabled when the PO is busy AND connected. Shows "Reconnecting..." indicator when disconnected instead of permanently locking.
- **Tool calls not appearing on canvas** — Tool call visualization now extracts from PO message history instead of looking for a format bus messages don't use.

## [0.3.1] - 2025-02-08

### Added

- **Thread Explorer** — Standalone HTML visualizer for exploring conversation thread exports. Three views: sequence diagram (swim lanes showing PO communication), timeline (flat chronological event list), and detail panel (full conversation with tool calls). Includes token cost bar, search, per-PO filtering, breadcrumb navigation, and structural event highlighting.
- **`explore` CLI command** — Open Thread Explorer from the command line. `prompt_objects explore <env>` lists root threads and opens the most recent; `--session ID` targets a specific thread. Data is embedded directly so it opens ready to go.

### Fixed

- Delegation messages now correctly show the calling PO's name instead of "human". Previously `context.current_capability` resolved to the target PO (matching its own name), causing a fallback to "human". Now uses `context.calling_po`.
- CLI integration tests skip gracefully in CI when no LLM API key is available, instead of failing.

## [0.3.0] - 2025-02-05

### Added

- **Token usage & cost tracking** — Track input/output tokens and estimated costs per session and across delegation trees. Includes per-model pricing table and a Usage Panel in the web UI (right-click a thread to view).
- **Ollama & OpenRouter support** — Connect to local Ollama models or OpenRouter's model marketplace. Both reuse the OpenAI adapter with configurable base URLs. Ollama models are auto-discovered from the local API.
- **Thread export** — Export any conversation thread as Markdown or JSON, including full delegation chains. Delegation sub-threads render inline next to the tool call that triggered them, preserving the actual flow of work. Available via right-click context menu or REST API.
- **ARC-AGI-1 template** — A template for solving ARC-AGI challenges with a solver PO, data manager PO, and 7 custom grid primitives (load, render, diff, info, find objects, transform, test solution).
- **Persistent event log** — Message bus events are now persisted to SQLite for replay and debugging.
- **REST message endpoint & events API** — Send messages to POs and retrieve bus events via HTTP. Includes server discovery for CLI commands.
- **CLI `message` and `events` commands** — Interact with a running environment from the command line without opening the web UI.

### Fixed

- Custom primitives (created by POs or from templates) now auto-load on environment startup. Previously they were saved to `env/primitives/` but never registered on restart.
- Message serialization bugs that caused crashes when tool calls contained non-string values.
- Frontend auto-rebuilds when running `prompt_objects serve` in development.
- Delegation sub-threads in exports now appear inline after the triggering tool call, not at the bottom of the document.
- Tool result truncation limit increased from 2,000 to 10,000 characters to preserve detail in exports.
- Full message content stored in bus; truncation applied only at display time.

## [0.2.0] - 2025-01-23

### Added

- **GitHub Actions CI** — Automated test suite running on Ruby 3.2, 3.3, and 3.4.
- **Conversation threads with delegation isolation** — Each PO-to-PO delegation runs in its own thread, keeping conversations clean.
- **Thread sidebar** — Navigate between threads with auto-naming and instant feedback on creation.
- **Real-time capability updates** — Adding/removing capabilities broadcasts changes to the web UI immediately.
- **PO prompt editing** — Edit a Prompt Object's system prompt directly in the web UI with auto-save back to the markdown file.
- **`modify_prompt` universal capability** — POs can rewrite their own system prompts at runtime.
- **Environment recovery tools** — `remove_capability` and `delete_primitive` for cleaning up broken state.
- **Streaming tool calls** — Tool call chains display in real-time as they execute, not just after completion.
- **Capabilities panel** — Visual display of each PO's available primitives and PO-to-PO capabilities.
- **Core PromptObject tests** — Unit test suite for the core framework.

### Fixed

- Session store binding and Gemini model name resolution.
- Tool results missing function name for Gemini API compatibility.
- `tool_calls` Hash vs ToolCall object handling across all adapters.
- Claude API response parsing for new PO chat updates.
- Thread switching now immediately shows the new thread on creation.
- Session message counts and cross-session response routing.

## [0.1.0] - 2025-01-15

### Added

- **Core framework** — Markdown files with YAML frontmatter act as LLM-backed autonomous entities.
- **Unified capability interface** — Primitives (Ruby) and Prompt Objects (Markdown) share the same `receive(message, context:)` interface.
- **Built-in primitives** — `read_file`, `list_files`, `write_file`, `http_get`.
- **Universal capabilities** — `ask_human`, `think`, `request_capability`, `create_capability`, `add_capability`.
- **Multi-provider LLM support** — OpenAI, Anthropic, and Gemini adapters with model selection UI.
- **PO-to-PO communication** — Prompt Objects can call each other as capabilities through the message bus.
- **Self-modification** — POs can create new Prompt Objects and primitives at runtime (with human approval).
- **Web UI** — React frontend with real-time WebSocket updates, split-view layout, markdown rendering.
- **Notification system** — Non-blocking human-in-the-loop via `ask_human` with notification bell and dropdown.
- **Live filesystem watching** — Changes to `.md` files in the objects directory are reflected immediately.
- **SQLite session storage** — Persistent conversation history with WAL mode for concurrent access.
- **Environment management** — Create, list, and manage isolated environments with `prompt_objects env` commands.
- **Templates** — Bootstrap new environments from templates (`basic`, `pair`, `team`, and more).
- **MCP server mode** — Expose POs as tools via the Model Context Protocol for external client integration.
- **CLI** — `prompt_objects` command with subcommands for environment management, serving, and interaction.
