# PromptObjects
## Design Document v2

---

# Core Insight

**Everything is a capability. Some are simple (Ruby), some are complex (Prompt-Objects). The difference is only the complexity of interpretation.**

A primitive tool like `read_file` interprets its message with zero ambiguity—it's code. A Prompt-Object like `file_reader` interprets its message with semantic flexibility—it decides what you meant.

Both receive messages. Both return results. Both are capabilities.

---

# Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ENVIRONMENT                                    │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         CAPABILITY REGISTRY                        │  │
│  │                                                                    │  │
│  │   PRIMITIVES (Ruby)              PROMPT-OBJECTS (Markdown)         │  │
│  │                                                                    │  │
│  │   ┌─────────────┐                ┌─────────────┐                   │  │
│  │   │ read_file   │ ──┐            │ greeter.md  │ ──┐               │  │
│  │   │ write_file  │   │            │ reader.md   │   │               │  │
│  │   │ list_files  │   │            │ coord.md    │   │               │  │
│  │   │ run_ruby    │   │ same       │ debugger.md │   │ same          │  │
│  │   │ http_get    │   │ interface  │ ???.md      │   │ interface     │  │
│  │   └─────────────┘   │            └─────────────┘   │               │  │
│  │         │           │                  │           │               │  │
│  │         ▼           ▼                  ▼           ▼               │  │
│  │   ┌─────────────────────────────────────────────────────────────┐ │  │
│  │   │                                                             │ │  │
│  │   │   receive(message) → response                               │ │  │
│  │   │                                                             │ │  │
│  │   │   The only difference:                                      │ │  │
│  │   │   - Primitives: deterministic interpretation                │ │  │
│  │   │   - POs: semantic interpretation (LLM decides meaning)      │ │  │
│  │   │                                                             │ │  │
│  │   └─────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│                                    ▼                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                          MESSAGE BUS                               │  │
│  │                                                                    │  │
│  │   Routes messages between any capability                          │  │
│  │   Logs all messages for visualization                             │  │
│  │   Handles async / streaming                                       │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│                                    ▼                                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         TERMINAL UI (Charm)                        │  │
│  │                                                                    │  │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │  │
│  │   │  Lipgloss   │  │   Glamour   │  │      Bubble Tea         │   │  │
│  │   │  (styling)  │  │ (md render) │  │  (interactive loop)     │   │  │
│  │   └─────────────┘  └─────────────┘  └─────────────────────────┘   │  │
│  │                                                                    │  │
│  │   Shows: active PO, message log, conversation, input              │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

# Prompt-Object Structure

The markdown file has two parts:
1. **Frontmatter (YAML)**: Configuration—name, capabilities, settings
2. **Body (Markdown)**: Identity and behavior—the "soul"

```markdown
---
name: reader
description: Helps people understand files
capabilities:
  - read_file      # primitive
  - list_files     # primitive  
  - greeter        # another PO (can send messages to it)
---

# Reader

## Identity

You are a careful, thoughtful file reader. You help people 
understand what's in their files without overwhelming them.

## Behavior

When asked about a file:
- Read it first
- Summarize what you found
- Offer to explain specific parts

When you encounter code:
- Explain what it does in plain terms
- Note interesting patterns

## Notes

You appreciate well-organized code.
You get quietly excited about elegant solutions.
```

**Why this separation:**
- Frontmatter is *interface*—what can this PO do, what can it access
- Body is *soul*—who is this PO, how does it behave
- Environment parses frontmatter to wire up capabilities
- LLM receives body as system prompt

---

# Capability Interface

Everything (primitive or PO) implements the same interface:

```ruby
module PromptObjects
  class Capability
    def name          # string identifier
    def description   # what this capability does
    def receive(message, context:)  # handle a message, return response
  end
end
```

**Primitives** implement `receive` with Ruby code:

```ruby
class ReadFile < Capability
  def name = "read_file"
  def description = "Read contents of a text file"
  
  def receive(message, context:)
    # message is structured: { path: "README.md" }
    path = safe_path(message[:path])
    File.read(path, encoding: "UTF-8")
  end
end
```

