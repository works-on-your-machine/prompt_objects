# Phase 8: Environments (Images)

## Overview

Environments are the runtime state of a PromptObjects system - like Smalltalk images. Each environment is a complete, isolated workspace containing prompt objects, custom primitives, configuration, and conversation history.

**Key insight**: The environment IS the valuable artifact. Users build and refine their environments over time. The framework is just the engine; environments are the personalized systems users create.

## Core Concepts

### Environment
A git repository containing:
- Prompt objects (markdown files)
- Custom primitives (Ruby files, sandboxed)
- Configuration (metadata, preferences)
- Session database (SQLite, gitignored - private)

### Stdlib
Framework-provided objects and primitives that users can copy into their environments:
- **objects/**: Example POs (greeter, coordinator, reader) - copy to use
- **primitives/**: Common tools (read_file, list_files, http_get) - opt-in per PO

### Universal Capabilities
Always available to all POs (the "kernel"):
- ask_human, think, create_capability, add_capability, list_capabilities
- These enable the system itself - cannot be disabled

### Templates
Curated starter environments shipped with the gem:
- Users choose a template on first run
- Templates provide a starting point, not constraints

## Architecture

### User Data Location

```
~/.prompt_objects/                      # Default location (configurable)
├── config.yml                          # Global config
├── environments/
│   ├── default/                        # Git repo
│   │   ├── .git/
│   │   ├── manifest.yml                # Environment metadata
│   │   ├── objects/                    # Prompt objects
│   │   │   ├── my_coordinator.md
│   │   │   └── code_reviewer.md
│   │   ├── primitives/                 # Custom primitives
│   │   │   └── my_tool.rb
│   │   ├── sessions.db                 # SQLite (gitignored)
│   │   └── .gitignore                  # Ignores sessions.db
│   ├── work/                           # Another environment
│   └── personal/
└── archive/                            # Archived (soft-deleted) environments
```

### Framework Repo Structure

```
prompt-objects/                         # Gem source
├── lib/                                # Framework code
├── objects/                            # Stdlib POs (examples, copy to use)
│   ├── greeter.md
│   ├── coordinator.md
│   └── reader.md
├── templates/                          # Starter environments
│   ├── minimal/
│   │   ├── manifest.yml
│   │   └── objects/
│   │       └── assistant.md
│   ├── developer/
│   │   ├── manifest.yml
│   │   └── objects/
│   │       ├── coordinator.md
│   │       ├── code_reviewer.md
│   │       └── debugger.md
│   └── writer/
│       └── ...
└── exe/
    └── prompt_objects
```

## Environment Metadata (manifest.yml)

```yaml
name: work
description: My development environment
created_at: 2025-01-03T10:00:00Z
updated_at: 2025-01-03T14:30:00Z
last_opened: 2025-01-03T14:30:00Z

# UI customization
icon: "💻"
color: "#4A90D9"
tags:
  - development
  - ruby
  - daily-driver

# Preferences
default_po: coordinator

# Stats (auto-updated)
stats:
  total_messages: 1523
  total_sessions: 47
  po_count: 8
```

## Session Storage

Sessions stored in SQLite (`sessions.db`), gitignored for privacy:

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  po_name TEXT NOT NULL,
  name TEXT,
  created_at DATETIME,
  updated_at DATETIME,
  metadata JSON
);

CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  session_id TEXT REFERENCES sessions(id),
  role TEXT,           -- 'user', 'assistant', 'tool'
  content TEXT,
  from_po TEXT,        -- For delegation tracking
  tool_calls JSON,
  created_at DATETIME
);
```

## First-Run Experience

```
$ prompt_objects

╭─────────────────────────────────────────────────────────╮
│           Welcome to PromptObjects! 🎉                  │
│                                                         │
│  Let's set up your first environment.                   │
╰─────────────────────────────────────────────────────────╯

What would you like to name this environment?
> work

Choose a starting template:
  ▸ minimal     Basic coordinator to get started
    developer   Code review, debugging, testing specialists
    writer      Editor, researcher, fact-checker
    empty       Start from scratch

Creating environment 'work' from 'minimal' template...
Initialized git repository.
Created manifest.yml
Copied template objects.

╭─────────────────────────────────────────────────────────╮
│  Environment 'work' is ready!                           │
│  Location: ~/.prompt_objects/environments/work/         │
╰─────────────────────────────────────────────────────────╯

Press Enter to start...
```

## Environment Operations

### CLI Commands

```bash
# List environments
prompt_objects env list

# Create new environment
prompt_objects env create personal --template minimal

# Open specific environment (or picker if not specified)
prompt_objects                    # Interactive picker
prompt_objects --env work         # Direct open

# Environment info
prompt_objects env info work

# Export for sharing (git bundle)
prompt_objects env export work -o work.poenv

# Import from bundle
prompt_objects env import friend.poenv --as borrowed

# Archive (soft delete)
prompt_objects env archive old_project

# Restore from archive
prompt_objects env restore old_project

# Permanent delete
prompt_objects env delete old_project --permanent

# Clone environment
prompt_objects env clone work work_experimental
```

### TUI Commands

```
:env list                    # List environments
:env info                    # Current environment info
:env export work.poenv       # Export current
:stdlib list                 # List available stdlib objects
:stdlib add greeter          # Copy stdlib object to environment
```

## Concurrent Environments

Environments are designed to run simultaneously:

```bash
# Terminal 1: Work coding assistant
prompt_objects --env work

# Terminal 2: Personal PKM system
prompt_objects --env personal

# Terminal 3: Marketing content
prompt_objects --env marketing
```

Each instance is completely isolated - no shared state, no cross-communication.

## Custom Primitive Security

When importing environments with custom primitives:

### Sandbox Restrictions (Default)
Imported primitives run with:
- No filesystem access outside designated areas
- No network access
- No shell/exec capabilities

### Trust Model
```
╭─────────────────────────────────────────────────────────╮
│  ⚠️  This environment contains custom primitives        │
│                                                         │
│  primitives/web_scraper.rb                              │
│  primitives/file_processor.rb                           │
│                                                         │
│  Custom primitives are sandboxed by default.            │
│  [V]iew code  [T]rust all  [S]andboxed  [C]ancel       │
╰─────────────────────────────────────────────────────────╯
```

Trust can be granted:
- Per-primitive
- For entire environment
- Stored in user's global config (not in environment)

## Development Mode

For framework development:

```bash
# Use development environment (gitignored, isolated)
prompt_objects --dev

# Or with environment variable
PROMPT_OBJECTS_DEV=1 prompt_objects
```

The `--dev` flag:
- Uses `~/.prompt_objects/environments/_development/`
- This environment is gitignored in the framework repo
- Keeps development artifacts out of production

## Stdlib Integration

### Adding Stdlib Objects

```ruby
# In TUI or programmatically
env.add_stdlib_object("greeter")  # Copies from framework's objects/
env.add_stdlib_object("coordinator")
```

### Stdlib Primitives

Stdlib primitives (read_file, list_files, etc.) are always available to add to POs but not automatically included:

```yaml
# In a PO's frontmatter
capabilities:
  - read_file      # Stdlib primitive
  - list_files     # Stdlib primitive
  - my_tool        # Custom primitive from environment
  - code_reviewer  # Another PO in this environment
```

## Export/Import Format

Environments export as git bundles (`.poenv`):

```bash
# Export creates a git bundle
prompt_objects env export work -o work.poenv

# Bundle contains:
# - All commits (version history)
# - All objects and primitives
# - manifest.yml
# - Does NOT include sessions.db (private)
```

Import options:
```bash
# Import as new environment
prompt_objects env import work.poenv --as imported_work

# Merge into existing (advanced)
prompt_objects env import work.poenv --merge-into personal
```

## Migration Path

For existing users (us):

1. Create `~/.prompt_objects/environments/default/`
2. Move current working objects there
3. Initialize as git repo
4. Framework's `objects/` becomes stdlib examples
5. Add `templates/` directory to framework

## Implementation Phases

### Phase 8.1: Core Structure
- Environment class with git integration
- Manifest loading/saving
- Basic env create/list/open

### Phase 8.2: Templates
- Template directory structure
- First-run wizard
- Template selection and copying

### Phase 8.3: Sessions in SQLite
- Migrate from JSON files to SQLite
- Session CRUD operations
- Gitignore setup

### Phase 8.4: Export/Import
- Git bundle export
- Import with sandbox detection
- Trust management

### Phase 8.5: Archive & Metadata
- Soft delete to archive
- Rich metadata tracking
- Stats collection

### Phase 8.6: Dev Mode
- --dev flag implementation
- Development environment isolation

### Phase 8.7: Onboarding UI Polish (Non-Blocking)
Visual refinements for picker/wizard screens. Does not block feature development.

**Items to address:**
- [ ] Center alignment consistency across screens
- [ ] Box drawing alignment (visible length vs ANSI-escaped length)
- [ ] Consistent spacing/padding
- [ ] Template descriptions in picker
- [ ] Visual feedback during environment creation
- [ ] Error message styling
- [ ] Loading states/spinners
- [ ] Keyboard shortcut hints consistency

## File Changes

```
lib/prompt_objects/
├── environment.rb              # UPDATE: Major refactor
├── environment/
│   ├── manager.rb              # NEW: Multi-env management
│   ├── template.rb             # NEW: Template handling
│   ├── exporter.rb             # NEW: Bundle export
│   ├── importer.rb             # NEW: Bundle import
│   ├── sandbox.rb              # NEW: Primitive sandboxing
│   └── metadata.rb             # NEW: Rich metadata
├── session/
│   ├── store.rb                # NEW: SQLite session storage
│   └── migration.rb            # NEW: JSON to SQLite migration
└── ui/
    └── models/
        ├── setup_wizard.rb     # NEW: First-run wizard
        └── env_picker.rb       # NEW: Environment picker
```

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| Stdlib POs inherited or opt-in? | Opt-in (copy to use) |
| Environment storage format? | Git repository |
| Sessions in git? | No, SQLite + gitignore |
| Custom primitive security? | Full sandbox by default |
| Cross-environment communication? | Isolated, no cross-talk |
| Environment switching in TUI? | Run multiple concurrently instead |
| First-run experience? | Guided setup wizard |
| Deletion model? | Archive first (soft delete) |

## TUI Architecture Notes

### Single-Program Pattern (Critical)

**Bubble Tea best practice**: Use a single `Bubbletea.run` call with internal screen states, NOT multiple sequential programs.

Running multiple `tea.Program` instances sequentially (e.g., picker → wizard → main app) causes terminal state corruption. The recommended pattern is:

```ruby
class App
  SCREEN_PICKER = :picker
  SCREEN_WIZARD = :wizard
  SCREEN_MAIN = :main

  def init
    @screen = determine_initial_screen
    # Initialize appropriate sub-model
  end

  def update(msg)
    case @screen
    when SCREEN_PICKER
      # Route to picker, check if done, transition
    when SCREEN_WIZARD
      # Route to wizard, check if done, transition
    when SCREEN_MAIN
      # Handle main app logic
    end
  end

  def view
    case @screen
    when SCREEN_PICKER then @picker.view
    when SCREEN_WIZARD then @wizard.view
    when SCREEN_MAIN then view_main
    end
  end
end
```

**Key points:**
- The top-level model acts as a "message router and screen compositor"
- Child models (picker, wizard) handle their own state but report completion
- Screen transitions happen by changing `@screen` and initializing new sub-models
- All sub-models share the same window dimensions (broadcast `WindowSizeMessage`)

**References:**
- [GitHub Discussion #484: Transitioning between programs](https://github.com/charmbracelet/bubbletea/discussions/484)
- [Building Bubble Tea Programs](https://leg100.github.io/en/posts/building-bubbletea-programs/)

### Message Routing

For complex apps, route messages through three paths:
1. **Global**: Handle quit, help, window resize at top level
2. **Current screen**: Route user input to active sub-model
3. **Broadcast**: Pass structural messages to all sub-models

### Async Operations

Run expensive operations (LLM calls) in background threads:
```ruby
Thread.new do
  response = po.receive(text, context: context)
  Bubbletea.send_message(Messages::POResponse.new(...))
end
```

## Future Considerations

- Environment marketplace/registry for sharing
- Team environments with access control
- Environment versioning/rollback UI
- Primitive code signing for trust
- Environment health checks and repair
