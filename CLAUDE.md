# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PromptObjects** is a Ruby framework where markdown files with LLM-backed behavior act as first-class autonomous entities. The core insight: **everything is a capability**—primitives (Ruby code) and Prompt-Objects (markdown files) share the same interface, differing only in interpretation complexity.

**Current Status**: v0.5.0 — The core framework is fully implemented and functional. The original 6-phase implementation plan is complete. Active development is focused on visualization, developer experience, and exploring new primitives. See `CHANGELOG.md` for release history and `design-doc-v2.md` / `IMPLEMENTATION_PLAN.md` for original design context.

## Architecture

```
RUNTIME (Environment)
├── CAPABILITY REGISTRY
│   ├── PRIMITIVES (Ruby) - deterministic interpretation
│   ├── PROMPT-OBJECTS (Markdown) - semantic interpretation via LLM
│   └── UNIVERSAL CAPABILITIES - available to all POs automatically
├── MESSAGE BUS - routes messages, logs to SQLite for replay
├── SESSION STORE (SQLite) - persistent conversation threads, delegation tracking
├── HUMAN QUEUE - non-blocking ask_human requests
├── WEB SERVER (Sinatra + WebSocket) - serves React frontend
└── MCP SERVER - exposes POs as tools via Model Context Protocol
```

### Unified Capability Interface
Both primitives and Prompt-Objects implement:
```ruby
class Capability
  def name          # string identifier
  def description   # what this capability does
  def receive(message, context:)  # handle message, return response
end
```

### Prompt-Object Structure
Markdown files with two parts:
- **Frontmatter (YAML)**: Configuration (name, description, capabilities)
- **Body (Markdown)**: Identity and behavior (becomes LLM system prompt)

Example:
```markdown
---
name: reader
description: Helps people understand files
capabilities:
  - read_file
  - list_files
---

# Reader
## Identity
You are a careful, thoughtful file reader...
```

### Universal Capabilities
Available to all Prompt-Objects automatically (no frontmatter declaration needed):
- `ask_human` - pause for human input/confirmation
- `think` - internal reasoning (not shown to human)
- `create_capability` / `add_capability` / `remove_capability` - self-modification
- `list_capabilities` / `list_primitives` - introspection
- `create_primitive` / `add_primitive` / `delete_primitive` / `verify_primitive` / `modify_primitive` / `request_primitive` - primitive management
- `modify_prompt` - rewrite own system prompt at runtime

### PO-to-PO Delegation
When a PO calls another PO, the system creates an isolated delegation thread in the target PO. The caller's context is tracked so messages show correct provenance. Delegation start/complete events are broadcast via WebSocket for real-time UI updates.

## Technology Stack

- **Ruby** (>= 3.2, tested through Ruby 4) - core implementation
- **LLM APIs** - OpenAI, Anthropic, Gemini, Ollama, OpenRouter (adapter pattern via `LLM::Factory`)
- **Sinatra** - web server for REST API and static file serving
- **faye-websocket** - real-time WebSocket communication
- **React + TypeScript** - web frontend (dashboard, chat, capabilities panel)
- **Three.js** - spatial canvas visualization (force-directed PO graph)
- **SQLite** - session persistence and event log storage
- **MCP** - Model Context Protocol server mode

## File Structure

```
prompt_objects/
├── exe/prompt_objects              # CLI entrypoint
├── lib/
│   ├── prompt_objects.rb           # Main entry, requires all modules
│   └── prompt_objects/
│       ├── environment.rb          # Runtime container (registry, bus, LLM, sessions)
│       ├── capability.rb           # Base capability interface
│       ├── prompt_object.rb        # PO implementation (LLM conversation loop)
│       ├── primitive.rb            # Primitive tool wrapper
│       ├── loader.rb               # Parses frontmatter + body from .md files
│       ├── registry.rb             # Capability registration and lookup
│       ├── message_bus.rb          # Message routing, logging, SQLite persistence
│       ├── human_queue.rb          # Non-blocking human interaction queue
│       ├── cli.rb                  # CLI command definitions
│       ├── server.rb               # Web server setup
│       ├── server/
│       │   ├── app.rb              # Sinatra application
│       │   ├── api/routes.rb       # REST API endpoints
│       │   ├── websocket_handler.rb # WebSocket event handling
│       │   └── file_watcher.rb     # Live .md file change detection
│       ├── llm/
│       │   ├── factory.rb          # Provider/model selection
│       │   ├── response.rb         # Unified response object
│       │   ├── pricing.rb          # Token cost calculation
│       │   ├── openai_adapter.rb   # OpenAI + Ollama + OpenRouter
│       │   ├── anthropic_adapter.rb
│       │   └── gemini_adapter.rb
│       ├── primitives/             # Built-in: read_file, list_files, write_file, http_get
│       ├── universal/              # 14 universal capabilities (see list above)
│       ├── connectors/             # Interface adapters (base, mcp)
│       ├── mcp/                    # MCP server and tool definitions
│       ├── session/
│       │   └── store.rb            # SQLite session/thread persistence
│       └── environment/
│           ├── manager.rb          # Create/list/clone environments
│           ├── manifest.rb         # Environment metadata (manifest.yml)
│           ├── git.rb              # Auto-commit integration
│           ├── exporter.rb         # Environment export
│           └── importer.rb         # Environment import
├── frontend/                       # React + TypeScript web UI
│   └── src/
│       ├── App.tsx
│       ├── components/             # Dashboard, chat, capabilities panel
│       ├── canvas/                 # Three.js spatial visualization
│       ├── hooks/                  # WebSocket, state management hooks
│       ├── store/                  # Frontend state
│       └── types/                  # TypeScript type definitions
├── objects/                        # Default POs: greeter, reader, coordinator
├── templates/                      # Environment templates (basic, developer, writer, arc-agi-1, etc.)
├── tools/                          # Development tooling
└── test/                           # Unit and integration tests
```

## Key Concepts

- **Semantic Binding**: Natural language → capability call (visible in message log)
- **PO↔PO Communication**: Prompt-Objects call each other as capabilities through isolated delegation threads
- **Self-Modification**: POs can create new POs and primitives at runtime (with human approval)
- **Human-in-the-Loop**: POs use `ask_human` to pause and queue notifications; human responds asynchronously via the web UI
- **Environments**: Isolated collections of POs with their own sessions, git history, and configuration. Created from templates via CLI.
- **Thread Export**: Conversation threads (including delegation chains) exportable as Markdown or JSON

## Development

```bash
# Install dependencies
bundle install
cd frontend && npm install && cd ..

# Run tests
bundle exec rake test

# Serve an environment with web UI
prompt_objects serve <env-name> --open

# Environment management
prompt_objects env create <name> --template basic
prompt_objects env list
prompt_objects env info <name>
```

## Releases

Always tag releases. Pushing a version tag triggers the Discord notification workflow (`.github/workflows/discord-release.yml`), which extracts the matching section from `CHANGELOG.md` and posts it.

```bash
# 1. Update version in prompt_objects.gemspec
# 2. Add changelog entry under ## [X.Y.Z] - YYYY-MM-DD
# 3. Commit: "Release vX.Y.Z — short description"
# 4. Tag and push:
git tag vX.Y.Z
git push && git push origin vX.Y.Z
# 5. Publish gem:
gem build prompt_objects.gemspec && gem push prompt_objects-X.Y.Z.gem
```