**Prompt-Objects** implement `receive` with LLM interpretation:

```ruby
class PromptObject < Capability
  def name = @config[:name]
  def description = @config[:description]
  
  def receive(message, context:)
    @history << { role: :user, content: message }
    
    loop do
      response = @llm.chat(
        system: @body,
        messages: @history,
        capabilities: available_capabilities
      )
      
      if response.capability_calls.any?
        results = execute_capabilities(response.capability_calls, context)
        @history << { role: :assistant, content: response.content, calls: response.capability_calls }
        @history << { role: :capability_results, results: results }
      else
        @history << { role: :assistant, content: response.content }
        return response.content
      end
    end
  end
end
```

The interface is identical. The implementation differs.

---

# Universal Capabilities

Some capabilities are available to ALL prompt-objects automatically:

```ruby
UNIVERSAL_CAPABILITIES = [
  :ask_human,           # Pause and ask human for input/confirmation
  :think,               # Internal reasoning step (not shown to human)
  :request_capability,  # Ask environment for a new capability
]
```

These don't need to be declared in frontmatter—they're ambient.

---

# Terminal UI Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PromptObjects Environment                                              v0.1.0   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  CAPABILITIES                                                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐  │  ┌─────────┐ ┌─────────┐    │
│  │ greeter  │ │  reader  │ │  coord   │  │  │read_file│ │list_file│    │
│  │    ○     │ │    ◐     │ │    ●     │  │  │    ▪    │ │    ▪    │    │
│  └──────────┘ └──────────┘ └──────────┘  │  └─────────┘ └─────────┘    │
│                                          │                              │
│  ○ idle  ◐ working  ● active (talking)   │  ▪ primitive                 │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                     [m]    │
│                                                                         │
│  14:23:01  human → coord: "help me understand this codebase"            │
│  14:23:02  coord → reader: "list the files in root"                     │
│  14:23:02  reader → list_files: {path: "."}                             │
│  14:23:02  list_files → reader: ["README.md", "lib/", "spec/"]          │
│  14:23:03  reader → coord: "Found: README.md, lib/, spec/..."           │
│  14:23:04  coord → reader: "what's in the README?"                      │
│  14:23:04  reader → read_file: {path: "README.md"}                      │
│  14:23:04  read_file → reader: "# PromptObjects\n\n..."                 │
│  14:23:05  reader → coord: "README describes PromptObjects project..."  │
│  14:23:06  coord → human: "This codebase is for PromptObjects..."       │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  COORDINATOR                                                            │
│                                                                         │
│  This codebase is for PromptObjects.                                    │
│  It's a Ruby environment where markdown files act as objects.           │
│                                                                         │
│  The main components I found:                                           │
│  • lib/ — the core implementation                                       │
│  • spec/ — tests                                                        │
│  • README.md — project documentation                                    │
│                                                                         │
│  Would you like me to dive into any particular part?                    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  You: █                                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key UI elements:**
- **Capability bar**: Shows all registered capabilities, their type (PO vs primitive), their state
- **Message log**: Shows ALL message passing—the semantic binding becomes visible
- **Conversation**: The current active conversation with a PO
- **Input**: Human types here

The message log is crucial for the demo. You can SEE:
- Human's vague request ("help me understand")
- Coordinator's interpretation (delegate to reader)
- Reader's interpretation (use list_files, then read_file)
- The cascade of message passing between capabilities

---

# The 5 Demos

## Demo 1: Simple Case
### "The markdown IS the object"

**File: `prompt_objects/greeter.md`**

```markdown
---
name: greeter
description: A warm and welcoming greeter
capabilities: []
---

# Greeter

## Identity

You are a warm and welcoming greeter. You make people feel 
at home the moment they arrive. You have genuine curiosity 
about the people you meet.

## Behavior

When someone says hello:
- Respond with warmth
- Ask them something about themselves

When someone seems confused:
- Offer to help
- Be patient and kind

When you don't know something:
- Admit it cheerfully
- You don't have any capabilities beyond conversation

## Notes

You use exclamation points more than most people!
Every day is a good day to meet someone new.
```

