Prompt Objects
==============

LLM-backed entities as first-class autonomous objects.

Why
===

Alan Kay's vision: "The key in making great and growable systems is much more to design how its modules communicate rather than what their internal properties and behaviors should be."

Prompt Objects applies this to AI. Instead of treating LLMs as external APIs you call, what if they were objects that **communicate** with each other? Markdown files become autonomous entities. They have identity, capabilities, and memory. They delegate to each other naturally.

This is a new computing primitive: semantic late binding at runtime, where natural language becomes the interface between intelligent components.

Who
===

- **Ruby developers** exploring AI-native architectures
- **AI tinkerers** who want to build systems that grow and adapt
- **Anyone** frustrated with brittle prompt chains and rigid agent frameworks

What
====

A Ruby framework where:

- **Markdown files** define autonomous entities (Prompt Objects)
- **YAML frontmatter** declares capabilities and configuration
- **Markdown body** becomes identity and behavior (the system prompt)
- **Capabilities** are shared between primitives (Ruby) and Prompt Objects (markdown)
- **Environments** isolate collections of objects with their own memory

How
===

### Installation

```bash
gem install prompt_objects
```

### Quick Start

```bash
# Create an environment from a template
prompt_objects env create my-project --template basic

# Run and open the web interface
prompt_objects serve my-project --open
```

### Environment Commands

```bash
prompt_objects env list              # List all environments
prompt_objects env create <name>     # Create new environment
prompt_objects env info <name>       # Show environment details
prompt_objects env clone <src> <dst> # Clone an environment
```

### Templates

- `basic` - No capabilities, learns as needed (great for demos)
- `minimal` - Basic assistant with file reading
- `developer` - Code review, debugging, testing specialists
- `writer` - Editor, researcher for content creation

Extras
======

- **License**: MIT
- **Ruby**: >= 3.2.0
- **Repository**: https://github.com/works-on-your-machine/prompt_objects
