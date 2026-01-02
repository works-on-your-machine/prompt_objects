# PromptObjects Implementation Plan

Detailed phased implementation plan for the PromptObjects MVP.

---

## Phase 1: Core Loop

**Goal**: Get a single Prompt-Object (greeter) responding to human input via LLM.

### 1.1 Project Setup

- [ ] Initialize Ruby project structure
  ```
  prompt_objects/
  ├── Gemfile
  ├── lib/
  │   ├── prompt_objects.rb
  │   └── prompt_objects/
  └── exe/
      └── prompt_objects
  ```
- [ ] Gemfile dependencies:
  - `ruby-openai` (or `anthropic` SDK)
  - `front_matter_parser` (YAML frontmatter parsing)
  - Standard library: `optparse`, `readline`

### 1.2 Capability Base Class

**File**: `lib/prompt_objects/capability.rb`

```ruby
module PromptObjects
  class Capability
    attr_reader :name, :description

    def receive(message, context:)
      raise NotImplementedError
    end

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

### 1.3 Loader

**File**: `lib/prompt_objects/loader.rb`

- [ ] Parse markdown file with YAML frontmatter
- [ ] Extract config (name, description, capabilities list)
- [ ] Extract body (everything after frontmatter)
- [ ] Return structured data for PromptObject initialization

```ruby
module PromptObjects
  class Loader
    def self.load(path)
      content = File.read(path)
      parsed = FrontMatterParser::Parser.new(:md).call(content)

      {
        config: parsed.front_matter,
        body: parsed.content,
        path: path
      }
    end
  end
end
```

### 1.4 LLM Adapter (OpenAI)

**File**: `lib/prompt_objects/llm/openai_adapter.rb`

- [ ] Initialize with API key (from ENV)
- [ ] `chat(system:, messages:, tools:)` method
- [ ] Handle tool_calls in response
- [ ] Return structured response object with `content` and `tool_calls`

```ruby
module PromptObjects
  module LLM
    class OpenAIAdapter
      def initialize(api_key: ENV["OPENAI_API_KEY"], model: "gpt-4")
        @client = OpenAI::Client.new(access_token: api_key)
        @model = model
      end

      def chat(system:, messages:, tools: [])
        response = @client.chat(
          parameters: {
            model: @model,
            messages: format_messages(system, messages),
            tools: format_tools(tools)
          }
        )

        Response.new(response)
      end
    end

    class Response
      attr_reader :content, :tool_calls
      # Parse OpenAI response format
    end
  end
end
```

### 1.5 PromptObject Class

**File**: `lib/prompt_objects/prompt_object.rb`

- [ ] Initialize with config, body, environment reference, LLM adapter
- [ ] Implement `receive(message, context:)`:
  1. Add message to history
  2. Call LLM with system prompt (body) + history
  3. If tool_calls: execute and loop
  4. If no tool_calls: return content
- [ ] Track conversation history

### 1.6 Simple REPL

**File**: `exe/prompt_objects`

- [ ] Parse command line args (prompt object name)
- [ ] Load the specified .md file from `objects/` directory
- [ ] Create PromptObject instance
- [ ] Loop: read input → call receive → print response

```ruby
#!/usr/bin/env ruby
require "prompt_objects"

name = ARGV[0] || "greeter"
path = File.join("objects", "#{name}.md")

env = PromptObjects::Environment.new
po = env.load_prompt_object(path)

loop do
  print "You: "
  input = gets&.chomp
  break if input.nil? || input == "exit"

  response = po.receive(input, context: env.context)
  puts "\n#{po.name}: #{response}\n\n"
