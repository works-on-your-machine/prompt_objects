# Long-Term State for Prompt Objects

## The Problem

POs live in short sessions. When a session ends, context is lost. But there are things a PO might want to remember:

- **Learnings**: "User prefers concise answers", "This codebase uses tabs"
- **Context**: "We're working on the auth module", "Debugging issue #123"
- **Progress**: "Reviewed files A, B, C", "Step 3 of 5"
- **Preferences**: "Always ask before writing files"

## Current Options (what we have)

| Mechanism | Good for | Limitations |
|-----------|----------|-------------|
| Session history | Conversation replay | Not structured, gets long |
| `modify_prompt` | Identity/behavior changes | Mixes state with soul |
| Writing files | Large data | Heavyweight, not queryable |

## New Options to Consider

### Option 1: Key-Value Store per PO

```ruby
store_state(key: "user_style", value: "concise")
get_state(key: "user_style")  # => "concise"
list_state()
delete_state(key: "user_style")
```

**Pros**: Simple, fast, familiar
**Cons**: Flat, no organization

**Implementation**: New SQLite table `po_state(po_name, key, value, updated_at)`

### Option 2: Scoped Memory (PO vs Session vs Environment)

```ruby
store_state(key: "task", value: "fixing auth", scope: "session")   # Dies with session
store_state(key: "preference", value: "brief", scope: "po")        # Persists forever
store_state(key: "project_type", value: "rails", scope: "env")     # Shared across all POs
```

**Use cases**:
- `session`: "What files have I looked at?" (ephemeral)
- `po`: "User likes TypeScript" (this PO learns)
- `env`: "This is a Rails project" (all POs should know)

### Option 3: Structured State Section in Prompt

Convention: A `## State` section that's managed separately:

```markdown
## State
- current_task: debugging auth
- learnings:
  - User prefers TypeScript
  - Always run tests after changes
```

**Pros**: Visible in UI, human-editable, included in system prompt automatically
**Cons**: Mixes with identity, can get messy

### Option 4: Semantic Memory Primitives

Higher-level operations:

```ruby
learn("User prefers concise responses")
recall(about: "user preferences")
forget("old task context")
```

**Pros**: More natural language-y, matches how we think about memory
**Cons**: Harder to implement well, fuzzy semantics

## When Would This Be Useful?

1. **Multi-session workflows**: PO helping with a project over days/weeks, needs to remember context
2. **Preference learning**: PO adapts to user style without being told repeatedly
3. **Task handoff**: One PO hands off to another, state provides context
4. **Self-improvement**: PO notices what works, remembers for next time
5. **Checkpointing**: Long task gets interrupted, can resume with stored progress

## Recommendation

Start with **Option 1 + 2 combined** (scoped key-value):

```ruby
# Universal primitives
store_state(key:, value:, scope: "po")  # scope: po | session | env
get_state(key:, scope: "po")
list_state(scope: "po")
delete_state(key:, scope: "po")
```

- Simple to implement (SQLite table)
- Flexible scopes cover most use cases
- Can layer semantic helpers on top later
- Values are JSON for structured data

## Open Questions

1. Should state be visible in the UI? (Probably yes - maybe a "State" tab?)
2. Should key state be included in the system prompt automatically?
3. Size limits to prevent unbounded growth?
4. Should POs be able to read other POs' state?
5. How does state interact with environment export/import?
