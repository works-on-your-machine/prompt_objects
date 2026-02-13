# Message Provenance & Delegation Context

**Status**: Design
**Priority**: High
**Depends on**: PO-to-PO delegation (complete), shared environment data (design)

---

## Problem

When a PO is called by another PO, it receives a natural language message — but it has very little context about *why* it's being called, *who* is calling it, or *what the broader task is*. The receiving PO is essentially waking up in the middle of a conversation with no memory of how it got there.

**Today**: The `context.calling_po` field tracks the immediate caller, and messages have a `from` field. But the receiving PO's LLM doesn't see any of this in a useful way. It just gets a user message like "What patterns do you notice in this grid?"

**What's missing**:

1. **Who called me?** Not just a name, but what *kind* of thing the caller is. The observer PO doesn't know that "solver" is an ARC-AGI puzzle solver — it just sees the name.
2. **Why was I called?** What's the broader task? What's the human actually trying to accomplish?
3. **What's the delegation chain?** Am I being called directly by a human, or am I three levels deep in a delegation tree?
4. **What is a Prompt Object?** The receiving PO doesn't even have a mental model for what's happening — it doesn't know it's a PO in an environment with other POs, that it might be called by other POs vs. humans, etc.

## Solution: Two Layers

### Layer 1: Base System Prompt (What Am I?)

Every PO already gets a `## System Context` block appended to its body. This should be expanded to give POs a basic understanding of the world they live in:

```markdown
## System Context

You are a prompt object named "observer" running in a PromptObjects environment.

### What is a Prompt Object?
You are an autonomous entity defined by a markdown file. You have an identity (your prompt),
capabilities (tools you can use), and you communicate by receiving messages and responding.
You exist alongside other prompt objects and primitive tools in a shared environment.

### How you get called
You may receive messages from:
- **A human** interacting with you directly through the UI
- **Another prompt object** that has delegated a task to you as part of a larger workflow

When called by another PO, you'll see context about who called you and why in the message
preamble. You can also check shared environment data (via `list_env_data`) for context
that other POs in the same workflow have stored.

### Your capabilities
- Declared capabilities: read_file, list_files
- Universal capabilities (always available): ask_human, think, store_env_data, get_env_data, list_env_data, ...

You can use `list_capabilities` to see full details of your available tools.
```

This gives every PO a basic ontology — it knows what it is, that other POs exist, that it might be called by them, and that shared data might be available.

### Layer 2: Delegation Preamble (Who Called Me and Why?)

When a PO is called by another PO (not by a human), the system injects a **delegation preamble** into the message before the actual content. This preamble gives the receiving PO context about the call.

**Current message flow** (PO-to-PO):
```
User message: "What patterns do you notice in this grid?"
```

**Proposed message flow** (PO-to-PO):
```
User message:

---
[Delegation Context]
Called by: solver
Solver is: "Solves ARC-AGI puzzles by analyzing input/output grid pairs and finding transformation rules"
Delegation chain: human → coordinator → solver → you (observer)
Task context: The human asked the coordinator to "Solve ARC task training-001". The solver loaded the task and is now consulting you for pattern analysis.
Shared environment data is available — call list_env_data() to see what the solver has stored.
---

What patterns do you notice in the current task?
```

### What goes in the preamble?

| Field | Source | Purpose |
|-------|--------|---------|
| **Called by** | `context.calling_po` | Who's calling — the immediate parent |
| **Caller description** | Caller PO's `description` from frontmatter | What the caller *is* — so the receiver understands who it's working for |
| **Delegation chain** | Walk up the delegation thread parents | The full path from human to here — gives a sense of depth and purpose |
| **Task context** | The root human message + the caller's most recent assistant message (summarized) | What the overall task is and what the caller is currently trying to do |
| **Env data hint** | Check if there's any env data in scope | A nudge to check shared data if it exists |

### How to construct the preamble

```ruby
# In PromptObject#execute_po_delegation or PromptObject#receive

def build_delegation_preamble(context)
  caller_po = context.env.registry.get(context.calling_po)
  return nil unless caller_po.is_a?(PromptObject)

  chain = build_delegation_chain(context)
  root_message = find_root_human_message(context)
  has_env_data = env_data_available?(context)

  parts = []
  parts << "---"
  parts << "[Delegation Context]"
  parts << "Called by: #{caller_po.name}"
  parts << "#{caller_po.name} is: \"#{caller_po.description}\""
  parts << "Delegation chain: #{chain}" if chain
  parts << "Task context: #{root_message}" if root_message
  parts << "Shared environment data is available — call list_env_data() to see what context has been stored." if has_env_data
  parts << "---"

  parts.join("\n")
end
```

### Where the preamble gets injected

Two options:

**Option A: Prepend to the user message content**

The simplest approach. Before the target PO's `receive` method processes the message, prepend the preamble:

