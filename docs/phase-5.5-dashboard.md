# Phase 5.5-5.6: Mouse Support & Dashboard Grid View

## Overview

Extended TUI features building on the core Phase 5 implementation:
- **Phase 5.5**: Mouse support foundation
- **Phase 5.6**: Dashboard grid view with PO cards

---

## Phase 5.5: Mouse Support Foundation

### Enable Mouse Tracking

```ruby
# In App.run
Bubbletea.run(app, alt_screen: true, mouse: true)
```

### Handle MouseMessage

```ruby
def update(msg)
  case msg
  when Bubbletea::MouseMessage
    handle_mouse(msg)
  # ...
  end
end

def handle_mouse(msg)
  case
  when msg.left? && msg.press?
    handle_click(msg.x, msg.y)
  when msg.wheel?
    handle_scroll(msg)
  when msg.motion?
    handle_hover(msg.x, msg.y)
  end
end
```

### Clickable Regions

Track clickable areas with a simple hit-test system:

```ruby
class ClickRegion
  attr_reader :x, :y, :width, :height, :action, :data

  def contains?(px, py)
    px >= x && px < x + width && py >= y && py < y + height
  end
end

# In App
@click_regions = []

def register_click_region(x:, y:, width:, height:, action:, data: nil)
  @click_regions << ClickRegion.new(x, y, width, height, action, data)
end

def handle_click(x, y)
  region = @click_regions.find { |r| r.contains?(x, y) }
  return unless region

  case region.action
  when :select_po
    handle_select_po(region.data)
  when :open_inspector
    # ...
  end
end
```

### Mouse-Enabled Components

1. **Capability Bar**: Click PO to select
2. **Conversation Panel**: Click to focus, scroll wheel to scroll
3. **Message Log**: Scroll wheel support
4. **Modals**: Click buttons, scroll content
5. **Input**: Click to position cursor

---

## Phase 5.6: Dashboard Grid View

### Layout Modes

```ruby
MODE_DASHBOARD = :dashboard  # Grid of all POs
MODE_FOCUSED = :focused      # Current single-PO view
```

Toggle with `Tab` or click "Dashboard" button.

### Dashboard Layout

```
┌─ PromptObjects Dashboard ──────────────────────────────────────────┐
│                                                                     │
│  ┌─ coordinator ─┐  ┌─ greeter ──────┐  ┌─ researcher ──┐         │
│  │ Orchestrates  │  │ Friendly       │  │ Finds info    │         │
│  │ tasks...      │  │ welcome...     │  │ online...     │         │
│  │               │  │                │  │               │         │
│  │ ● 3 messages  │  │ ○ idle         │  │ ◐ working     │         │
│  │ [Chat] [Info] │  │ [Chat] [Info]  │  │ [Chat] [Info] │         │
│  └───────────────┘  └────────────────┘  └───────────────┘         │
│                                                                     │
│  ┌─ coder ───────┐  ┌─ reviewer ─────┐  ┌─ + New PO ────┐         │
│  │ Writes code   │  │ Reviews PRs    │  │               │         │
│  │ snippets...   │  │ and code...    │  │     (+)       │         │
│  │               │  │                │  │               │         │
│  │ ○ idle        │  │ ○ idle         │  │  Create new   │         │
│  │ [Chat] [Info] │  │ [Chat] [Info]  │  │               │         │
│  └───────────────┘  └────────────────┘  └───────────────┘         │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ [Tab] Focus view  [n] New PO  [/] Search  [q] Quit     6 POs total │
└─────────────────────────────────────────────────────────────────────┘
```

### PO Card Component

**File**: `lib/prompt_objects/ui/models/po_card.rb`

```ruby
class POCard
  CARD_WIDTH = 18
  CARD_HEIGHT = 7

  attr_reader :po, :x, :y, :selected, :hovered

  def view
    lines = []
    border_style = selected ? Styles.card_selected :
                   hovered ? Styles.card_hovered :
                   Styles.card_normal

    # Title
    title = truncate(po.name, CARD_WIDTH - 4)
    lines << border_style.render("┌─ #{title} #{'─' * (CARD_WIDTH - title.length - 5)}┐")

    # Description (2 lines)
    desc_lines = wrap_text(po.description, CARD_WIDTH - 4)
    lines << "│ #{pad(desc_lines[0], CARD_WIDTH - 4)} │"
    lines << "│ #{pad(desc_lines[1] || '', CARD_WIDTH - 4)} │"

    # Empty line
    lines << "│ #{' ' * (CARD_WIDTH - 4)} │"

    # Status
    status = format_status(po)
    lines << "│ #{status}#{' ' * (CARD_WIDTH - 4 - visible_length(status))} │"

    # Actions
    actions = "[Chat] [Info]"
    lines << "│ #{actions}#{' ' * (CARD_WIDTH - 4 - actions.length)} │"

    # Bottom border
    lines << border_style.render("└#{'─' * (CARD_WIDTH - 2)}┘")

    lines.join("\n")
  end

  def format_status(po)
    icon = case po.state
           when :working then "◐"
           when :waiting_for_human then "◑"
           else "○"
           end

    msg_count = po.history.length
    if msg_count > 0
      "#{icon} #{msg_count} messages"
    else
      "#{icon} idle"
    end
  end
end
```