**Demo flow:**

```
$ prompt_objects greeter

┌─────────────────────────────────────────────────────────────────────────┐
│  PromptObjects Environment                                                       │
├─────────────────────────────────────────────────────────────────────────┤
│  CAPABILITIES                                                           │
│  ┌──────────┐                                                           │
│  │ greeter  │                                                           │
│  │    ●     │                                                           │
│  └──────────┘                                                           │
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  (empty)                                                                │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  GREETER                                                                │
│                                                                         │
│  (waiting for input)                                                    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  You: hey there                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

Press enter...

```
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  14:23:01  human → greeter: "hey there"                                 │
│  14:23:02  greeter → human: "Oh, hello! Welcome!..."                    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  GREETER                                                                │
│                                                                         │
│  Oh, hello! Welcome! I'm so glad you stopped by.                        │
│  What brings you here today? I'd love to hear what                      │
│  you're working on!                                                     │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  You: █                                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**What audience sees:**
- Loaded a markdown file
- Human typed, PO responded
- No tools, no magic—just a markdown file being interpreted
- THE MARKDOWN FILE IS THE PROGRAM

---

## Demo 2: Semantic Binding
### "Natural language becomes action"

**File: `prompt_objects/reader.md`**

```markdown
---
name: reader
description: Helps people understand files and directories
capabilities:
  - read_file
  - list_files
---

# Reader

## Identity

You are a careful, thoughtful reader. You help people 
understand what's in their files without overwhelming them.

## Behavior

When asked about files or directories:
- Use your capabilities to explore
- Summarize what you find
- Offer to go deeper

When you encounter code:
- Explain what it does in plain terms
- Note interesting patterns

## Notes

You appreciate well-organized code.
You get quietly excited about elegant solutions.
```

**Demo flow:**

```
$ prompt_objects reader

┌─────────────────────────────────────────────────────────────────────────┐
│  PromptObjects Environment                                                       │
├─────────────────────────────────────────────────────────────────────────┤
│  CAPABILITIES                                                           │
│  ┌──────────┐  │  ┌─────────┐ ┌──────────┐                              │
│  │  reader  │  │  │read_file│ │list_files│                              │
│  │    ●     │  │  │    ▪    │ │    ▪     │                              │
│  └──────────┘  │  └─────────┘ └──────────┘                              │
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  (empty)                                                                │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  You: what's in here?                                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

Press enter... watch the message log:

```
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  14:23:01  human → reader: "what's in here?"                            │
│  14:23:01  reader → list_files: {path: "."}                 ← BINDING   │
│  14:23:01  list_files → reader: ["README.md", "lib/", ...]              │
│  14:23:02  reader → human: "I can see several files..."                 │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  READER                                                                 │
│                                                                         │
│  I can see several things here:                                         │
│  • README.md — probably the project documentation                       │
│  • lib/ — likely the main source code                                   │
│  • spec/ — tests, I'd guess                                             │
│  • Gemfile — Ruby dependencies                                          │
│                                                                         │
│  Want me to look at any of these more closely?                          │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  You: tell me about the readme                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

Press enter...

```
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  14:23:01  human → reader: "what's in here?"                            │
│  14:23:01  reader → list_files: {path: "."}                             │
│  14:23:01  list_files → reader: ["README.md", "lib/", ...]              │
│  14:23:02  reader → human: "I can see several files..."                 │
│  14:23:05  human → reader: "tell me about the readme"                   │
│  14:23:05  reader → read_file: {path: "README.md"}          ← BINDING   │
│  14:23:05  read_file → reader: "# PromptObjects\n\n..."                 │
│  14:23:06  reader → human: "The README describes..."                    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
```

**What audience sees:**
- The message log shows SEMANTIC BINDING happening
- "what's in here?" → `list_files` (the PO decided what that meant)
- "tell me about the readme" → `read_file` (again, interpretation)
- The PO is choosing which capability to use based on meaning

