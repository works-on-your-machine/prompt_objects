# PromptObjects

A framework where markdown files with LLM-backed behavior act as first-class autonomous entities.

## Architecture

PromptObjects is a unified Ruby project with:
- **Core Framework**: PromptObject, Capability, Registry, MessageBus
- **Ruby TUI**: Bubble Tea + Lipgloss + Glamour (Charm gems)
- **MCP Server**: For external clients (Claude Desktop, etc.)

## Progress

See **[epics.md](epics.md)** for detailed feature tracking and priorities.

### Quick Status
- **Core Framework**: Done
- **TUI**: Done (foundation, notifications, sessions)
- **Environments**: Done (git-backed, templates, export/import)
- **MCP Server**: Done
- **Charm Native**: Done (stable TUI with single Go runtime)
- **Markdown Rendering**: Done (via Glamour/charm-native)
- **Next Up**: Dashboard UX Overhaul (mouse support, PO-centric view)

## File Structure

```
lib/prompt_objects/
├── capability.rb           # Base capability class
├── prompt_object.rb        # LLM-backed capability
├── registry.rb             # Capability registry
├── message_bus.rb          # Inter-PO communication
├── human_queue.rb          # Pending human requests
├── loader.rb               # Markdown file loader
├── cli.rb                  # CLI commands
├── llm/
│   ├── client.rb           # Unified LLM client (via ruby_llm gem)
│   └── tool_call.rb        # Tool call representation
├── primitives/             # Built-in primitives
├── universal/              # Universal capabilities
├── environment/
│   ├── manager.rb          # Multi-env management
│   ├── manifest.rb         # Environment metadata
│   ├── git.rb              # Git operations
│   ├── exporter.rb         # Bundle export
│   └── importer.rb         # Bundle import
├── session/
│   └── store.rb            # SQLite session storage
├── mcp/
│   ├── server.rb           # MCP server
│   └── tools/              # MCP tool implementations
└── ui/
    ├── app.rb              # Main Bubble Tea app
    ├── styles.rb           # Lipgloss styles
    └── models/             # UI components
        ├── capability_bar.rb
        ├── conversation.rb
        ├── input.rb
        ├── message_log.rb
        ├── notification_panel.rb
        ├── request_responder.rb
        ├── po_inspector.rb
        ├── capability_editor.rb
        ├── setup_wizard.rb
        ├── env_picker.rb
        └── session_picker.rb
```

## Running

```bash
# Ruby TUI
bundle exec ruby exe/poop_tui

# With specific environment
bundle exec ruby exe/poop_tui --env myenv

# Development mode
bundle exec ruby exe/poop_tui --dev

# MCP Server (for Claude Desktop, etc.)
bundle exec ruby exe/poop_mcp

# CLI commands
bundle exec ruby exe/poop_tui env list
bundle exec ruby exe/poop_tui env create myenv --template minimal
bundle exec ruby exe/poop_tui env export myenv -o myenv.poenv
bundle exec ruby exe/poop_tui env import shared.poenv --as imported
```

## Keyboard Shortcuts (TUI)

| Key | Mode | Action |
|-----|------|--------|
| `i` | Normal | Enter insert mode |
| `Esc` | Insert | Return to normal mode |
| `Enter` | Insert | Send message |
| `h/l` or `←/→` | Normal | Switch PO |
| `S` | Normal | Open session picker |
| `I` | Normal | Inspect PO |
| `e` | Normal | Edit PO capabilities |
| `n` | Normal | Toggle notifications |
| `m` | Normal | Toggle message log |
| `?` | Normal | Toggle help |
| `q` | Normal | Quit |

## Environment Commands

```bash
env list              # List all environments
env create <name>     # Create new environment
env info <name>       # Show environment details
env export <name>     # Export as .poenv bundle
env import <file>     # Import from bundle
env archive <name>    # Soft delete
env restore <name>    # Restore from archive
env clone <src> <dst> # Clone environment
env default <name>    # Set default environment
```
