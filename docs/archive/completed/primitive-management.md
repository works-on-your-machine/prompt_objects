# Primitive Management

## Overview

Enable POs to create and manage their own primitives (deterministic code), and request new primitives from humans when they identify a need.

## Motivation

- **Self-improvement**: POs can write deterministic code for repetitive tasks
- **Human-in-the-loop**: POs can request primitives they need, with human approval
- **Specialization**: Each PO can have custom tooling tailored to its role
- **Transparency**: Humans see what tools POs are creating/requesting

## Core Concepts

### Universal Capabilities

These would be available to all POs (like `ask_human`, `think`):

| Capability | Description |
|------------|-------------|
| `add_primitive` | Add an existing stdlib primitive to this PO |
| `create_primitive` | Write new Ruby code as a primitive for this PO |
| `modify_primitive` | Update/fix an existing primitive's code |
| `verify_primitive` | Test a primitive with sample inputs before using |
| `request_primitive` | Ask human to create/approve a primitive |
| `list_primitives` | List available and active primitives |

### Primitive Lifecycle

```
PO identifies need
       │
       ▼
┌──────────────────┐
│ request_primitive │──────────────────┐
└────────┬─────────┘                   │
         │                             │
         ▼                             ▼
┌─────────────────┐          ┌─────────────────┐
│  Human Reviews  │          │ create_primitive │
│    Request      │          │  (if allowed)    │
└────────┬────────┘          └────────┬────────┘
         │                            │
    ┌────┴────┬────────┐              │
    ▼         ▼        ▼              │
 Approve   Suggest   Reject           │
 as Prim.  as PO                      │
    │         │                       │
    ▼         ▼                       │
┌─────────┐  ┌─────────┐              │
│ Create  │  │ Create  │              │
│Primitive│  │ New PO  │              │
└────┬────┘  └─────────┘              │
     │                                │
     └────────────────┬───────────────┘
                      ▼
              ┌──────────────┐
              │ PO uses new  │
              │  capability  │
              └──────────────┘
```

---

## Capabilities

### add_primitive

Add an existing stdlib primitive to this PO's capabilities.

```ruby
# PO calls:
add_primitive("http_get")
add_primitive("write_file")

# Result: Primitive is added to PO's capability list
# Persisted to PO's markdown frontmatter
```

**Implementation**: Already partially exists via `add_capability`. May just need refinement.

### create_primitive

Write new Ruby code as a primitive. Requires trust/sandbox considerations.

```ruby
# PO calls:
create_primitive(
  name: "parse_json",
  description: "Parse JSON string into Ruby hash",
  code: <<~RUBY
    def call(json_string:)
      JSON.parse(json_string, symbolize_names: true)
    rescue JSON::ParserError => e
      { error: e.message }
    end
  RUBY
)
```

**Security Considerations**:
- Code runs in sandbox by default (limited filesystem, no network)
- Human can review and trust specific primitives
- Trust stored in environment config, not in PO file

**Storage**:
- Saved to `environment/primitives/{name}.rb`
- Marked as "created by {po_name}" in metadata

### request_primitive

Request a primitive from the human. Similar to `ask_human` but specifically for tooling needs.

```ruby
# PO calls:
request_primitive(
  name: "fetch_weather",
  description: "Fetch current weather for a location",
  reason: "I need to check weather conditions for travel planning tasks",
  suggested_implementation: <<~RUBY
    # Optional: PO can suggest code
    def call(location:)
      # HTTP request to weather API
    end
  RUBY
)
```

**Human Response Options**:

1. **Approve as Primitive**: Human writes/approves the code, it becomes a primitive
2. **Suggest as PO**: "This is complex enough to be its own PO" → creates a new PO
3. **Reject**: "You don't need this" / "Use existing capability X instead"
4. **Defer**: "I'll handle this later" → stays in pending requests

**TUI Integration**:
- Shows in notification panel like `ask_human` requests
- Special UI for reviewing/editing code
- Option to run in sandbox before approving

### modify_primitive

Update or fix an existing primitive's code.

```ruby
# PO calls:
modify_primitive(
  name: "parse_json",
  code: <<~RUBY
    def call(json_string:, symbolize: true)
      JSON.parse(json_string, symbolize_names: symbolize)
    rescue JSON::ParserError => e
      { error: e.message, input: json_string[0..100] }
    end
  RUBY,
  reason: "Added symbolize option and better error reporting"
)
```

**Behavior:**
- Updates the primitive file in `environment/primitives/`
- Keeps history of changes (git commit)
- Re-runs verification if tests exist
- Human notification for untrusted primitives

### verify_primitive

Test a primitive with sample inputs before using it in real tasks.