end
```

### 1.7 Test Prompt Object

**File**: `objects/greeter.md`

Create the greeter from the design doc to test with.

### Phase 1 Deliverable

- Run `./exe/prompt_objects greeter`
- Type "hello"
- Get a response from the greeter personality
- **Demo 1 achievable**

---

## Phase 2: Primitives & Binding

**Goal**: Add primitive capabilities that PromptObjects can call. Reader uses `read_file` and `list_files`.

### 2.1 Primitive Base Class

**File**: `lib/prompt_objects/primitive.rb`

```ruby
module PromptObjects
  class Primitive < Capability
    # Primitives are Capabilities with deterministic Ruby implementations
    # They define parameters more strictly than POs
  end
end
```

### 2.2 Built-in Primitives

**Directory**: `lib/prompt_objects/primitives/`

#### read_file.rb
- [ ] Parameters: `{ path: string }`
- [ ] Validate path (prevent directory traversal)
- [ ] Read and return file contents
- [ ] Handle errors gracefully

#### list_files.rb
- [ ] Parameters: `{ path: string }` (defaults to ".")
- [ ] Return array of filenames/directories
- [ ] Optional: include file types/sizes

#### write_file.rb
- [ ] Parameters: `{ path: string, content: string }`
- [ ] Validate path
- [ ] Write content to file
- [ ] Return confirmation

### 2.3 Registry

**File**: `lib/prompt_objects/registry.rb`

- [ ] Store capabilities by name
- [ ] `register(capability)` - add to registry
- [ ] `get(name)` - retrieve by name
- [ ] `all` - list all capabilities
- [ ] `prompt_objects` - filter to just POs
- [ ] `primitives` - filter to just primitives
- [ ] Generate tool descriptors for LLM

```ruby
module PromptObjects
  class Registry
    def initialize
      @capabilities = {}
    end

    def register(capability)
      @capabilities[capability.name] = capability
    end

    def get(name)
      @capabilities[name] or raise "Unknown capability: #{name}"
    end

    def descriptors_for(names)
      names.map { |n| get(n).descriptor }
    end
  end
end
```

### 2.4 Environment Updates

**File**: `lib/prompt_objects/environment.rb`

- [ ] Hold registry instance
- [ ] Auto-register built-in primitives on init
- [ ] Load prompt objects from `objects/` directory
- [ ] Provide context object for capability execution

```ruby
module PromptObjects
  class Environment
    attr_reader :registry, :llm

    def initialize
      @registry = Registry.new
      @llm = LLM::OpenAIAdapter.new
      register_primitives
    end

    def register_primitives
      registry.register(Primitives::ReadFile.new)
      registry.register(Primitives::ListFiles.new)
      registry.register(Primitives::WriteFile.new)
    end

    def load_prompt_object(path)
      data = Loader.load(path)
      po = PromptObject.new(
        config: data[:config],
        body: data[:body],
        env: self,
        llm: @llm
      )
      registry.register(po)
      po
    end
  end
end
```

### 2.5 PromptObject Updates

- [ ] Look up declared capabilities from registry
- [ ] Pass capability descriptors to LLM as tools
- [ ] Execute capability calls through registry
- [ ] Handle capability results in conversation loop

### 2.6 Test Prompt Object

**File**: `objects/reader.md`

Create the reader from the design doc with `read_file` and `list_files` capabilities.

### Phase 2 Deliverable

- Run `./exe/prompt_objects reader`
- Ask "what's in here?"
- Reader calls `list_files`, interprets results, responds
- Ask "tell me about the README"
- Reader calls `read_file`, summarizes content
- **Demo 2 achievable** - semantic binding visible in output

---

## Phase 3: Multi-Capability

**Goal**: Prompt-Objects can call other Prompt-Objects. Coordinator delegates to reader.

### 3.1 Message Bus

**File**: `lib/prompt_objects/message_bus.rb`

- [ ] Log all messages: `{ timestamp, from, to, message }`
- [ ] Subscribe mechanism for UI updates
- [ ] `recent(n)` to get last n messages
- [ ] Truncate long messages for display

```ruby
module PromptObjects
  class MessageBus
    attr_reader :log

    def initialize
      @log = []
      @subscribers = []
    end

    def publish(from:, to:, message:)
      entry = {
        timestamp: Time.now,
        from: from,
        to: to,
        message: message
      }
      @log << entry
      @subscribers.each { |s| s.call(entry) }
      entry
    end

    def subscribe(&block)
      @subscribers << block
    end

    def recent(n = 20)
      @log.last(n)
    end
  end
