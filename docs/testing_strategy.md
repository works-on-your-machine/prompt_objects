# Testing Strategy

## Overview

This document outlines the testing approach for PromptObjects to ensure reliability and catch regressions early. The goal is to minimize manual testing and trial-and-error debugging by having comprehensive automated tests.

## Problem Statement

During development, we've encountered bugs that could have been caught by basic tests:
- Method signature mismatches (`update_session` missing `last_message_source:` parameter)
- Missing methods (`capability_names` didn't exist on PromptObject)
- SQL/database errors (FTS `snippet()` function misuse)

These issues required manual testing via Claude Desktop integration, which is slow and error-prone.

## Testing Pyramid

```
         /\
        /  \        E2E (manual for now)
       /----\
      /      \      Integration Tests
     /--------\
    /          \    Unit Tests (primary focus)
   /--------------\
```

**Unit Tests** (80% of tests): Test individual methods and classes in isolation
**Integration Tests** (20%): Test component interactions and workflows
**E2E Tests**: Manual testing for TUI and full system flows (future: automate)

## Test Directory Structure

```
test/
├── test_helper.rb              # Common setup, mocks, helpers
├── unit/
│   ├── session/
│   │   └── store_test.rb       # Session CRUD, search, export/import
│   ├── connectors/
│   │   └── mcp_tools_test.rb   # Each MCP tool in isolation
│   ├── prompt_object_test.rb   # PO public interface
│   ├── registry_test.rb        # Registry operations
│   └── primitives/
│       └── *_test.rb           # Each primitive
├── integration/
│   ├── mcp_server_test.rb      # Full JSON-RPC protocol flow
│   ├── session_flow_test.rb    # Session lifecycle
│   └── po_communication_test.rb # PO calling other POs
└── fixtures/
    ├── objects/                # Test prompt object .md files
    └── environments/           # Test environment directories
```

## Key Components to Test

### Priority 1: High (Core functionality, external interfaces)

| Component | Test File | What to Test |
|-----------|-----------|--------------|
| Session::Store | `unit/session/store_test.rb` | CRUD, FTS search, export/import, schema migrations |
| MCP Tools | `unit/connectors/mcp_tools_test.rb` | Each tool's input validation, response format, error handling |
| PromptObject | `unit/prompt_object_test.rb` | Public interface methods, history management, session binding |

### Priority 2: Medium (Important but simpler)

| Component | Test File | What to Test |
|-----------|-----------|--------------|
| Connectors::Base | `unit/connectors/base_test.rb` | Session creation helper, source tracking |
| Registry | `unit/registry_test.rb` | Registration, lookup, capability resolution |
| Primitives | `unit/primitives/*_test.rb` | Input/output, error handling |

### Priority 3: Lower (Complex to test, lower ROI)

| Component | Notes |
|-----------|-------|
| TUI App | Hard to test rendering, consider testing models only |
| LLM interactions | Require extensive mocking, test adapters in isolation |

## Mock Strategy

### MockLLM Adapter

Returns predictable responses without API calls:

```ruby
class MockLLM
  attr_reader :calls

  def initialize(responses: [])
    @responses = responses
    @calls = []
    @call_index = 0
  end

  def chat(messages:, tools: nil)
    @calls << { messages: messages, tools: tools }
    response = @responses[@call_index] || default_response
    @call_index += 1
    response
  end

  private

  def default_response
    PromptObjects::LLM::Response.new(
      content: "Mock response",
      tool_calls: []
    )
  end
end
```

### In-Memory SQLite

Fast, isolated database for each test:

```ruby
def setup
  @store = PromptObjects::Session::Store.new(":memory:")
end
```

### Temporary Environments

For integration tests that need full environment structure:

```ruby
def with_temp_env
  Dir.mktmpdir do |dir|
    # Create manifest, objects dir, etc.
    yield dir
  end
end
```

## Test Patterns

### Testing MCP Tools

Each tool should be tested in isolation with a mock server context:

```ruby
def test_list_prompt_objects
  runtime = create_test_runtime_with_pos(["po1", "po2"])
  ctx = { env: runtime, context: runtime.context, connector: nil }

  result = ListPromptObjects.call(server_context: ctx)
  data = JSON.parse(result.content.first[:text])

  assert_equal 2, data["prompt_objects"].length
  assert data["prompt_objects"].all? { |po| po.key?("capabilities") }
end
```

### Testing Session Store

Test each method, including edge cases:

```ruby
def test_update_session_with_all_parameters
  id = @store.create_session(po_name: "test", name: "Original")

  @store.update_session(id,
    name: "Updated",
    last_message_source: "mcp",
    metadata: { key: "value" }
  )

  session = @store.get_session(id)
  assert_equal "Updated", session[:name]
  assert_equal "mcp", session[:last_message_source]
end
```

### Testing PromptObject Interface

Verify the public contract:

```ruby
def test_prompt_object_has_required_methods
  po = create_test_po

  # These should all exist and work
  assert_respond_to po, :name
  assert_respond_to po, :description
  assert_respond_to po, :config
  assert_respond_to po, :history
  assert_respond_to po, :receive
end
```

## Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby -Itest test/unit/session/store_test.rb

# Run specific test method
bundle exec ruby -Itest test/unit/session/store_test.rb -n test_create_session
```

## CI Integration (Future)

GitHub Actions workflow to run on every push:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle exec rake test
```

## Coverage Goals

| Component | Target Coverage |
|-----------|-----------------|
| Session::Store | 90% |
| MCP Tools | 100% |
| PromptObject | 80% |
| Primitives | 100% |
| Overall | 70% |

## Test-Driven Development

For new features:
1. Write failing test that describes expected behavior
2. Implement minimal code to pass test
3. Refactor if needed
4. Commit with both test and implementation

This ensures:
- Requirements are clear before coding
- Regressions are caught immediately
- Documentation via executable examples

## What NOT to Test (Initially)

- TUI rendering output (visual, hard to assert)
- Complex multi-turn LLM conversations (too many variables)
- Performance/load testing (premature optimization)
- External service integration (use mocks instead)

## Maintenance

- Run tests before every commit
- Add tests when fixing bugs (regression prevention)
- Review test coverage monthly
- Prune flaky or low-value tests