```ruby
# In execute_po_delegation
def execute_po_delegation(target_po, tool_call, context)
  message = tool_call.arguments
  preamble = build_delegation_preamble(context)

  enriched_message = if preamble
    "#{preamble}\n\n#{normalize_message(message)}"
  else
    message
  end

  # ... delegate with enriched_message
end
```

**Pros**: Simple, the LLM sees it naturally as part of the message.
**Cons**: The preamble is in the user message, so it shows up in conversation history and could confuse subsequent messages.

**Option B: Inject as a system prompt addition on the target PO**

Add the delegation context as a temporary addition to the target PO's system prompt for the duration of the delegation:

```ruby
# In PromptObject#receive, check if there's delegation context
def build_system_prompt
  base = "#{@body}\n\n#{system_context_block}"

  if @current_delegation_context
    "#{base}\n\n#{@current_delegation_context}"
  else
    base
  end
end
```

**Pros**: Cleaner — the message itself stays focused on the task. Context is "ambient" rather than inline.
**Cons**: More plumbing — need to pass delegation context into the target PO and clean it up after.

**Recommendation**: Start with **Option A** (prepend to message). It's simpler and good enough. The LLM handles mixed context/instruction messages well. If it causes problems (preamble leaking into subsequent messages in the same delegation thread), switch to Option B.

---

## Walkthrough: ARC-AGI with Full Provenance

### Human -> Coordinator
```
You: Solve ARC task training-001
```

### Coordinator -> Solver (delegation)
Solver receives:
```
---
[Delegation Context]
Called by: coordinator
coordinator is: "Orchestrates ARC-AGI solving by delegating to specialist POs"
Delegation chain: human → coordinator → you (solver)
Task context: The human asked: "Solve ARC task training-001"
---

Please solve ARC task training-001. Load the task, analyze it, and find the transformation rule.
```

### Solver -> Observer (delegation)
Observer receives:
```
---
[Delegation Context]
Called by: solver
solver is: "Solves ARC-AGI puzzles by analyzing input/output grid pairs and finding transformation rules"
Delegation chain: human → coordinator → solver → you (observer)
Task context: The human asked to solve ARC task training-001. The solver has loaded the task and is consulting you for pattern analysis.
Shared environment data is available — call list_env_data() to see what context has been stored.
---

What patterns do you notice in the current task? Focus on spatial relationships and color transformations.
```

The observer now knows:
- It was called by the solver (and what the solver does)
- It's part of a chain starting from a human request
- There's shared environment data it should check (the loaded grid)
- The specific ask is about patterns

---

## What about the base system prompt?

The expanded system prompt (Layer 1) is a separate, smaller change that benefits all POs regardless of delegation. Key additions:

1. **"You are a prompt object"** — basic self-awareness
2. **"You may be called by humans or other POs"** — sets expectations
3. **"Check shared environment data"** — teaches the env data pattern
4. **Capability inventory** — already partially there, could be richer

This should be implemented first since it's a simple change to `PromptObject#build_system_prompt` and immediately improves all PO behavior.

---

## Implementation Steps

### Step 1: Expand base system prompt
- Update `PromptObject#build_system_prompt` to include the "what is a prompt object" section
- Test with existing POs to ensure it doesn't degrade behavior
- Keep it concise — LLMs perform worse with very long system prompts

### Step 2: Build delegation preamble
- Add `build_delegation_preamble` method
- Build delegation chain by walking thread parents
- Extract root human message from the root thread
- Check env data availability

### Step 3: Inject preamble into delegated messages
- Prepend preamble to message content in `execute_po_delegation`
- Only add preamble for PO-to-PO calls (not human-to-PO)

### Step 4: Test and tune
- Test with ARC-AGI template (solver -> observer flow)
- Test with coordinator -> reader -> coordinator flow
- Tune preamble length — too much context can distract the LLM
- Consider making preamble detail level configurable (minimal, standard, verbose)

---

## Open Questions

1. **How much context is too much?** The delegation preamble adds tokens to every delegated message. Should it be capped? Should it be configurable per-PO in frontmatter?

2. **Should the root human message be summarized?** For long conversations, the original human message might be very long. Summarizing it (maybe via a quick LLM call, or just truncating) might be necessary.

3. **Should POs be able to opt out of the preamble?** Some POs might work better as "pure tools" that just get a clean message. A frontmatter option like `delegation_context: false` could disable it.

4. **Should the preamble include the caller's recent conversation?** Not just what the caller is, but what it's been *doing* — its last few messages. This gives richer context but could be expensive in tokens. Probably not for v1.

5. **Interaction with environment data**: If shared env data exists and the preamble mentions it, should the system automatically inject a `list_env_data()` call result into the context? Or let the PO decide to call it? Leaning toward letting the PO decide — it's more aligned with the autonomous agent model.
