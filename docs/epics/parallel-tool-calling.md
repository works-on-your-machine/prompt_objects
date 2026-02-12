# Parallel Tool Calling

**Status**: Ready
**Priority**: High
**Depends on**: Spatial Canvas (In Progress), Web Server Infrastructure (Done)

---

## Overview

When a PO's LLM response includes multiple tool_calls, they currently execute sequentially via `.map`. This epic enables concurrent execution — all tool calls in a single turn run in parallel, but results are still collected and returned together for the next LLM turn. This is purely an execution optimization from the LLM's perspective (same input/output contract), but it fundamentally changes observability, error handling, and the visual experience.

### Why This Matters

A coordinator PO that delegates to 3 worker POs currently waits for each one serially. If each takes 5 seconds, that's 15 seconds. With parallel execution, it's ~5 seconds. For tool-heavy workflows (read 10 files, call 3 APIs, delegate to 2 POs), the speedup is dramatic.

### Core Invariant

**The LLM tool calling contract is preserved**: when the model generates N tool_calls in a single response, all N results are returned together in the next message. Parallel execution changes *when* things run, not *what* the model sees.

```
assistant: tool_calls: [Tool1, Tool2, PO-C]
                         │       │      │
                         ▼       ▼      ▼     ← run concurrently
                       result1 result2 result3
                         │       │      │
                         └───────┴──────┘     ← barrier wait, collect all
                                │
tool: [result1, result2, result3]             ← returned together
assistant: "Based on all three results..."
```

---

## Current Architecture (Sequential)

### Execution Flow

```ruby
# prompt_object.rb — execute_tool_calls
def execute_tool_calls(tool_calls, context:)
  tool_calls.map do |tc|                    # Sequential .map
    capability = @registry.resolve(tc.name)
    if capability.is_a?(PromptObject)
      execute_po_delegation(capability, tc, context)  # Blocks
    else
      capability.call(tc.arguments, context: context)  # Blocks
    end
  end
end
```

Each tool call waits for the previous one to finish. PO-to-PO delegations are especially expensive — the delegated PO runs its own multi-turn LLM loop before returning.

### State Broadcasting Gap

The server only sends `po_state` updates for the PO that the user directly messaged. Delegated POs are invisible — they execute inside the caller's `receive()` chain and never broadcast their status. The frontend currently infers delegation by scanning tool_calls in the caller's message history (fragile, lossy).

### Thread Isolation (Already Exists)

`receive_in_thread` already provides basic session isolation:

```ruby
def receive_in_thread(message, context:, thread_id:)
  original_session = @session_id
  original_history = @history.dup
  @session_id = thread_id
  @history = []
  reload_history_from_session
  begin
    result = receive(message, context: context)
  ensure
    @session_id = original_session
    @history = original_history
  end
end
```

But this swaps instance variables on a shared object — not safe for concurrent execution.

---

## Target Architecture (Parallel)

### Execution Model

Replace sequential `.map` with `Async::Barrier` (cooperative fiber concurrency via the Async gem, which Falcon already uses):

```ruby
def execute_tool_calls(tool_calls, context:)
  barrier = Async::Barrier.new
  semaphore = Async::Semaphore.new(MAX_CONCURRENT_CALLS)  # e.g., 5

  tasks = tool_calls.map do |tc|
    semaphore.async(parent: barrier) do
      execute_single_tool(tc, context)
    end
  end

  barrier.wait  # Block until all complete
  tasks.map(&:result)
end
```

Key properties:
- **Async fibers, not OS threads**: Cooperative scheduling via Async gem. No mutex needed for most things since fibers yield explicitly (at I/O boundaries).
- **Semaphore bounded**: Prevents thundering herd on the LLM API. Max 5 concurrent calls by default (configurable).
- **Barrier wait**: All results collected before returning to the LLM loop. Same contract as sequential.
- **Error tolerance**: If one task fails, others still complete. Failed tasks return error strings as their result content.

### Context Isolation (Required Change)

With concurrent execution, `receive_in_thread`'s swap-and-restore pattern breaks. Two fibers would clobber each other's `@session_id` and `@history`.

Solution: make thread state fully task-local instead of mutating instance variables:

```ruby
def receive_in_thread(message, context:, thread_id:)
  # Each fiber gets its own isolated state — no instance mutation
  isolated_history = session_store.load_messages(thread_id)
  receive_isolated(
    message,
    context: context,
    session_id: thread_id,
    history: isolated_history
  )
end

def receive_isolated(message, context:, session_id:, history:)
  # New method: runs the LLM loop with explicit state instead of instance vars
  # This is the main refactor — extract @session_id/@history from instance
  # state into parameters threaded through the execution
end
```

### State Broadcasting (Required Change)

Add explicit WebSocket events for delegation lifecycle:

```ruby
def execute_po_delegation(target_po, tool_call, context)
  thread_id = target_po.create_delegation_thread(...)

  # NEW: Broadcast delegation start
  broadcast(:po_delegation_started, {
    target: target_po.name,
    caller: context.calling_po,
    thread_id: thread_id,
    tool_call_id: tool_call.id
  })

  result = target_po.receive_in_thread(message, thread_id: thread_id)

  # NEW: Broadcast delegation complete
  broadcast(:po_delegation_completed, {
    target: target_po.name,
    caller: context.calling_po,
    thread_id: thread_id,
    tool_call_id: tool_call.id
  })

  result
end
```