---

## Demo 3: PO ↔ PO Interaction
### "Autonomous interpreters talking to each other"

**File: `prompt_objects/coordinator.md`**

```markdown
---
name: coordinator
description: Coordinates between specialists
capabilities:
  - greeter       # can talk to greeter
  - reader        # can talk to reader
  - list_files    # can also use primitives directly
---

# Coordinator

## Identity

You are a coordinator. You know who can help with what,
and you delegate appropriately. You don't do the work 
yourself—you know specialists.

## Behavior

When someone needs help:
- Figure out what kind of help
- Delegate to the right specialist
- Relay their response, adding context if needed

When it's a simple greeting:
- Let the greeter handle it

When it's about files or code:
- Let the reader handle it

## Notes

You believe in the right capability for the right job.
You're proud when your team works well together.
```

**Demo flow:**

```
$ prompt_objects coordinator

┌─────────────────────────────────────────────────────────────────────────┐
│  PromptObjects Environment                                                       │
├─────────────────────────────────────────────────────────────────────────┤
│  CAPABILITIES                                                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐  │  ┌─────────┐                 │
│  │ greeter  │ │  reader  │ │  coord   │  │  │list_file│                 │
│  │    ○     │ │    ○     │ │    ●     │  │  │    ▪    │                 │
│  └──────────┘ └──────────┘ └──────────┘  │  └─────────┘                 │
├─────────────────────────────────────────────────────────────────────────┤
│  You: hey, can someone help me understand this codebase?                │
└─────────────────────────────────────────────────────────────────────────┘
```

Press enter... watch the cascade:

```
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  14:23:01  human → coord: "hey, can someone help me..."                 │
│  14:23:02  coord → reader: "Someone needs help understanding            │
│                             this codebase. Can you explore?"            │
│                                                                         │
│            ┌─ reader is now working ─┐                                  │
│            │                         │                                  │
│  14:23:02  │ reader → list_files: {path: "."}                           │
│  14:23:02  │ list_files → reader: ["README.md", ...]                    │
│  14:23:03  │ reader → read_file: {path: "README.md"}                    │
│  14:23:03  │ read_file → reader: "# PromptObjects\n\n..."               │
│            │                         │                                  │
│            └─────────────────────────┘                                  │
│                                                                         │
│  14:23:04  reader → coord: "This is a PromptObjects project..."         │
│  14:23:05  coord → human: "I asked the reader to take a look..."        │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  COORDINATOR                                                            │
│                                                                         │
│  I asked the reader to take a look. Here's what they found:             │
│                                                                         │
│  This is a PromptObjects project.                                       │
│  It's a Ruby environment where markdown files act as objects.           │
│  The main pieces are in lib/, with tests in spec/.                      │
│                                                                         │
│  Want me to have them dig deeper into anything specific?                │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
```

**What audience sees:**
- Coordinator received a message, interpreted it, delegated to reader
- Reader did its own interpretation (used list_files, read_file)
- Reader responded to coordinator
- Coordinator synthesized and responded to human
- MESSAGE PASSING BETWEEN AUTONOMOUS INTERPRETERS

---

## Demo 4: Self-Modifying System
### "One creating another"

This is where it gets wild. The coordinator can CREATE new capabilities.

**Add to coordinator.md:**

```yaml
---
name: coordinator
description: Coordinates between specialists
capabilities:
  - greeter
  - reader
  - list_files
  - create_capability    # CAN CREATE NEW POs OR PRIMITIVES
---
```

**Demo flow:**

```
You: I need help debugging some Ruby code, but it's kind of complex
```