```ruby
# PO calls:
verify_primitive(
  name: "parse_json",
  tests: [
    { input: { json_string: '{"a": 1}' }, expected: { a: 1 } },
    { input: { json_string: 'invalid' }, expected_error: true },
    { input: { json_string: '[]' }, expected: [] }
  ]
)

# Returns:
{
  passed: 2,
  failed: 1,
  results: [
    { input: {...}, output: {...}, passed: true },
    { input: {...}, output: {...}, passed: true },
    { input: {...}, error: "...", passed: false, expected_error: true }
  ]
}
```

**Use cases:**
- PO tests primitive before relying on it
- Verify after `create_primitive` or `modify_primitive`
- Human can request verification before trusting
- Can be run in sandbox even for trusted primitives

### list_primitives

List available primitives (stdlib and custom).

```ruby
# PO calls:
list_primitives(filter: :available)  # All primitives PO could add
list_primitives(filter: :active)     # Primitives PO currently has
list_primitives(filter: :stdlib)     # Built-in primitives
list_primitives(filter: :custom)     # Environment-specific primitives
```

---

## Data Structures

### PrimitiveRequest

```ruby
PrimitiveRequest = Struct.new(
  :id,                    # UUID
  :requesting_po,         # PO name
  :name,                  # Requested primitive name
  :description,           # What it should do
  :reason,                # Why the PO needs it
  :suggested_code,        # Optional implementation
  :status,                # :pending, :approved, :rejected, :deferred
  :response,              # Human's response/notes
  :created_at,
  :resolved_at,
  keyword_init: true
)
```

### PrimitiveMetadata

```ruby
# Stored in primitive file or alongside
PrimitiveMetadata = Struct.new(
  :name,
  :description,
  :created_by,            # PO name or "human"
  :created_at,
  :trusted,               # Boolean
  :sandbox_restrictions,  # Array of restrictions
  keyword_init: true
)
```

---

## Implementation Steps

### Step 1: Primitive Request Queue
- Create `PrimitiveQueue` (similar to `HumanQueue`)
- Add `request_primitive` universal capability
- Wire up to notification panel

### Step 2: Request Responder UI
- New modal for reviewing primitive requests
- Code editor/viewer for suggested implementations
- Approve/Suggest PO/Reject/Defer actions

### Step 3: create_primitive Capability
- Code validation (syntax check)
- Sandbox execution test
- Save to environment primitives directory
- Auto-add to requesting PO

### Step 4: add_primitive Capability
- List available primitives
- Add to PO's frontmatter
- Reload PO capabilities

### Step 5: Trust Management
- Trust UI in capability editor
- Per-primitive and per-PO trust levels
- Sandbox configuration

---

## Security Model

### Trust Levels

| Level | Description | Capabilities |
|-------|-------------|--------------|
| **Untrusted** | Default for created primitives | Sandbox only, no IO |
| **Limited** | Human-reviewed | Read-only filesystem |
| **Trusted** | Explicitly approved | Full capabilities |

### Sandbox Restrictions

```ruby
# Default sandbox for untrusted primitives
sandbox_restrictions: [
  :no_filesystem,
  :no_network,
  :no_shell,
  :no_require,
  :timeout_5s
]
```

---

## TUI Integration

### Notification Badge
```
[n (2)] notifications  ← Shows pending primitive requests
```

### Primitive Request Modal
```
┌─ Primitive Request ─────────────────────────────────┐
│                                                     │
│  From: code_reviewer                                │
│  Requested: fetch_github_pr                         │
│                                                     │
│  Description:                                       │
│  Fetch pull request details from GitHub API        │
│                                                     │
│  Reason:                                           │
│  I need to review PRs but can't access GitHub      │
│  directly. This would let me fetch PR details.     │
│                                                     │
│  Suggested Code:                                   │
│  ┌─────────────────────────────────────────────┐   │
│  │ def call(repo:, pr_number:)                 │   │
│  │   # ... suggested implementation ...        │   │
│  │ end                                         │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
├─────────────────────────────────────────────────────┤
│ [a] Approve  [e] Edit  [p] As PO  [r] Reject       │
└─────────────────────────────────────────────────────┘
```

---

## Open Questions

1. Should POs be able to create primitives directly, or always go through request?
2. How to handle primitive versioning/updates?
3. Should primitives be shareable across environments?
4. How to handle primitive dependencies (one primitive using another)?

---

## Future Enhancements

- **Primitive Templates**: Common patterns for HTTP, file parsing, etc.
- **Primitive Marketplace**: Share primitives across environments
- **Auto-suggest**: System suggests primitives based on PO conversations
- **Primitive Analytics**: Track which primitives are most used