end
```

### 3.2 Context Object

**File**: `lib/prompt_objects/context.rb`

- [ ] Hold reference to environment
- [ ] Hold reference to message bus
- [ ] Track current execution chain (for loop detection)
- [ ] Provide callbacks for streaming/deltas

```ruby
module PromptObjects
  class Context
    attr_reader :env, :bus
    attr_accessor :on_delta

    def initialize(env:, bus:)
      @env = env
      @bus = bus
      @call_stack = []
    end

    def push(capability_name)
      if @call_stack.include?(capability_name)
        raise "Capability loop detected: #{@call_stack.join(' → ')} → #{capability_name}"
      end
      @call_stack.push(capability_name)
    end

    def pop
      @call_stack.pop
    end
  end
end
```

### 3.3 PO → PO Communication

Update PromptObject to:
- [ ] When calling a capability, check if it's a PO or primitive
- [ ] Log message to bus before calling
- [ ] Log response to bus after receiving
- [ ] POs receive natural language messages from other POs

### 3.4 REPL Updates

- [ ] Print message bus entries as they happen
- [ ] Show the cascade of messages
- [ ] Format: `HH:MM:SS  from → to: "message..."`

### 3.5 Test Prompt Object

**File**: `objects/coordinator.md`

Create coordinator with capabilities: `greeter`, `reader`, `list_files`

### Phase 3 Deliverable

- Run `./exe/prompt_objects coordinator`
- Ask "help me understand this codebase"
- See coordinator delegate to reader
- See reader use primitives
- See message cascade in output
- **Demo 3 achievable**

---

## Phase 4: Self-Modification & Human Interaction Queue

**Goal**: System can create new Prompt-Objects at runtime. Human interactions are non-blocking with a notification queue.

### 4.1 Universal Capabilities

**Directory**: `lib/prompt_objects/universal/`

These are automatically available to ALL prompt objects.

#### ask_human.rb
- [ ] Parameters: `{ question: string, options: array (optional) }`
- [ ] **Non-blocking**: Suspends PO execution, queues notification
- [ ] Returns when human eventually responds
- [ ] Use **Huh** gem for rendering the prompt when human engages

```ruby
module PromptObjects
  module Universal
    class AskHuman < Capability
      def name = "ask_human"
      def description = "Pause and ask the human a question"

      def parameters
        {
          type: "object",
          properties: {
            question: { type: "string", description: "Question to ask" },
            options: {
              type: "array",
              items: { type: "string" },
              description: "Optional choices to present"
            }
          },
          required: ["question"]
        }
      end

      def receive(message, context:)
        question = message[:question] || message["question"]
        options = message[:options] || message["options"]

        # Create a pending request and suspend until human responds
        request = HumanRequest.new(
          capability: context.current_capability,
          type: :ask_human,
          question: question,
          options: options
        )

        # Queue the request - this suspends the PO's fiber
        context.env.human_queue.enqueue(request)

        # When we resume, the response is in the request
        request.response
      end
    end
  end