### Grid Layout Manager

**File**: `lib/prompt_objects/ui/models/grid_layout.rb`

```ruby
class GridLayout
  def initialize(width:, height:, card_width:, card_height:, gap: 2)
    @width = width
    @height = height
    @card_width = card_width
    @card_height = card_height
    @gap = gap
  end

  def columns
    (@width / (@card_width + @gap)).to_i.clamp(1, 6)
  end

  def rows
    ((@height - 4) / (@card_height + @gap)).to_i.clamp(1, 10)
  end

  def visible_count
    columns * rows
  end

  def card_position(index)
    col = index % columns
    row = index / columns

    x = col * (@card_width + @gap) + 2
    y = row * (@card_height + @gap) + 2

    { x: x, y: y }
  end
end
```

### Dashboard Model

**File**: `lib/prompt_objects/ui/models/dashboard.rb`

```ruby
class Dashboard
  def initialize(registry:)
    @registry = registry
    @grid = GridLayout.new(...)
    @scroll_offset = 0
    @selected_index = 0
    @hovered_index = nil
  end

  def view(width, height)
    @grid = GridLayout.new(width: width, height: height, ...)

    pos = visible_pos
    lines = Array.new(height) { " " * width }

    pos.each_with_index do |po, i|
      card = POCard.new(po: po,
                        selected: i == @selected_index,
                        hovered: i == @hovered_index)
      pos = @grid.card_position(i)
      render_card_at(lines, card, pos[:x], pos[:y])
    end

    lines.join("\n")
  end

  def visible_pos
    all = @registry.prompt_objects
    start = @scroll_offset * @grid.columns
    all[start, @grid.visible_count] || []
  end

  # Navigation
  def move_left
    @selected_index = [@selected_index - 1, 0].max
  end

  def move_right
    @selected_index = [@selected_index + 1, visible_pos.length - 1].min
  end

  def move_up
    @selected_index = [@selected_index - @grid.columns, 0].max
  end

  def move_down
    @selected_index = [@selected_index + @grid.columns, visible_pos.length - 1].min
  end

  # Mouse
  def handle_hover(x, y)
    @hovered_index = card_at(x, y)
  end

  def handle_click(x, y)
    index = card_at(x, y)
    return unless index

    @selected_index = index

    # Check if click was on [Chat] or [Info] button
    button = button_at(x, y, index)
    case button
    when :chat then :open_chat
    when :info then :open_inspector
    else :select
    end
  end
end
```

---

## Keyboard Shortcuts

### Dashboard Mode
| Key | Action |
|-----|--------|
| `Tab` | Switch to focused mode |
| `h/j/k/l` | Navigate grid |
| `Arrow keys` | Navigate grid |
| `Enter` | Open chat with selected PO |
| `i` | Open inspector for selected |
| `n` | Create new PO |
| `/` | Search/filter POs |
| `q` | Quit |

### Focused Mode
| Key | Action |
|-----|--------|
| `Tab` | Switch to dashboard |
| `h/l` | Switch PO (same as before) |
| `i` | Enter insert mode |
| `I` | Open inspector |
| `e` | Open editor |
| `q` | Quit |

## Mouse Actions

| Action | Result |
|--------|--------|
| Click PO card | Select PO |
| Double-click card | Open chat (focused mode) |
| Click [Chat] button | Open chat |
| Click [Info] button | Open inspector |
| Click [+] card | Create new PO |
| Scroll wheel | Scroll grid / conversation |
| Hover card | Highlight, show tooltip |

---

## Implementation Order

### Phase 5.5 (Mouse)
1. **5.5a**: Enable mouse tracking, basic click handling
2. **5.5b**: Clickable capability bar
3. **5.5c**: Scroll wheel in conversation/message log

### Phase 5.6 (Dashboard)
4. **5.6a**: Dashboard model with grid layout
5. **5.6b**: PO card component
6. **5.6c**: Mode switching (Tab key)
7. **5.6d**: Mouse click on cards

### Phase 5.7 (Polish)
8. **5.7a**: Hover effects
9. **5.7b**: Search/filter
10. **5.7c**: View transitions

## File Changes

```
lib/prompt_objects/ui/
├── app.rb                    # Add mouse handling, mode switching
├── click_region.rb           # NEW: Hit testing (5.5)
├── models/
│   ├── dashboard.rb          # NEW: Dashboard grid view (5.6)
│   ├── po_card.rb            # NEW: Individual PO card (5.6)
│   ├── grid_layout.rb        # NEW: Grid positioning (5.6)
│   └── search_overlay.rb     # NEW: Search modal (5.7)
└── styles.rb                 # Add card styles, hover states
```

## Future Ideas

- Drag and drop to reorder POs
- Right-click context menu
- PO grouping/folders
- Minimap for large collections
- Touch support (if terminal supports)
