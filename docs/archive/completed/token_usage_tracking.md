# Token Usage & Cost Tracking

## Goal

Track token usage (input/output) and estimated costs for all LLM calls. Surface this per-thread via a right-click context menu in the ThreadsSidebar, showing a usage breakdown page.

## Current State

- **All three adapters** return `raw:` in the Response object, which contains provider-specific usage data:
  - OpenAI: `raw["usage"]["prompt_tokens"]`, `raw["usage"]["completion_tokens"]`
  - Anthropic: `raw.usage.input_tokens`, `raw.usage.output_tokens` (also cache tokens)
  - Gemini: `raw["usageMetadata"]["promptTokenCount"]`, `raw["usageMetadata"]["candidatesTokenCount"]`
- **Response class** only exposes `content`, `tool_calls`, `raw` — no usage fields
- **No cost tracking or pricing data** exists anywhere
- **No context menus** in the frontend

## Design

### Phase 1: Extract Usage from LLM Responses

**File:** `lib/prompt_objects/llm/response.rb`

Add `usage` to Response:

```ruby
class Response
  attr_reader :content, :tool_calls, :raw, :usage

  def initialize(content:, tool_calls: [], raw: nil, usage: nil)
    @usage = usage  # { input_tokens:, output_tokens:, model:, provider: }
  end
end
```

**Each adapter** extracts usage in `parse_response`:

```ruby
# OpenAI
usage = {
  input_tokens: raw.dig("usage", "prompt_tokens") || 0,
  output_tokens: raw.dig("usage", "completion_tokens") || 0,
  model: @model,
  provider: "openai"
}

# Anthropic
usage = {
  input_tokens: raw.usage.input_tokens,
  output_tokens: raw.usage.output_tokens,
  cache_creation_tokens: raw.usage.respond_to?(:cache_creation_input_tokens) ? raw.usage.cache_creation_input_tokens : 0,
  cache_read_tokens: raw.usage.respond_to?(:cache_read_input_tokens) ? raw.usage.cache_read_input_tokens : 0,
  model: @model,
  provider: "anthropic"
}

# Gemini
usage = {
  input_tokens: raw.dig("usageMetadata", "promptTokenCount") || 0,
  output_tokens: raw.dig("usageMetadata", "candidatesTokenCount") || 0,
  model: @model,
  provider: "gemini"
}
```

### Phase 2: Persist Usage Per Message

**File:** `lib/prompt_objects/session/store.rb`

Add `usage` column to messages table (schema v6 migration):

```sql
ALTER TABLE messages ADD COLUMN usage TEXT;
-- JSON: {"input_tokens": 1234, "output_tokens": 567, "model": "claude-haiku-4-5", "provider": "anthropic"}
```

Update `add_message` and `parse_message_row` to handle the new column.

**File:** `lib/prompt_objects/prompt_object.rb`

In `persist_message`, pass usage from the Response:

```ruby
when :assistant
  session_store.add_message(
    session_id: @session_id,
    role: :assistant,
    content: msg[:content],
    tool_calls: tool_calls_data,
    usage: msg[:usage]  # NEW
  )
```

In the receive loop, attach usage to the assistant message hash:

```ruby
assistant_msg = {
  role: :assistant,
  content: nil,
  tool_calls: response.tool_calls,
  usage: response.usage  # NEW
}
```

### Phase 3: Session Usage Aggregation

**File:** `lib/prompt_objects/session/store.rb`

Add query methods:

```ruby
# Get total usage for a session
def session_usage(session_id)
  rows = @db.execute(<<~SQL, [session_id])
    SELECT usage FROM messages
    WHERE session_id = ? AND usage IS NOT NULL
  SQL

  totals = { input_tokens: 0, output_tokens: 0, cost_usd: 0.0, calls: 0 }
  rows.each do |row|
    usage = JSON.parse(row["usage"], symbolize_names: true)
    totals[:input_tokens] += usage[:input_tokens] || 0
    totals[:output_tokens] += usage[:output_tokens] || 0
    totals[:cost_usd] += calculate_cost(usage)
    totals[:calls] += 1
  end
  totals
end

# Get usage for a full delegation chain (thread + all child threads)
def thread_tree_usage(session_id)
  tree = get_thread_tree(session_id)
  aggregate_tree_usage(tree)
end
```

### Phase 4: Cost Calculation

**File:** `lib/prompt_objects/llm/pricing.rb` (new)

Static pricing table (updated periodically):