end
```

#### think.rb
- [ ] Parameters: `{ thought: string }`
- [ ] Log to bus but don't show to human (or show dimmed)
- [ ] Return acknowledgment
- [ ] Useful for chain-of-thought reasoning

#### create_capability.rb
- [ ] Parameters: `{ type, name, description, capabilities, body }`
- [ ] For type "prompt_object":
  - Build frontmatter YAML
  - Combine with body markdown
  - Write to `objects/` directory
  - Load into registry
- [ ] For type "primitive": return error (not supported in MVP)

### 4.2 Human Interaction Queue

**File**: `lib/prompt_objects/human_queue.rb`

Non-blocking system for POs to request human attention. Multiple POs can be waiting simultaneously.

```ruby
module PromptObjects
  class HumanRequest
    attr_reader :id, :capability, :type, :question, :options, :created_at
    attr_accessor :response

    def initialize(capability:, type:, question:, options: nil)
      @id = SecureRandom.uuid
      @capability = capability
      @type = type
      @question = question
      @options = options
      @created_at = Time.now
      @response = nil
      @fiber = Fiber.current
    end

    def respond!(value)
      @response = value
      @fiber.resume(value)
    end

    def pending?
      @response.nil?
    end
  end

  class HumanQueue
    attr_reader :pending

    def initialize
      @pending = []
      @subscribers = []
    end

    def enqueue(request)
      @pending << request
      notify_subscribers(:added, request)
      # Suspend the calling fiber until human responds
      Fiber.yield
    end

    def respond(request_id, value)
      request = @pending.find { |r| r.id == request_id }
      return unless request

      @pending.delete(request)
      notify_subscribers(:resolved, request)
      request.respond!(value)
    end

    def pending_for(capability_name)
      @pending.select { |r| r.capability == capability_name }
    end

    def subscribe(&block)
      @subscribers << block
    end

    private

    def notify_subscribers(event, request)
      @subscribers.each { |s| s.call(event, request) }
    end
  end
end
```

### 4.3 PO States & Concurrent Execution

**File**: `lib/prompt_objects/executor.rb`

POs run in Fibers for cooperative concurrency. States:
- `idle` - Not doing anything
- `working` - Processing (LLM call in progress)
- `waiting_for_human` - Suspended, has pending HumanRequest
- `active` - Currently being interacted with by human

```ruby
module PromptObjects
  class Executor
    def initialize(env:)
      @env = env
      @fibers = {}  # capability_name => Fiber
    end

    def run(capability, message, context:)
      fiber = Fiber.new do
        capability.receive(message, context: context)
      end

      @fibers[capability.name] = fiber
      capability.state = :working

      result = fiber.resume

      if fiber.alive?
        # Fiber yielded (waiting for human)
        capability.state = :waiting_for_human
        nil  # Result pending
      else
        # Fiber completed
        capability.state = :idle
        @fibers.delete(capability.name)
        result
      end
    end

    def resume(capability_name)
      fiber = @fibers[capability_name]
      return unless fiber&.alive?

      capability = @env.registry.get(capability_name)
      capability.state = :working

      result = fiber.resume

      unless fiber.alive?
        capability.state = :idle
        @fibers.delete(capability_name)
      end

      result
    end
  end
end
```

### 4.4 Extensible Request Types

The `HumanRequest` system is designed to support future interaction types beyond `ask_human`:

```ruby
module PromptObjects
  class HumanRequest
    TYPES = {
      ask_human: {
        icon: "❓",
        renderer: :render_question
      },
      confirm_action: {
        icon: "⚠️",
        renderer: :render_confirmation
      },
      review_output: {
        icon: "👁",
        renderer: :render_review
      },
      provide_input: {
        icon: "✏️",
        renderer: :render_input_form
      }
    }
  end
