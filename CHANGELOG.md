# Changelog

All notable changes to PromptObjects are documented in this file.

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
