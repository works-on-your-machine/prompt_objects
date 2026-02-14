# Watcher PO & Reactive Patterns

**Status**: Design (future — build after shared environment data and message provenance)
**Priority**: Medium
**Depends on**: Shared environment data (design), message provenance (design)
**See also**: Earlier brainstorm in `environment-data.md` (full stigmergy/watch/subscription model — elements deferred to here)

---

## Problem

With shared environment data, POs can store and retrieve context within a delegation chain. But what about *reacting* to changes? What if a PO should do something when new data appears, or when certain conditions are met?

The naive answer is explicit event subscriptions — POs declare what data keys they watch, and the runtime notifies them on changes. But that introduces significant complexity: event dispatch, ordering, cascading updates, and the fundamental question of "how does a PO process an unsolicited notification while it might already be doing something?"

We want the reactive *behavior* without the infrastructure *complexity*.

## Solution: The Watcher PO Pattern

Instead of building an event subscription system into the runtime, use what we already have: **a prompt object whose job is to watch for changes and decide what to do**.

A watcher PO is just a regular PO with:
- Access to `list_env_data` and `get_env_data` (universal, already available)
- The ability to send messages to other POs (declared as capabilities)
- A prompt that describes what to watch for and how to react

The key insight: **the reactive logic lives in natural language (the watcher's prompt), not in code**. This means:
- A human can read and understand the routing rules
- The watcher can make nuanced decisions ("this looks urgent, route to the fixer immediately" vs. "this is minor, batch it")
- No new runtime concepts needed — it's just a PO

### Example: ARC-AGI Watcher

```markdown
---
name: arc_watcher
description: Monitors ARC puzzle solving progress and coordinates next steps
capabilities:
  - solver
  - observer
  - transformer
---

# ARC Watcher

## Identity

You monitor the progress of ARC puzzle solving. You watch the shared environment
data for new results and coordinate what happens next.

## Behavior

Periodically check the environment data using `list_env_data()` and `get_env_data()`.

When you see new `observed_patterns` data:
- Check if the patterns are sufficient for the solver to attempt a solution
- If yes, tell the solver to try applying the patterns
- If the patterns are unclear, ask the observer to look more carefully

When you see `solution_attempts` data:
- Check if any attempt succeeded
- If a solution failed, check the error and decide whether to:
  - Ask the observer for more patterns
  - Ask the transformer to try a different approach
  - Ask the human for guidance

When you see `solver_stuck` data:
- Immediately alert the human via ask_human
```

### How does the watcher get triggered?

This is the important design question. There are a few options, ranging from simple to sophisticated:

**Option A: Polling (simplest)**

The watcher PO is called periodically by the runtime or by a coordinator PO. After each major action in a delegation chain, the coordinator asks the watcher "anything to react to?"

```ruby
# In the coordinator's flow:
# After solver finishes its delegation...
watcher.receive("Check the environment data for anything that needs attention.", context: context)
```

**Pros**: No new infrastructure. Just message passing.
**Cons**: Requires a coordinator to drive it. Watcher doesn't truly "watch" — it checks on demand.

**Option B: Post-delegation hook**

The runtime calls the watcher after any delegation completes, if a watcher PO is registered in the environment. This is a lightweight hook, not a full event system.

```ruby
# In Runtime, after a delegation completes:
def after_delegation(target_po, result, context)
  watcher = @registry.get("watcher") # or find POs with a `watcher: true` frontmatter flag
  return unless watcher

  watcher.receive(
    "A delegation just completed. #{target_po.name} finished its work. Check environment data for anything to react to.",
    context: context
  )
end
```

**Pros**: Automatic — the watcher gets called without a coordinator having to remember. Still just message passing.
**Cons**: Gets called after *every* delegation, which might be noisy. Could add a frontmatter option to scope which delegations trigger the watcher.

**Option C: Env data change hook**

The runtime calls the watcher specifically when environment data changes (store, update, delete). This is the closest to actual event subscription, but the "subscriber" is always the watcher PO.

```ruby
# In the store_env_data universal capability:
def after_store(key, context)
  watchers = context.env.registry.prompt_objects.select { |po| po.config["watches_env_data"] }
  watchers.each do |watcher|
    watcher.receive(
      "Environment data changed: key '#{key}' was updated. Check it and decide if any action is needed.",
      context: context
    )
  end
end
```

**Pros**: More targeted — watcher only fires when data actually changes.
**Cons**: Could cause cascading issues if the watcher's actions also change env data (need a guard).

**Recommendation**: Start with **Option A** (polling via coordinator) for simplicity. Graduate to **Option B** (post-delegation hook) when the pattern proves useful. Option C is essentially the beginning of an event subscription system and should be deferred.

---

## Preventing Cascading Loops

If a watcher reacts to data changes by writing more data, which triggers the watcher again, you get an infinite loop. Safeguards:

1. **Depth limit**: Track watcher invocation depth. If the watcher is already running (or was triggered by a watcher action), skip.
2. **Cooldown**: Don't trigger the watcher more than once per N seconds for the same key.
3. **Self-awareness**: Include in the watcher's context that it was triggered by a data change, so it can decide not to cascade.
4. **Natural language guard**: The watcher's prompt can include "Don't react to changes you caused yourself."

---

## Frontmatter Configuration

For Option B or C, POs can opt into watcher behavior:

```yaml
---
name: arc_watcher
description: Monitors ARC puzzle solving progress
capabilities:
  - solver
  - observer
watches_env_data: true    # This PO gets called when env data changes
---
```

Or more granularly:

```yaml
watches_env_data:
  - "observed_patterns"    # Only watch specific keys
  - "solution_attempts"
  - "solver_stuck"
```

---

## Broader Vision: External Triggers & Reactive Environments

The watcher PO pattern is the first step toward a much larger idea: **PO environments that react to the outside world**. The pattern is always the same — something happens, a message arrives, a PO decides what to do.

### Trigger Sources (Future)

The question is always: how does information get into the environment, and how does a PO get told about it?

| Trigger | How it enters | Who processes it |
|---------|--------------|-----------------|
| Env data change | Universal capability (internal) | Watcher PO |
| Discord message | External adapter writes to env data or sends message to a PO | Discord handler PO |
| Incoming email | Email adapter places data in env | Email handler PO |
| Cron/timer | Scheduled job sends a message to a PO | Any PO |
| Webhook/HTTP request | Web server routes to a PO | API handler PO |
| Calendar event | Calendar adapter fires at event time | Scheduler PO |
| Text message/SMS | SMS adapter places data in env | Messaging PO |
| File system change | Watcher detects file change (already built for .md files) | File handler PO |

In every case, the pattern is:
1. Something external happens
2. An **adapter** translates it into a PO message or env data
3. A PO receives the message and decides what to do

The adapter is the boundary between the outside world and the PO environment. PromptObjects already has one adapter: the web server (human sends a message via the UI → PO receives it). The connectors architecture (`lib/prompt_objects/connectors/`) is designed for exactly this — different interfaces into the same environment.

### End-User Facing Web Interfaces

An especially interesting direction: **could a PO environment act as a web application?**

Imagine a PO that has a `serve_html` primitive and a `handle_request` capability:

```markdown
---
name: support_bot
description: Handles customer support via a web interface
capabilities:
  - serve_html
  - read_file
  - query_database
---

# Support Bot

When you receive an HTTP request:
- If it's a GET to /, return the support chat HTML page
- If it's a POST to /message, process the customer's message and respond
- If it's a GET to /status, return the current ticket status
```

This PO could:
- Serve an HTML page with a chat widget
- Receive form submissions as messages
- Query a database for information
- Return HTML/JSON responses

The environment becomes the "backend" and the PO's prompt defines the application logic. This is a very different model from traditional web frameworks — the routing, business logic, and response generation all live in natural language.

### How to model this?

The key abstraction is the **connector** (already partially in the codebase):

```
External World → Connector → Environment → PO → Response → Connector → External World
```

Each connector type translates between an external protocol and PO messages:

- **Web connector**: HTTP request → PO message, PO response → HTTP response
- **Discord connector**: Discord message → PO message, PO response → Discord reply
- **Email connector**: Incoming email → env data, PO response → outgoing email
- **Timer connector**: Cron tick → PO message
- **API connector**: JSON request → PO message, PO response → JSON response

The connector handles the protocol. The PO handles the logic. The environment handles coordination.

### What would it look like to build and test?

For a web-facing PO environment:

1. Define the PO(s) that handle requests
2. Create or configure a web connector (route patterns, which PO handles what)
3. `prompt_objects serve my-app --port 3000` — serves both the admin UI (existing) and the end-user routes
4. The spatial canvas shows the POs processing requests in real-time
5. The admin can watch, intervene (via ask_human), and adjust PO behavior live

For a Discord bot:
1. Define a PO that handles Discord messages
2. Configure a Discord connector with bot token
3. `prompt_objects connect my-env --discord` — starts listening
4. Messages flow in, PO responds, replies flow out
5. The admin UI shows all message traffic

---

## Implementation Steps

### Step 1: Watcher PO as a pattern (no runtime changes)

- Create an example watcher PO in a template
- Document the pattern: coordinator calls watcher after delegations
- Test with ARC-AGI template
- This is purely a prompt engineering / template exercise

### Step 2: Post-delegation hook (small runtime change)

- Add optional `after_delegation` callback in Runtime
- If a PO with `watches_env_data: true` exists, call it after delegations complete
- Add cascade guard (depth limit)

### Step 3: Env data change hook (medium runtime change)

- Add callback in `store_env_data` / `update_env_data` / `delete_env_data`
- Call watcher POs with context about what changed
- Add cooldown and self-trigger guards

### Step 4: Connector abstraction (larger, separate epic)

- Formalize the connector interface
- Build first external connector (timer? webhook? Discord?)
- Route external events to POs
- This is a separate epic but follows naturally from this pattern

---

## Open Questions

1. **Should there be one watcher or many?** A single watcher PO is simpler to reason about. Multiple watchers (each watching different things) is more flexible but harder to debug. Start with one.

2. **Concurrency**: If the watcher triggers while a delegation chain is still in progress, does the watcher run in parallel? Sequentially after? This interacts with Ruby's threading model and the existing Fiber-based concurrency.

3. **Watcher PO's own context**: Does the watcher maintain conversation history across triggers? Or does each trigger start fresh? Probably start fresh — the watcher is more like a stateless router than a conversational agent.

4. **Testing**: How do you test watcher behavior? Probably by mocking env data changes and asserting that the right POs get called. Need to think about test infrastructure.

---

## Future: If the Watcher PO Pattern Proves Limiting, Explore Explicit Event Subscriptions

The watcher PO pattern deliberately keeps reactive behavior in a single, human-readable place (the watcher's prompt). But there are scenarios where this might not be enough:

- **High-frequency triggers**: If env data changes dozens of times per second (e.g., streaming sensor data), calling a full LLM to decide what to do each time is too expensive.
- **Many independent watchers**: If 10 different POs each need to react to different data keys independently, funneling everything through one watcher PO becomes a bottleneck.
- **Precise routing**: Sometimes you know exactly which PO should handle a specific data key — the LLM decision step adds latency for no value.

In these cases, explore **explicit event subscriptions** as described in the earlier `environment-data.md` brainstorm:

```yaml
# Frontmatter
watches:
  - pattern: "sensor:temperature_*"
    filter: { value: { gt: 100 } }
```

This would let POs declare what they watch directly, with the runtime handling dispatch — no watcher PO intermediary. The tradeoff is more runtime complexity and less human-readable routing logic.

This should only be built if the watcher PO pattern is demonstrably insufficient for real use cases. Don't build it speculatively.