end
```

Future universal capabilities can use the same queue:
- `confirm_action` - "About to delete 5 files. Proceed?"
- `review_output` - "Here's the code I generated. Approve?"
- `provide_input` - "I need the API key for service X"

### 4.5 Environment Updates

- [ ] Auto-register universal capabilities
- [ ] Add `human_queue` instance
- [ ] Add `executor` for fiber management
- [ ] Method to add universal caps to any PO's available tools
- [ ] `prompt_objects_dir` configuration

### 4.6 PromptObject Updates

- [ ] Merge universal capabilities with declared capabilities
- [ ] Universal caps don't need to be in frontmatter
- [ ] Add `state` attribute for tracking execution state

### 4.7 Update Coordinator

Add `create_capability` to coordinator's capabilities list.

### Phase 4 Deliverable

- Run `./exe/prompt_objects coordinator`
- Ask for help with something requiring a new specialist
- Coordinator uses `ask_human` to get permission
- **Request appears as notification badge on coordinator** (not blocking UI)
- Human can navigate to notification, respond via Huh prompt
- Coordinator resumes and creates new PO via `create_capability`
- New PO appears and can be interacted with
- **Demo 4 achievable** with non-blocking human interaction

---

## Phase 5: Polish & UI

**Goal**: Beautiful Charm-based terminal UI with capability bar, message log, conversation.

### 5.1 Charm Ruby Gems (Marco Roth's Ports)

Use Marco Roth's Ruby ports of the Charm libraries:
- **bubbletea** - Elm-inspired TUI framework (Model-View-Update)
- **lipgloss** - CSS-like terminal styling
- **glamour** - Markdown rendering in terminal
- **bubbles** - Pre-built components (spinners, text inputs, progress bars)
- **huh** - Interactive forms/prompts (perfect for `ask_human`!)

GitHub: https://github.com/marcoroth/bubbletea-ruby (and related repos)
Reference: https://marcoroth.dev/posts/glamorous-christmas

### 5.2 UI Components (Bubble Tea approach)

**Directory**: `lib/prompt_objects/ui/`

#### app.rb
- [ ] Main application loop
- [ ] Handle keyboard input
- [ ] Manage screen layout
- [ ] Coordinate component updates

#### capability_bar.rb
- [ ] Display all registered capabilities
- [ ] Show state: ○ idle, ◐ working, ● active, ⚠ waiting_for_human
- [ ] Distinguish POs from primitives (▪)
- [ ] **Notification badges**: Show count of pending requests per PO
- [ ] Keyboard navigation: Tab/arrow keys to select PO
- [ ] Click or Enter to focus a PO (especially ones with pending requests)
- [ ] Update in real-time as state changes

```
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ greeter  │ │  reader  │ │  coord   │ │ debugger │
│    ○     │ │    ◐     │ │   ⚠ 2    │ │   ⚠ 1    │
└──────────┘ └──────────┘ └──────────┘ └──────────┘
                          ^ 2 pending   ^ 1 pending
