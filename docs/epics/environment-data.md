# Environment Data (Stigmergy)

## Overview

Enable POs to place data into a shared environment space, with other POs (or humans) able to watch for and react to that data. This creates a stigmergic communication model where coordination happens through the environment rather than direct messaging.

## Motivation

- **Loose coupling**: POs don't need to know about each other to collaborate
- **Event-driven**: POs react to data appearing, not direct requests
- **Extensibility**: External systems can inject data into the environment
- **Persistence**: Data persists in the environment for later processing
- **Human visibility**: Humans can see all data flowing through the system

## Core Concepts

### Environment Data Store

A shared space where POs can:
- **Place** data (write)
- **Watch** for data matching patterns (subscribe)
- **Query** existing data (read)
- **React** to data and produce responses

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Environment Data Store                    │
│                                                             │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │
│  │ task:1  │  │ email:* │  │result:1 │  │ alert:* │       │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘       │
└───────┼───────────┼───────────┼───────────┼───────────────┘
        │           │           │           │
        ▼           ▼           ▼           ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
   │ Worker  │ │ Email   │ │ Summary │ │ Alert   │
   │   PO    │ │ Handler │ │   PO    │ │ Handler │
   └─────────┘ └─────────┘ └─────────┘ └─────────┘
```

### Data Entry

```ruby
DataEntry = Struct.new(
  :id,              # UUID
  :type,            # String, e.g., "task", "email", "result"
  :key,             # Optional specific key, e.g., "task:123"
  :data,            # Hash or structured data
  :source,          # Who created it: PO name, "human", "external:email"
  :created_at,
  :expires_at,      # Optional TTL
  :metadata,        # Tags, priority, etc.
  keyword_init: true
)
```

---

## Capabilities

### place_data

Place data into the environment for others to observe.

```ruby
# PO calls:
place_data(
  type: "task",
  key: "review_pr_123",
  data: {
    action: "review",
    repo: "myproject",
    pr_number: 123,
    priority: "high"
  },
  metadata: { tags: ["code", "urgent"] }
)
```

### watch_data

Subscribe to data matching a pattern. When matching data appears, the PO receives a notification.

```ruby
# PO declares in frontmatter or calls:
watch_data(
  pattern: "task:*",           # Watch all tasks
  filter: { priority: "high" }, # Optional filter
  handler: :on_new_task        # Method to call (or inline block)
)

# When data arrives:
def on_new_task(entry)
  # Process the task
  # Optionally place result data
end
```

### query_data

Query existing data in the environment.

```ruby
# PO calls:
query_data(type: "result", limit: 10)
query_data(pattern: "email:*", since: 1.hour.ago)
query_data(source: "email_watcher")
```

### respond_to_data

Place a response/result linked to original data.

```ruby
# PO calls:
respond_to_data(
  original_id: entry.id,
  type: "result",
  data: {
    status: "completed",
    output: "PR looks good, approved."
  }
)
```

---

## Watch Patterns

### Pattern Syntax

```ruby
"task:*"              # All tasks
"task:review_*"       # Tasks starting with "review_"
"email:inbox:*"       # Emails in inbox
"*:urgent"            # Anything marked urgent
```

### Filter Options

```ruby
watch_data(
  pattern: "task:*",
  filter: {
    priority: "high",
    tags: { includes: "code" },
    source: { not: "self" }  # Don't react to own data
  }
)
```

---

## PO Configuration

### Frontmatter Watches

```yaml
---
name: code_reviewer
capabilities:
  - read_file
  - place_data
watches:
  - pattern: "task:review_*"
    filter: { type: "pull_request" }
  - pattern: "code:analyze_*"
---
```

### Reactive Behavior

When watched data arrives, the PO's prompt can include instructions:

```markdown
## When You Receive Data

When you receive a `task:review_*` entry:
1. Fetch the PR details using the provided info
2. Review the code changes
3. Place your review as a `result:review_*` entry

When you receive `code:analyze_*`:
1. Read the specified files
2. Analyze for issues
3. Place findings as `result:analysis_*`
```

---

## Implementation Architecture

### DataStore

```ruby
class DataStore
  def initialize(env_path)
    @db = SQLite3::Database.new(File.join(env_path, "data.db"))
    @subscribers = {}  # pattern => [callbacks]
  end

  def place(type:, key: nil, data:, source:, metadata: {}, expires_at: nil)
    entry = create_entry(...)
    persist(entry)
    notify_subscribers(entry)
    entry
  end

  def watch(pattern:, filter: nil, &block)
    @subscribers[pattern] ||= []
    @subscribers[pattern] << { filter: filter, callback: block }
  end

  def query(type: nil, pattern: nil, since: nil, limit: 100)
    # Query from SQLite
  end

  private

  def notify_subscribers(entry)
    @subscribers.each do |pattern, handlers|
      next unless matches?(entry, pattern)
      handlers.each do |handler|
        next unless passes_filter?(entry, handler[:filter])
        handler[:callback].call(entry)
      end
    end
  end
