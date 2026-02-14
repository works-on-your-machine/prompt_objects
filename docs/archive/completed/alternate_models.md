# Alternate Models: Ollama + OpenRouter Support

## Goal

Support local/open-source models via Ollama and cloud open-source models via OpenRouter, alongside the existing paid providers (OpenAI, Anthropic, Gemini). Users should be able to hot-swap between any provider from the web UI.

## Current State

- **Factory pattern**: `LLM::Factory` with `PROVIDERS` hash, `create()`, `switch_llm()` — well-designed for extension
- **Adapters**: `OpenAIAdapter`, `AnthropicAdapter`, `GeminiAdapter` — each implements `chat(system:, messages:, tools:)`
- **Hot-swap**: `Runtime#switch_llm` updates all POs dynamically
- **Web UI**: LLM switcher dropdown already exists in Header component

## Design

### Key Insight: Both Ollama and OpenRouter use OpenAI-compatible APIs

Instead of writing two new adapters from scratch, make `OpenAIAdapter` configurable with a `base_url` parameter. Then Ollama and OpenRouter become thin config entries in the Factory.

### Phase 1: Make OpenAIAdapter Base-URL Configurable

**File:** `lib/prompt_objects/llm/openai_adapter.rb`

```ruby
def initialize(api_key: nil, model: nil, base_url: nil)
  @api_key = api_key || ENV.fetch("OPENAI_API_KEY") { raise Error, "..." }
  @model = model || DEFAULT_MODEL
  @client = OpenAI::Client.new(
    access_token: @api_key,
    uri_base: base_url  # nil = default OpenAI endpoint
  )
end
```

The `ruby-openai` gem supports `uri_base` for custom endpoints. This is the only change needed in the adapter itself.

### Phase 2: Add Ollama Provider

**File:** `lib/prompt_objects/llm/factory.rb`

Add to `PROVIDERS`:
```ruby
"ollama" => {
  adapter: "OpenAIAdapter",
  env_key: nil,  # No API key needed for local Ollama
  default_model: "llama3.2",
  models: [],  # Dynamic — populated from Ollama API
  base_url: "http://localhost:11434/v1",
  api_key_default: "ollama"  # Ollama ignores this but OpenAI client requires it
}
```

**Dynamic model discovery:** Ollama exposes `GET /api/tags` which lists installed models. Add a `discover_models` class method to Factory:

```ruby
def self.discover_ollama_models(base_url = "http://localhost:11434")
  response = Net::HTTP.get(URI("#{base_url}/api/tags"))
  data = JSON.parse(response)
  data["models"].map { |m| m["name"] }
rescue
  []  # Ollama not running or unreachable
end
```

**Factory#create changes:** Support `base_url` and `api_key_default` in provider config:

```ruby
def create(provider: nil, model: nil, api_key: nil)
  config = PROVIDERS[provider_name]
  raise Error, "Unknown provider" unless config

  # Resolve API key: explicit > env var > default
  resolved_key = api_key || (config[:env_key] && ENV[config[:env_key]]) || config[:api_key_default]

  adapter_class = LLM.const_get(config[:adapter])
  adapter_class.new(
    api_key: resolved_key,
    model: model || config[:default_model],
    base_url: config[:base_url]
  )
end
```

**Availability check:** Ollama availability should ping the local server, not check for an API key:

```ruby
def available_providers
  PROVIDERS.transform_values do |config|
    if config[:env_key].nil?
      # Local provider — check if server is reachable
      check_local_provider(config[:base_url])
    else
      ENV.key?(config[:env_key])
    end
  end
end

def check_local_provider(base_url)
  return false unless base_url
  uri = URI("#{base_url.sub('/v1', '')}/api/tags")
  Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
rescue
  false
end
```

### Phase 3: Add OpenRouter Provider

**File:** `lib/prompt_objects/llm/factory.rb`

```ruby
"openrouter" => {
  adapter: "OpenAIAdapter",
  env_key: "OPENROUTER_API_KEY",
  default_model: "meta-llama/llama-3.3-70b-instruct",
  models: %w[
    meta-llama/llama-3.3-70b-instruct
    meta-llama/llama-4-scout
    meta-llama/llama-4-maverick
    mistralai/mistral-large-2411
    google/gemma-3-27b-it
    deepseek/deepseek-r1
    qwen/qwen-2.5-72b-instruct
  ],
  base_url: "https://openrouter.ai/api/v1"
}
```

OpenRouter uses the standard OpenAI chat completions format. The only addition is optional HTTP headers for attribution:

```ruby
# In OpenAIAdapter, add optional headers support
def initialize(api_key: nil, model: nil, base_url: nil, extra_headers: nil)
  @client = OpenAI::Client.new(
    access_token: @api_key,
    uri_base: base_url,
    extra_headers: extra_headers
  )
end
```

Provider config can include:
```ruby
extra_headers: {
  "HTTP-Referer" => "https://github.com/prompt-objects",
  "X-Title" => "PromptObjects"
}
```

### Phase 4: Update Web UI

**File:** `frontend/src/components/Header.tsx` (or LLM switcher component)

The existing LLM switcher already shows providers and models from the `llm_config` WebSocket message. Changes needed:

1. **Show Ollama status:** Indicate whether Ollama is reachable (green/red dot)
2. **Dynamic model list for Ollama:** Add a WebSocket message `get_ollama_models` that triggers `discover_ollama_models` and returns the list
3. **Provider grouping:** Group the dropdown into "Cloud" (OpenAI, Anthropic, Gemini, OpenRouter) and "Local" (Ollama)

### Phase 5: Handle Ollama Tool Calling Limitations

Not all Ollama models support tool calling. The system should:

1. **Detect capability:** When switching to an Ollama model, check if it supports tools (Ollama's `/api/show` endpoint reports capabilities)
2. **Graceful degradation:** If no tool support, POs can still converse but can't call capabilities. Show a warning in the UI.
3. **Prompt adaptation:** For models without tool calling, could inject tool descriptions into the system prompt and parse structured output. This is a future enhancement.

## Files to Modify

| File | Change |
|------|--------|
| `lib/prompt_objects/llm/openai_adapter.rb` | Add `base_url` and `extra_headers` params |
| `lib/prompt_objects/llm/factory.rb` | Add ollama/openrouter providers, dynamic model discovery, local provider availability check |
| `lib/prompt_objects/server/websocket_handler.rb` | Add `get_ollama_models` handler |
| `frontend/src/components/Header.tsx` | Provider grouping, Ollama status indicator |
| `test/unit/llm/factory_test.rb` | Tests for new providers, availability checks |
| `test/unit/llm/openai_adapter_test.rb` | Tests for base_url configuration |

## Testing

- Unit tests: Factory creates adapters with correct base_url for each provider
- Unit tests: Ollama model discovery (mock HTTP response)
- Unit tests: Availability check for local vs cloud providers
- Integration: Switch to Ollama from web UI, send message, verify response
- Integration: Switch to OpenRouter, verify tool calling works

## Cost Consideration

OpenRouter provides per-model pricing via their API (`/api/v1/models`). This could feed into the token usage tracking feature — OpenRouter responses include `usage` data and we can look up the cost per token from their model list.

Ollama is free (local compute).
