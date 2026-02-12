# Parallel Tool Calling — Stories

**Parent epic**: [parallel-tool-calling.md](parallel-tool-calling.md)

Stories are grouped by theme. Dependencies are noted inline.

---

## Theme 1: Server-Side State Broadcasting (No Parallelism Yet)

These stories fix the observability gap independently of parallel execution. They make the canvas and UI more accurate today.

### Story 1.1: Broadcast po_state for delegated POs
**Priority**: Today (bug fix)

Currently, when PO-A delegates to PO-B, PO-B never gets a `po_state` WebSocket event — it stays "idle" from the client's perspective. The frontend infers delegation by scanning tool_calls in PO-A's message history (fragile).

**Changes**:
- In `prompt_object.rb`, move status broadcasting from the WebSocket handler into the PO execution loop (or add hooks that the WebSocket handler subscribes to)
- When a PO starts `receive()` (even via delegation), broadcast `po_state` with `status: 'thinking'`
- When a PO transitions to `calling_tool`, broadcast that too
- When a PO finishes, broadcast `status: 'idle'`

**Acceptance**:
- Send a message to PO-A that causes it to delegate to PO-B
- PO-B's status updates appear in WebSocket feed in real time
- Canvas shows PO-B glowing/active during delegation without client-side inference

### Story 1.2: Add po_delegation_started/completed events
**Priority**: Today (bug fix)

Add explicit WebSocket events for delegation lifecycle so the frontend knows *who* called *whom*.

**Changes**:
- In `execute_po_delegation`, broadcast `po_delegation_started` before calling `receive_in_thread`
- Broadcast `po_delegation_completed` after it returns
- Payload: `{ target, caller, thread_id, tool_call_id }`

**Acceptance**:
- Frontend receives delegation events and can display "PO-B called by PO-A" accurately
- Canvas SceneManager can replace client-side tool_call scanning with server events

### Story 1.3: Frontend — handle delegation events
**Priority**: Today
**Depends on**: 1.1, 1.2

Update `useWebSocket.ts` and canvas SceneManager to consume the new server events.

**Changes**:
- Add `po_delegation_started` and `po_delegation_completed` handlers in `useWebSocket.ts`
- Update store to track `delegated_by` on PromptObject type
- SceneManager: replace `extractAndCreateToolCalls` delegation inference with event-driven updates
- PONode: `setDelegatedBy` / `clearDelegated` driven by store state instead of scanning

**Acceptance**:
- Canvas shows delegated POs with cyan glow and "called by X" status from server events
- No more client-side tool_call scanning for delegation detection
- Delegation arcs appear from caller to target PO

---

## Theme 2: Context Isolation Refactor (Foundation for Parallelism)

### Story 2.1: Extract instance state from receive loop
**Priority**: Tomorrow

The current `receive()` method reads/writes `@session_id` and `@history` as instance variables. For parallel execution, this state must be task-local.

**Changes**:
- Create `receive_isolated(message, context:, session_id:, history:)` that takes state as parameters
- Refactor `receive()` to call `receive_isolated` with its instance vars
- Refactor `receive_in_thread()` to call `receive_isolated` with thread-local state
- No behavioral change — pure refactor

**Acceptance**:
- All existing tests pass
- `receive_in_thread` no longer mutates `@session_id` or `@history` on the PO instance
- Two calls to `receive_isolated` on the same PO instance with different session_ids would not interfere (unit test this)

### Story 2.2: Thread-safe session store writes
**Priority**: Tomorrow

Verify that concurrent writes to different sessions don't cause SQLite lock contention issues.

**Changes**:
- Add integration test: 3 concurrent `receive_isolated` calls writing to different session_ids
- Verify WAL mode + busy_timeout handles concurrent writes gracefully
- If contention is an issue, add write batching or connection pooling

**Acceptance**:
- 3 concurrent PO executions writing to different sessions all complete without lock errors
- Session data is consistent (no interleaved or lost messages)

---

## Theme 3: Parallel Execution

