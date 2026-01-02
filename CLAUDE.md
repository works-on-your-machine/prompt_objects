# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PromptObjects** is a Ruby framework where markdown files with LLM-backed behavior act as first-class autonomous entities. The core insight: **everything is a capability**—primitives (Ruby code) and Prompt-Objects (markdown files) share the same interface, differing only in interpretation complexity.

**Current Status**: Design phase—`design-doc-v2.md` contains the full specification, `IMPLEMENTATION_PLAN.md` has detailed phased build plans. No implementation code exists yet.

## Architecture

```
ENVIRONMENT
├── CAPABILITY REGISTRY
│   ├── PRIMITIVES (Ruby) - deterministic interpretation
│   └── PROMPT-OBJECTS (Markdown) - semantic interpretation via LLM
├── MESSAGE BUS - routes messages, logs for visualization
└── TERMINAL UI (Charm) - capability bar, message log, conversation, input
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
- `request_capability` - ask environment for new capability

## Technology Stack

- **Ruby** - core implementation
- **LLM APIs** - OpenAI, Anthropic, Gemini (adapter pattern)
- **Charm** - Terminal UI (Bubble Tea for interaction, Lipgloss for styling, Glamour for markdown)
- **MCP** - Model Context Protocol integration

## Planned File Structure

```
prompt_objects/
├── exe/prompt_objects          # CLI entrypoint
├── lib/
│   ├── prompt_objects.rb       # Main entry
│   └── prompt_objects/
│       ├── environment.rb      # Runtime container
│       ├── capability.rb       # Base interface
│       ├── prompt_object.rb    # PO implementation
│       ├── primitive.rb        # Primitive tool wrapper
│       ├── loader.rb           # Parses frontmatter + body
│       ├── registry.rb         # Capability registration
│       ├── message_bus.rb      # Message routing and logging
│       ├── llm/                # LLM adapters
│       ├── primitives/         # Built-in primitives (read_file, etc.)
│       ├── universal/          # Universal capabilities
│       ├── mcp/                # MCP integration
│       └── ui/                 # Charm-based terminal UI
├── objects/                    # Where Prompt-Objects live (.md files)
└── primitives/                 # Optional user-defined primitives
```

## Implementation Phases

1. **Core Loop**: Capability base, PromptObject, Loader, single LLM adapter, simple REPL
2. **Primitives & Binding**: Primitive base, built-in primitives, Registry
3. **Multi-Capability**: Message bus with logging, PO↔PO communication
4. **Self-Modification**: Universal capabilities including create_capability
5. **Polish & UI**: Full Charm integration, all UI components
6. **Demo Ready**: Error handling, testing, practice runs

## Key Concepts

- **Semantic Binding**: Natural language → capability call (visible in message log)
- **PO↔PO Communication**: Prompt-Objects can call each other as capabilities
- **Self-Modification**: System can create new Prompt-Objects at runtime (with human approval)
- **Human-in-the-Loop**: POs ask for confirmation on dangerous actions, clarification when ambiguous
- **Non-blocking Human Queue**: When POs need human input (`ask_human`), they suspend (via Fibers) and queue a notification. Multiple POs can wait simultaneously. Human responds via notification panel, PO resumes automatically.