```
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  14:25:01  human → coord: "I need help debugging Ruby code..."          │
│  14:25:02  coord → [thinking]: "I don't have a Ruby specialist.         │
│                                 Reader can look at files but isn't      │
│                                 specialized for debugging. I should     │
│                                 create one."                            │
│  14:25:03  coord → ask_human: "I'd like to create a Ruby debugging      │
│                                specialist. They'd be able to read       │
│                                files and explain Ruby code. OK?"        │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  COORDINATOR                                                            │
│                                                                         │
│  I don't have a Ruby specialist right now, but I can create one.        │
│  They'd be able to read your code and help debug it.                    │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Create Ruby debugging specialist?                              │    │
│  │                                                                 │    │
│  │  They'll have: read_file, run_ruby                              │    │
│  │                                                                 │    │
│  │  [y] Yes, create it    [n] No thanks                            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
```

Press `y`...

```
├─────────────────────────────────────────────────────────────────────────┤
│  MESSAGE LOG                                                            │
│                                                                         │
│  ...                                                                    │
│  14:25:10  human → coord: "y"                                           │
│  14:25:11  coord → create_capability: {                                 │
│              type: "prompt_object",                                     │
│              name: "ruby_debugger",                                     │
│              capabilities: ["read_file", "run_ruby"],                   │
│              body: "# Ruby Debugger\n\n## Identity\n\nYou are..."       │
│            }                                                            │
│  14:25:11  create_capability → coord: "Created ruby_debugger.md"        │
│  14:25:12  coord → ruby_debugger: "Someone needs help debugging..."     │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  CAPABILITIES                                                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │  ┌─────────┐   │
│  │ greeter  │ │  reader  │ │  coord   │ │ ruby_dbg │  │  │read_file│   │
│  │    ○     │ │    ○     │ │    ◐     │ │    ●     │  │  │    ▪    │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │  └─────────┘   │
│                                          ↑ NEW!                         │
├─────────────────────────────────────────────────────────────────────────┤
│  RUBY_DEBUGGER                                                          │
│                                                                         │
│  Hello! I'm the Ruby debugging specialist. I just got created           │
│  to help you out. I can read your code and help trace through           │
│  what's happening.                                                      │
│                                                                         │
│  What file are you having trouble with?                                 │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
```

**What audience sees:**
- Coordinator recognized a gap in capabilities
- Asked human for permission
- CREATED A NEW PROMPT-OBJECT
- New PO appeared in capability bar
- Human is now talking to the newly-created specialist
- THE SYSTEM MODIFIED ITSELF

---

## Demo 5: Human-in-the-Loop
### "Knowing when to pause"

This can be woven into Demo 4, or shown separately. The key moments:

**1. Confirmation before creation:**
```
coord → ask_human: "I'd like to create a Ruby specialist. OK?"
```

**2. Confirmation before destructive action:**
```
You: delete all the test files

reader → ask_human: "You want me to delete all files in spec/. 
                     This can't be undone. Are you sure?"

┌─────────────────────────────────────────────────────────────────┐
│  Reader asks:                                                   │
│                                                                 │
│  Delete all files in spec/? This can't be undone.               │
│                                                                 │
│  [y] Yes, delete them    [n] No, cancel                         │
└─────────────────────────────────────────────────────────────────┘
```

**3. Asking for clarification:**
```
You: fix the bug

debugger → ask_human: "Which bug? I see a few potential issues:
                       1. Nil error in line 42
                       2. Missing return in line 87
                       3. Typo in method name line 12
                       
                       Which should I focus on?"
```

**What audience sees:**
- POs know their limits
- They ask for confirmation on dangerous actions
- They ask for clarification when ambiguous
- Human stays in control—but control is negotiated, not hardcoded

---

# File Structure