### Story 3.1: Parallel tool call execution with Async::Barrier
**Priority**: Tomorrow
**Depends on**: 2.1

Replace sequential `.map` in `execute_tool_calls` with `Async::Barrier` for concurrent execution.

**Changes**:
- `execute_tool_calls` spawns an Async task per tool call via `Async::Barrier`
- Add `Async::Semaphore` to limit concurrency (default: 5)
- Barrier waits for all tasks before returning results
- Error handling: failed tasks return error strings, don't crash the batch
- Environment config flag: `parallel_tool_calls: true` (default: false for safety)

**Acceptance**:
- With flag on: 3 tool calls that each take 2 seconds complete in ~2 seconds (not 6)
- With flag off: behavior unchanged (sequential)
- One failing tool call doesn't prevent others from completing
- Semaphore prevents more than N concurrent calls

### Story 3.2: Parallel batch events
**Priority**: Tomorrow
**Depends on**: 3.1

Broadcast when a parallel batch starts and completes.

**Changes**:
- Before `barrier.wait`, broadcast `parallel_batch_started` with `{ caller, tool_call_ids, batch_id }`
- After `barrier.wait`, broadcast `parallel_batch_completed` with `{ caller, batch_id }`
- Individual tool results still trigger their own events (po_delegation_completed, etc.)

**Acceptance**:
- Frontend receives batch events
- Can track progress: "3/5 complete" by counting individual completions within a batch

### Story 3.3: Frontend — parallel batch visualization
**Priority**: Tomorrow
**Depends on**: 3.2

Canvas and UI updates for parallel execution visibility.

**Changes**:
- Canvas: fan-out animation when parallel batch starts (simultaneous arcs to multiple targets)
- Canvas: progress indicator on caller PO node ("2/5")
- Chat panel: "Running N tasks in parallel..." status during batch
- Store: track active batches with completion progress

**Acceptance**:
- Canvas shows multiple POs activating simultaneously during parallel batch
- Caller PO shows progress count
- All concurrent activity visible at a glance

---

## Theme 4: Advanced Observability (Future)

### Story 4.1: Thread tree visualization
**Priority**: Future

Show the parent-child relationship between delegation threads as a tree.

**Changes**:
- New panel or canvas overlay showing thread tree
- Nodes represent threads/sessions, edges represent delegation relationships
- Color-coded by status (active, completed, failed)
- Click to navigate to that thread's messages

### Story 4.2: Timeline/waterfall view
**Priority**: Future

Like browser DevTools network tab — show parallel task execution as horizontal bars on a time axis.

**Changes**:
- New panel showing task bars on a timeline
- Start/end times from batch events
- Overlapping bars clearly show parallelism
- Click to inspect individual task details

### Story 4.3: Execution replay
**Priority**: Future

Scrub through the history of a complex parallel execution.

**Changes**:
- Record all state events with timestamps
- Timeline scrubber that replays canvas state at any point in time
- Play/pause/speed controls

---

## Today vs Tomorrow Summary

### Today (Bug Fixes / Quick Wins)

| Story | What | Why Today |
|-------|------|-----------|
| 1.1 | Broadcast po_state for delegated POs | Fixes "called PO stays idle" bug on canvas |
| 1.2 | Add delegation started/completed events | Replaces fragile client-side inference |
| 1.3 | Frontend handles delegation events | Completes the delegation display fix end-to-end |

### Tomorrow (Parallel Execution)

| Story | What | Why Tomorrow |
|-------|------|-------------|
| 2.1 | Extract instance state from receive loop | Foundation — no parallel without this |
| 2.2 | Thread-safe session store writes | Verify DB handles concurrency |
| 3.1 | Parallel execution with Async::Barrier | The core feature |
| 3.2 | Parallel batch events | Observability for parallel execution |
| 3.3 | Frontend parallel visualization | Canvas fan-out, progress indicators |

### Future

| Story | What |
|-------|------|
| 4.1 | Thread tree visualization |
| 4.2 | Timeline/waterfall view |
| 4.3 | Execution replay |