Additionally, delegated POs should broadcast their own `po_state` transitions (thinking, calling_tool, idle) just like directly-messaged POs do. This means the status broadcasting needs to move from the WebSocket handler into the PO execution loop itself.

### WebSocket Protocol Additions

| Message Type | Payload | Direction | Purpose |
|---|---|---|---|
| `po_delegation_started` | `{ target, caller, thread_id, tool_call_id }` | server → client | Target PO activated by delegation |
| `po_delegation_completed` | `{ target, caller, thread_id, tool_call_id }` | server → client | Target PO finished delegation |
| `parallel_batch_started` | `{ caller, tool_call_ids: [...], batch_id }` | server → client | Group of parallel calls began |
| `parallel_batch_completed` | `{ caller, batch_id, results_summary }` | server → client | All parallel calls in batch finished |
| `po_state` (enhanced) | existing + `{ delegated_by?, batch_id? }` | server → client | PO status now includes delegation context |

### Error Handling

When tool calls run in parallel and one fails:

1. **The failure is isolated**: Other concurrent tasks continue to completion.
2. **Error becomes result content**: The failed tool call returns an error message string as its result, not an exception.
3. **LLM decides next step**: The model sees all results (including the error) and can choose to retry, work around it, or report the failure.
4. **Cascade protection**: If a delegated PO hits an unrecoverable error, its fiber terminates cleanly and the barrier collects the error result.

```ruby
semaphore.async(parent: barrier) do
  execute_single_tool(tc, context)
rescue => e
  { error: true, message: "Tool #{tc.name} failed: #{e.message}" }
end
```

### Concurrency Limits

Default limits (configurable per-environment):

| Resource | Limit | Rationale |
|---|---|---|
| Concurrent tool calls per PO | 5 | Prevent one PO from monopolizing the LLM API |
| Concurrent delegations total | 10 | Environment-wide cap on active PO executions |
| LLM API calls per second | Rate-limited by provider | Respect API rate limits |
| SQLite write concurrency | 1 (WAL mode) | SQLite limitation — writes serialize, reads parallel |

---

## Frontend Changes

### Canvas Visualization

With proper server-side events, the canvas gets simpler and more accurate:

**Remove client-side inference**: The current `extractAndCreateToolCalls` method scans PO message history to infer tool calls. With `po_delegation_started/completed` events, the SceneManager reacts to explicit server events instead.

**Fan-out visualization**: When `parallel_batch_started` arrives with multiple targets, animate arcs from the caller to all targets simultaneously. Visual effect: one node radiating connections outward like a starburst.

**Concurrent activity**: Multiple PO nodes glow simultaneously. The canvas should clearly show which POs are working at the same time vs sequentially.

**Progress indicator**: Show "2/5 calls complete" on the caller PO node during a parallel batch.

### WebSocket Handler (`useWebSocket.ts`)

Add handlers for new message types:

```typescript
case 'po_delegation_started': {
  const { target, caller } = message.payload
  setPromptObject(target, { status: 'thinking', delegated_by: caller })
  break
}

case 'po_delegation_completed': {
  const { target } = message.payload
  setPromptObject(target, { status: 'idle', delegated_by: null })
  break
}

case 'parallel_batch_started': {
  const { caller, tool_call_ids, batch_id } = message.payload
  // Track active batch for progress display
  break
}

case 'parallel_batch_completed': {
  const { caller, batch_id } = message.payload
  // Clear batch tracking
  break
}
```

### Chat Panel

- Show delegation threads: when PO-B is delegated by PO-A, allow viewing PO-B's delegation thread in the chat panel
- Parallel execution indicator: "Running 3 tasks in parallel..." status message
- Thread tree visualization showing parent-child delegation relationships

### Store Extensions

```typescript
interface ParallelState {
  // Active parallel batches: batch_id → { caller, tool_call_ids, completed_ids }
  activeBatches: Map<string, ParallelBatch>
  // Delegation tracking: target_po → { caller, thread_id }
  activeDelegations: Map<string, DelegationInfo>
}
```

---

## Database Considerations

SQLite with WAL mode already supports concurrent reads. For parallel execution:

- **Writes serialize**: Multiple fibers writing session messages will queue at the SQLite write lock. WAL mode with 5-second busy timeout handles this gracefully.
- **Session isolation**: Each delegation thread writes to its own session_id, so write contention is low (different rows).
- **Consider write batching**: If 5 parallel tasks all finish within milliseconds, batch their result writes into a single transaction.

---

## Migration Path

Parallel execution is opt-in and backward-compatible:

1. **Default: sequential** (current behavior, no risk)
2. **Environment flag**: `parallel_tool_calls: true` in environment config
3. **Gradual rollout**: Enable per-environment, monitor for issues
4. **No LLM contract change**: The model never knows whether its tool calls ran sequentially or in parallel

---

## Verification

1. PO-A calls 3 tools in one turn → all 3 execute concurrently (visible in canvas as simultaneous activity)
2. PO-A delegates to PO-B and PO-C in parallel → both POs show as active simultaneously on canvas
3. One parallel task fails → other tasks complete, LLM receives all results including error
4. Semaphore limits respected → 6th concurrent call waits for a slot
5. Canvas shows fan-out animation when parallel batch starts
6. Chat panel shows "Running 3 tasks in parallel..." during execution
7. Delegation threads viewable in chat panel during and after execution
8. Sequential mode still works when parallel flag is off