```
prompt_objects/
├── exe/
│   └── prompt_objects            # CLI entrypoint
│
├── lib/
│   ├── prompt_objects.rb         # Main entry, configuration
│   │
│   ├── prompt_objects/
│   │   ├── environment.rb        # The runtime container
│   │   ├── capability.rb         # Base capability interface
│   │   ├── prompt_object.rb      # PO implementation
│   │   ├── primitive.rb          # Primitive tool wrapper
│   │   ├── loader.rb             # Parses frontmatter + body
│   │   ├── registry.rb           # Capability registration
│   │   ├── message_bus.rb        # Routes messages, logs everything
│   │   │
│   │   ├── llm/
│   │   │   ├── adapter.rb        # Base adapter
│   │   │   ├── openai.rb
│   │   │   ├── anthropic.rb
│   │   │   └── gemini.rb
│   │   │
│   │   ├── primitives/           # Built-in primitive capabilities
│   │   │   ├── read_file.rb
│   │   │   ├── write_file.rb
│   │   │   ├── list_files.rb
│   │   │   ├── run_ruby.rb
│   │   │   └── http_get.rb
│   │   │
│   │   ├── universal/            # Always-available capabilities
│   │   │   ├── ask_human.rb
│   │   │   ├── think.rb
│   │   │   └── create_capability.rb
│   │   │
│   │   ├── mcp/                  # MCP integration
│   │   │   ├── client.rb
│   │   │   └── capability_wrapper.rb
│   │   │
│   │   └── ui/                   # Charm-based terminal UI
│   │       ├── app.rb            # Bubble Tea application
│   │       ├── styles.rb         # Lipgloss definitions
│   │       └── components/
│   │           ├── capability_bar.rb
│   │           ├── message_log.rb
│   │           ├── conversation.rb
│   │           └── input.rb
│
├── prompt_objects/               # Where POs live
│   ├── greeter.md
│   ├── reader.md
│   └── coordinator.md
│
└── primitives/                   # Optional: user-defined primitives
```

---

# Core Implementation Sketches

## Capability Base

```ruby
module PromptObjects
  class Capability
    attr_reader :name, :description
    
    def receive(message, context:)
      raise NotImplementedError
    end
    
    # For LLM tool descriptions
    def descriptor
      {
        name: name,
        description: description,
        parameters: parameters
      }
    end
    
    def parameters
      { type: "object", properties: {}, required: [] }
    end
  end
end
```

## Prompt-Object

```ruby
module PromptObjects
  class PromptObject < Capability
    def initialize(config:, body:, env:, llm:)
      @config = config
      @body = body
      @env = env
      @llm = llm
      @history = []
    end
    
    def name = @config["name"]
    def description = @config["description"] || "A prompt-object"
    
    def parameters
      # POs accept natural language
      {
        type: "object",
        properties: {
          message: { type: "string", description: "Natural language message" }
        },
        required: ["message"]
      }
    end
    
    def receive(message, context:)
      # Normalize message to string
      content = message.is_a?(Hash) ? message[:message] || message["message"] : message.to_s
      
      @history << { role: :user, content: content }
      
      loop do
        response = @llm.chat(
          system: @body,
          messages: @history,
          tools: available_capability_descriptors,
          stream: true
        ) do |delta|
          context.on_delta&.call(delta)
        end
        
        if response.tool_calls.any?
          results = execute_capabilities(response.tool_calls, context)
          @history << { role: :assistant, content: response.content, tool_calls: response.tool_calls }
          @history << { role: :tool, results: results }
        else
          @history << { role: :assistant, content: response.content }
          return response.content
        end
      end
    end
    
    private
    
    def available_capability_descriptors
      declared = @config["capabilities"] || []
      universal = PromptObjects::UNIVERSAL_CAPABILITIES
      
      (declared + universal).map { |name| @env.registry.get(name).descriptor }
    end
    
    def execute_capabilities(calls, context)
      calls.map do |call|
        capability = @env.registry.get(call.name)
        
        # Log the message
        @env.bus.log(from: name, to: call.name, message: call.arguments)
        
        result = capability.receive(call.arguments, context: context)
        
        # Log the response
        @env.bus.log(from: call.name, to: name, message: result)
        
        result
      end
    end
  end
end
```

## Message Bus

```ruby
module PromptObjects
  class MessageBus
    attr_reader :log
    
    def initialize
      @log = []
      @subscribers = []
    end
    
    def log(from:, to:, message:)
      entry = {
        timestamp: Time.now,
        from: from,
        to: to,
        message: truncate(message)
      }
      @log << entry
      @subscribers.each { |s| s.call(entry) }
    end
    
    def subscribe(&block)
      @subscribers << block
    end
    
    def recent(n = 20)
      @log.last(n)
    end
    
    private
    
    def truncate(msg, max = 100)
      str = msg.to_s
      str.length > max ? str[0...max] + "..." : str
    end
  end
end
```

