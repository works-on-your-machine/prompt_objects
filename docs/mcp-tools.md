# MCP Server Tools Reference

The PromptObjects MCP server exposes these tools for clients (Go TUI, Claude Desktop, etc.).

## Tools

### list_prompt_objects

List all loaded prompt objects with their current state.

**Parameters:** None

**Returns:**
```json
[
  {
    "name": "coordinator",
    "description": "Coordinates between specialists",
    "state": "idle",
    "capabilities": ["greeter", "reader", "list_files"]
  }
]
```

### send_message

Send a message to a prompt object and get its response.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `po_name` | string | yes | Name of the PO to message |
| `message` | string | yes | The message to send |

**Returns:**
```json
{
  "po_name": "coordinator",
  "response": "Hello! How can I help?",
  "history_length": 2
}
```

### get_conversation

Get conversation history for a prompt object.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `po_name` | string | yes | Name of the PO |
| `limit` | integer | no | Max messages to return |

**Returns:**
```json
{
  "po_name": "coordinator",
  "message_count": 4,
  "history": [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi there!"}
  ]
}
```

### inspect_po

Get detailed information about a prompt object.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `po_name` | string | yes | Name of the PO to inspect |

**Returns:**
```json
{
  "name": "coordinator",
  "description": "Coordinates between specialists",
  "state": "idle",
  "config": { ... },
  "capabilities": {
    "universal": ["ask_human", "think", "add_capability"],
    "primitives": ["list_files", "http_get"],
    "delegates": ["greeter", "reader"]
  },
  "prompt_body": "# Coordinator\n\nYou are a coordinator...",
  "history_length": 0
}
```

### get_pending_requests

Get all pending human requests across all POs.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `po_name` | string | no | Filter to specific PO |

**Returns:**
```json
{
  "count": 1,
  "requests": [
    {
      "id": "uuid-here",
      "capability": "coordinator",
      "question": "Should I proceed?",
      "options": ["Yes", "No"],
      "age": "2m",
      "created_at": "2024-01-03T12:00:00Z"
    }
  ]
}
```

### respond_to_request

Respond to a pending human request (unblocks the waiting PO).

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `request_id` | string | yes | ID from get_pending_requests |
| `response` | string | yes | Your response |

**Returns:**
```json
{
  "success": true,
  "request_id": "uuid-here",
  "capability": "coordinator",
  "question": "Should I proceed?",
  "response": "Yes"
}
```

## Resources

The server also exposes these MCP resources:

| URI | Description |
|-----|-------------|
| `po://{name}/conversation` | Conversation history as JSON |
| `po://{name}/config` | PO configuration as JSON |
| `po://{name}/prompt` | Raw markdown prompt body |
| `bus://messages` | Recent message bus entries |

## Running the Server

```bash
# Stdio transport (for TUI, Claude Desktop)
ruby exe/prompt_objects_mcp

# With custom objects directory
PROMPT_OBJECTS_DIR=/path/to/objects ruby exe/prompt_objects_mcp
```

## Claude Desktop Configuration

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "prompt-objects": {
      "command": "ruby",
      "args": ["/path/to/prompt-objects/exe/prompt_objects_mcp"],
      "env": {
        "PROMPT_OBJECTS_DIR": "/path/to/objects"
      }
    }
  }
}
```