end
```

### Integration with Runtime

```ruby
class Runtime
  def initialize(...)
    @data_store = DataStore.new(env_path)
    setup_po_watches
  end

  def setup_po_watches
    registry.prompt_objects.each do |po|
      po.watches.each do |watch_config|
        @data_store.watch(
          pattern: watch_config[:pattern],
          filter: watch_config[:filter]
        ) do |entry|
          # Queue for PO processing
          po.receive_data(entry)
        end
      end
    end
  end
end
```

---

## External Data Sources (Future)

### Ingestion Patterns

```
External World          Environment
     │                      │
     ▼                      ▼
┌─────────┐  place_data  ┌───────────┐
│ Email   │─────────────▶│ email:*   │──▶ Email Handler PO
│ Watcher │              └───────────┘
└─────────┘
                         ┌───────────┐
┌─────────┐  place_data  │ schedule: │
│  Cron   │─────────────▶│   *       │──▶ Scheduler PO
│ Runner  │              └───────────┘
└─────────┘
                         ┌───────────┐
┌─────────┐  place_data  │ webhook:  │
│ Webhook │─────────────▶│   *       │──▶ Webhook Handler PO
│  Server │              └───────────┘
└─────────┘
```

### External Adapters (Future Epic)

```ruby
# Email watcher (runs as separate process or scheduled)
class EmailWatcher
  def check
    new_emails.each do |email|
      env.data_store.place(
        type: "email",
        key: "inbox:#{email.id}",
        data: {
          from: email.from,
          subject: email.subject,
          body: email.body,
          received_at: email.date
        },
        source: "external:email"
      )
    end
  end
end
```

---

## TUI Integration

### Data Panel

New panel (or tab) showing data flow:

```
┌─ Environment Data ──────────────────────────────────┐
│                                                     │
│  → task:review_123        code_reviewer    2m ago  │
│  ← result:review_123      code_reviewer    1m ago  │
│  → email:inbox:456        external:email   5m ago  │
│  → task:summarize         coordinator      just now│
│                                                     │
├─────────────────────────────────────────────────────┤
│ [d] Details  [f] Filter  [q] Close                 │
└─────────────────────────────────────────────────────┘
```

### Data Inspector

View details of a data entry:

```
┌─ Data: task:review_123 ─────────────────────────────┐
│                                                     │
│  Type: task                                         │
│  Source: coordinator                                │
│  Created: 2025-01-06 10:30:00                      │
│                                                     │
│  Data:                                              │
│  {                                                  │
│    "action": "review",                              │
│    "repo": "myproject",                             │
│    "pr_number": 123,                                │
│    "priority": "high"                               │
│  }                                                  │
│                                                     │
│  Watchers: code_reviewer, qa_checker                │
│  Responses: result:review_123                       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Step 1: DataStore Core
- SQLite schema for data entries
- Basic CRUD operations
- Pattern matching for queries

### Step 2: Universal Capabilities
- `place_data` capability
- `query_data` capability
- `respond_to_data` capability

### Step 3: Watch System
- Subscription management
- Pattern matching engine
- Filter evaluation

### Step 4: PO Integration
- Frontmatter `watches` configuration
- `receive_data` method on PromptObject
- Automatic watch setup in Runtime

### Step 5: TUI Data Panel
- Data flow visualization
- Data inspector modal
- Filter/search

### Step 6: External Adapters (Future)
- Adapter interface
- Email watcher
- Webhook receiver
- Scheduled checks

---

## Open Questions

1. Should data have schemas/types or be freeform?
2. How to handle data retention/cleanup?
3. Should humans be able to place data via TUI?
4. How to handle PO "overload" from too many data events?
5. Should there be data transformation/routing POs?

---

## Future Enhancements

- **Data Schemas**: Define expected structure for data types
- **Data Routing**: Rules for directing data to specific POs
- **Data Pipelines**: Chain of POs processing data sequentially
- **External Publish**: Push data to external systems
- **Data Visualization**: Graphs/charts of data flow
- **Replay**: Re-process historical data through POs