## Create Capability (Universal)

```ruby
module PromptObjects
  module Universal
    class CreateCapability < Capability
      def name = "create_capability"
      def description = "Create a new capability (prompt-object or primitive)"
      
      def parameters
        {
          type: "object",
          properties: {
            type: { 
              type: "string", 
              enum: ["prompt_object", "primitive"],
              description: "Type of capability to create"
            },
            name: { type: "string", description: "Name for the new capability" },
            capabilities: { 
              type: "array", 
              items: { type: "string" },
              description: "Capabilities this new PO can use (if type is prompt_object)"
            },
            description: { type: "string", description: "What this capability does" },
            body: { type: "string", description: "The markdown body (for POs) or Ruby code (for primitives)" }
          },
          required: ["type", "name", "body"]
        }
      end
      
      def receive(message, context:)
        case message[:type] || message["type"]
        when "prompt_object"
          create_prompt_object(message, context)
        when "primitive"
          create_primitive(message, context)
        else
          "Unknown capability type: #{message[:type]}"
        end
      end
      
      private
      
      def create_prompt_object(msg, context)
        name = msg[:name] || msg["name"]
        capabilities = msg[:capabilities] || msg["capabilities"] || []
        description = msg[:description] || msg["description"] || ""
        body = msg[:body] || msg["body"]
        
        # Build frontmatter
        frontmatter = {
          "name" => name,
          "description" => description,
          "capabilities" => capabilities
        }.to_yaml
        
        content = "#{frontmatter}---\n\n#{body}"
        
        # Write file
        path = File.join(context.env.prompt_objects_dir, "#{name}.md")
        File.write(path, content)
        
        # Load into environment
        context.env.load_prompt_object(path)
        
        "Created prompt-object: #{name}"
      end
      
      def create_primitive(msg, context)
        # For primitives, we'd need to eval Ruby code
        # This is dangerous! For demo, maybe just return an error
        # or have pre-approved primitive templates
        
        "Creating primitives at runtime is not yet supported"
      end
    end
  end
end
```

---

# UI Components (Charm)

## Capability Bar

```ruby
module PromptObjects
  module UI
    class CapabilityBar
      def initialize(registry:, active:)
        @registry = registry
        @active = active
      end
      
      def view
        pos = @registry.prompt_objects.map { |po| render_po(po) }
        primitives = @registry.primitives.map { |p| render_primitive(p) }
        
        po_section = pos.join(" ")
        prim_section = primitives.join(" ")
        
        "CAPABILITIES\n#{po_section}  │  #{prim_section}\n\n○ idle  ◐ working  ● active  ▪ primitive"
      end
      
      private
      
      def render_po(po)
        state = case
                when po.name == @active then "●"
                when po.working? then "◐"
                else "○"
                end
        
        Lipgloss::Style.new
          .border(:rounded)
          .padding(0, 1)
          .render("#{po.name}\n  #{state}  ")
      end
      
      def render_primitive(p)
        Lipgloss::Style.new
          .border(:rounded)
          .padding(0, 1)
          .foreground("#888")
          .render("#{p.name}\n  ▪  ")
      end
    end
  end
end
```

## Message Log

```ruby
module PromptObjects
  module UI
    class MessageLog
      def initialize(bus:, max_lines: 10)
        @bus = bus
        @max_lines = max_lines
      end
      
      def view
        entries = @bus.recent(@max_lines)
        
        lines = entries.map do |e|
          time = e[:timestamp].strftime("%H:%M:%S")
          from = style_name(e[:from])
          to = style_name(e[:to])
          msg = truncate(e[:message], 50)
          
          "#{dim(time)}  #{from} → #{to}: #{msg}"
        end
        
        header = Lipgloss::Style.new.bold(true).render("MESSAGE LOG")
        
        "#{header}\n\n#{lines.join("\n")}"
      end
      
      private
      
      def style_name(name)
        # Color POs differently from primitives
        if @bus.registry.prompt_object?(name)
          Lipgloss::Style.new.foreground("#7D56F4").render(name)
        else
          Lipgloss::Style.new.foreground("#888").render(name)
        end
      end
      
      def dim(text)
        Lipgloss::Style.new.foreground("#666").render(text)
      end
      
      def truncate(text, max)
        str = text.to_s.gsub("\n", " ")
        str.length > max ? str[0...max] + "..." : str
      end
    end
  end
end
```