```

#### message_log.rb
- [ ] Subscribe to message bus
- [ ] Display scrolling log of messages
- [ ] Color-code by capability type
- [ ] Truncate long messages
- [ ] Timestamp formatting

#### conversation.rb
- [ ] Show current conversation with active PO
- [ ] Render markdown responses (via `tty-markdown` or similar)
- [ ] Handle streaming output

#### input.rb
- [ ] Text input field
- [ ] History (up/down arrows)
- [ ] Handle special commands

#### notification_panel.rb
- [ ] List all pending HumanRequests across all POs
- [ ] Show: PO name, request type, question preview, age
- [ ] Keyboard navigation to select a request
- [ ] Enter to engage with selected request (opens Huh prompt)
- [ ] Toggle visibility with hotkey (e.g., `n` for notifications)
- [ ] Sort by age or PO name

```
┌─ PENDING REQUESTS (3) ────────────────────────────────────┐
│                                                           │
│  ▸ coordinator  "Create Ruby debugging specialist?"  2m   │
│    debugger     "Which bug should I focus on?"       45s  │
│    reader       "Delete all files in spec/?"         10s  │
│                                                           │
│  [Enter] Respond  [Esc] Close  [↑↓] Navigate              │
└───────────────────────────────────────────────────────────┘
```

#### request_responder.rb
- [ ] Modal that appears when engaging with a HumanRequest
- [ ] Renders the full question with context
- [ ] Uses **Huh** components for input (select, text input, confirm)
- [ ] On submit: calls `human_queue.respond(request_id, value)`
- [ ] PO resumes execution automatically

### 5.3 Streaming Support

- [ ] Update LLM adapter to support streaming
- [ ] Pass deltas through context callbacks
- [ ] UI updates character-by-character

### 5.4 State Management

- [ ] Track which PO is "active" (talking to human)
- [ ] Track which POs are "working" (processing)
- [ ] Broadcast state changes to UI

### 5.5 Spinners & Polish

- [ ] Show spinner during LLM calls
- [ ] Graceful handling of slow responses
- [ ] Keyboard shortcuts (e.g., `m` to toggle message log)

### Phase 5 Deliverable

- Full TUI experience
- See capability bar at top with **notification badges**
- See message log showing all traffic
- See conversation area with current PO
- **Notification panel** accessible via hotkey
- Navigate between POs, respond to pending requests
- Multiple POs can be waiting simultaneously without blocking
- Input at bottom
- **Demo 5 achievable** - human-in-the-loop feels natural and scalable

---

## Phase 6: Demo Ready

**Goal**: Everything works smoothly for an 8-minute demo.

### 6.1 Error Handling

- [ ] Graceful LLM API errors (rate limits, timeouts)
- [ ] Invalid capability references
- [ ] File system errors in primitives
- [ ] Malformed prompt object files
- [ ] Capability loop detection

### 6.2 Demo Script

- [ ] Write exact script for 8-minute demo
- [ ] Prepare prompt objects for each demo
- [ ] Time each section
- [ ] Identify where things could go wrong

### 6.3 Demo Prompt Objects

Finalize and test:
- [ ] `objects/greeter.md` - warm, welcoming, no capabilities
- [ ] `objects/reader.md` - file exploration specialist
- [ ] `objects/coordinator.md` - delegates to specialists

### 6.4 Backup Plan

- [ ] Record backup video of successful run
- [ ] Prepare fallback if live demo fails
- [ ] Have reset script to restore clean state

### 6.5 Practice

- [ ] Run through demo 5+ times
- [ ] Time it precisely
- [ ] Identify common failure points
- [ ] Prepare recovery strategies

### Phase 6 Deliverable

- Polished, tested demo
- Backup video ready
- Confident presenter
- **All 5 demos work smoothly**

---

## File Checklist

```
prompt_objects/
├── Gemfile
├── CLAUDE.md
├── IMPLEMENTATION_PLAN.md
├── design-doc-v2.md
│
├── exe/
│   └── prompt_objects
│
├── lib/
│   ├── prompt_objects.rb
│   └── prompt_objects/
│       ├── capability.rb
│       ├── context.rb
│       ├── environment.rb
│       ├── executor.rb
│       ├── human_queue.rb
│       ├── loader.rb
│       ├── message_bus.rb
│       ├── primitive.rb
│       ├── prompt_object.rb
│       ├── registry.rb
│       │
│       ├── llm/
│       │   ├── adapter.rb
│       │   ├── openai_adapter.rb
│       │   └── response.rb
│       │
│       ├── primitives/
│       │   ├── list_files.rb
│       │   ├── read_file.rb
│       │   └── write_file.rb
│       │
│       ├── universal/
│       │   ├── ask_human.rb
│       │   ├── create_capability.rb
│       │   └── think.rb
│       │
│       └── ui/
│           ├── app.rb
│           ├── capability_bar.rb
│           ├── conversation.rb
│           ├── input.rb
│           ├── message_log.rb
│           ├── notification_panel.rb
│           └── request_responder.rb
│
├── objects/
│   ├── coordinator.md
│   ├── greeter.md
│   └── reader.md
│
└── spec/
    └── (tests as needed)
```

---

## Dependencies Summary

```ruby
# Gemfile
source "https://rubygems.org"

# Core
gem "ruby-openai"           # LLM API (or anthropic SDK)
gem "front_matter_parser"   # YAML frontmatter parsing

# Charm TUI (Marco Roth's Ruby ports)
gem "bubbletea"             # Elm-inspired TUI framework
gem "lipgloss"              # CSS-like terminal styling
gem "glamour"               # Markdown rendering
gem "bubbles"               # Pre-built components (spinners, inputs, etc.)
gem "huh"                   # Interactive forms/prompts
```