```ruby
module PromptObjects
  module LLM
    class Pricing
      # Prices per 1M tokens (input, output) in USD
      RATES = {
        # OpenAI
        "gpt-5.2" => { input: 2.00, output: 8.00 },
        "gpt-4.1" => { input: 2.00, output: 8.00 },
        "gpt-4.1-mini" => { input: 0.40, output: 1.60 },
        # Anthropic
        "claude-opus-4" => { input: 15.00, output: 75.00 },
        "claude-sonnet-4-5" => { input: 3.00, output: 15.00 },
        "claude-haiku-4-5" => { input: 0.80, output: 4.00 },
        # Gemini
        "gemini-2.5-pro" => { input: 1.25, output: 10.00 },
        "gemini-2.5-flash" => { input: 0.15, output: 0.60 },
        # Ollama / local
      }.freeze

      def self.calculate(model:, input_tokens:, output_tokens:)
        rates = RATES[model]
        return 0.0 unless rates

        input_cost = (input_tokens / 1_000_000.0) * rates[:input]
        output_cost = (output_tokens / 1_000_000.0) * rates[:output]
        input_cost + output_cost
      end
    end
  end
end
```

Local models (Ollama) return $0.00. OpenRouter models could pull pricing from their API in the future.

### Phase 5: REST + WebSocket API

**File:** `lib/prompt_objects/server/api/routes.rb`

Add endpoint:
```
GET /api/sessions/:id/usage → { input_tokens, output_tokens, cost_usd, calls, by_model: {...} }
GET /api/sessions/:id/usage/tree → same but aggregated across delegation chain
```

**File:** `lib/prompt_objects/server/websocket_handler.rb`

Add handler:
```ruby
when "get_session_usage"
  handle_get_session_usage(message["payload"])
```

Response:
```json
{
  "type": "session_usage",
  "payload": {
    "session_id": "...",
    "input_tokens": 12345,
    "output_tokens": 6789,
    "total_tokens": 19134,
    "cost_usd": 0.042,
    "calls": 8,
    "by_model": {
      "claude-haiku-4-5": { "input_tokens": 10000, "output_tokens": 5000, "cost_usd": 0.028, "calls": 6 },
      "gpt-4.1-mini": { "input_tokens": 2345, "output_tokens": 1789, "cost_usd": 0.014, "calls": 2 }
    }
  }
}
```

### Phase 6: Right-Click Context Menu + Usage Panel

**File:** `frontend/src/components/ContextMenu.tsx` (new)

Generic right-click context menu component:

```tsx
interface ContextMenuProps {
  x: number
  y: number
  items: { label: string; onClick: () => void; icon?: string }[]
  onClose: () => void
}
```

Positioned via portal at cursor coordinates, closes on click-away or Escape.

**File:** `frontend/src/components/ThreadsSidebar.tsx`

Add `onContextMenu` to thread buttons:

```tsx
<button
  onContextMenu={(e) => {
    e.preventDefault()
    showContextMenu(e.clientX, e.clientY, [
      { label: 'View Usage', onClick: () => requestUsage(session.id) },
      { label: 'Export Thread', onClick: () => exportThread(session.id) },
      { label: 'Rename', onClick: () => startRename(session.id) },
    ])
  }}
>
```

**File:** `frontend/src/components/UsagePanel.tsx` (new)

Modal or slide-in panel showing:
- Total input/output tokens
- Estimated cost in USD
- Breakdown by model (table)
- Number of LLM calls
- If delegation chain: breakdown by PO

## Files to Create/Modify

| File | Action |
|------|--------|
| `lib/prompt_objects/llm/response.rb` | Add `usage` field |
| `lib/prompt_objects/llm/openai_adapter.rb` | Extract usage in parse_response |
| `lib/prompt_objects/llm/anthropic_adapter.rb` | Extract usage in parse_response |
| `lib/prompt_objects/llm/gemini_adapter.rb` | Extract usage in parse_response |
| `lib/prompt_objects/llm/pricing.rb` | **Create** — cost calculation |
| `lib/prompt_objects/session/store.rb` | Add usage column (v6), aggregation queries |
| `lib/prompt_objects/prompt_object.rb` | Pass usage through persist_message |
| `lib/prompt_objects/server/api/routes.rb` | Usage REST endpoint |
| `lib/prompt_objects/server/websocket_handler.rb` | Usage WebSocket handler |
| `frontend/src/components/ContextMenu.tsx` | **Create** — generic right-click menu |
| `frontend/src/components/UsagePanel.tsx` | **Create** — usage display |
| `frontend/src/components/ThreadsSidebar.tsx` | Add context menu |
| `frontend/src/types/index.ts` | Add Usage types |
| `frontend/src/hooks/useWebSocket.ts` | Add usage request/response handlers |
| `test/unit/llm/pricing_test.rb` | **Create** |
| `test/unit/session/usage_test.rb` | **Create** |

## Testing

- Unit: Pricing calculation for each provider
- Unit: Usage extraction from mock raw responses
- Unit: Session usage aggregation
- Unit: Tree usage aggregation across delegation chain
- Integration: Full round-trip — send message, verify usage persisted, query via API