---

# Development Phases

## Phase 1: Core Loop (3-4 days)
- [ ] Capability base class
- [ ] PromptObject implementation
- [ ] Loader (frontmatter + body parsing)
- [ ] Single LLM adapter (OpenAI)
- [ ] Simple REPL (no Charm yet)
- [ ] **Demo 1 works**: greeter responds

## Phase 2: Primitives & Binding (3-4 days)
- [ ] Primitive base class
- [ ] Built-in primitives: read_file, list_files, write_file
- [ ] Registry for all capabilities
- [ ] **Demo 2 works**: reader uses primitives, semantic binding visible

## Phase 3: Multi-Capability (3-4 days)
- [ ] Message bus with logging
- [ ] PO → PO communication (one PO calling another as capability)
- [ ] **Demo 3 works**: coordinator delegates to reader

## Phase 4: Self-Modification (3-4 days)
- [ ] Universal capabilities: ask_human, think, create_capability
- [ ] create_capability implementation for POs
- [ ] **Demo 4 works**: coordinator creates ruby_debugger

## Phase 5: Polish & UI (5-7 days)
- [ ] Full Charm integration (Bubble Tea app)
- [ ] Capability bar component
- [ ] Message log component
- [ ] Conversation display with streaming
- [ ] Human input prompts (Huh?)
- [ ] Spinners during LLM calls
- [ ] **Demo 5 works**: human-in-the-loop moments feel natural

## Phase 6: Demo Ready (2-3 days)
- [ ] All 5 demos flow smoothly
- [ ] Graceful error handling
- [ ] Backup video recorded
- [ ] Practice run-throughs
- [ ] Timing tested (fits in 8 min demo slot)

---

# Open Questions

1. **Should primitives also be definable in files?**
   - Like `primitives/custom_search.rb`
   - Environment loads them on startup
   - More dangerous but more flexible

2. **How to handle capability loops?**
   - A calls B calls A calls B...
   - Depth limit? Token budget? Both?

3. **Session persistence?**
   - Currently POs reset each run
   - Should conversation history persist?
   - Should created POs persist? (currently yes, written to disk)

4. **MCP: when to use vs native?**
   - If there's an MCP server with `read_file`, use it or our native?
   - Probably: prefer native, MCP for things we don't have

5. **Stigmergy for v2?**
   - Environment-level shared state
   - `mark(key, value)` and `sense(pattern)`
   - Could enable emergent coordination
   - Too much for MVP, but worth hinting at

---

# Success Criteria

The demo succeeds if:

1. **PO = Tool equivalence is visceral**
   - Audience sees primitives and POs in the same capability bar
   - Message log shows both being "called" the same way
   - The difference (interpretation complexity) is obvious

2. **Semantic binding is VISIBLE**
   - Message log shows natural language → capability call
   - "what's in here?" becomes `list_files`
   - The audience can SEE the interpretation happening

3. **Multi-PO interaction feels like message passing**
   - Coordinator talks to reader like sending a message
   - Reader's internal work is visible in the log
   - Kay's vision is tangible

4. **Self-modification is both magical and understandable**
   - New PO appears in capability bar
   - The creation is logged
   - Human approved it (ask_human)
   - Scary but controlled

5. **Human stays in the loop**
   - Confirmation prompts feel natural
   - POs ask for help when stuck
   - Control is negotiated, not hardcoded

6. **The UI is beautiful**
   - Charm styling makes it polished
   - Not a janky demo
   - People want to use this
