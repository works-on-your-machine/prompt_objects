# Frontend Redesign: Smalltalk System Browser

## The Problem With the Current Design

The current UI is a **chat app wearing a dark theme**. Purple accents on blue-black, chat bubbles with "You"/"AI" avatars, a sidebar of threads — this is the same visual language as every AI wrapper since ChatGPT. It communicates: "this is a chatbot." But PromptObjects isn't a chatbot. It's a **live runtime of autonomous objects communicating through message passing**. The UI should make you feel like you're peering into a running system, not typing into a text box.

## Design Philosophy: The Object Browser

In Smalltalk, the System Browser is the center of the universe. You don't "chat with" an object — you **inspect** it, **browse** its methods, **evaluate** expressions in its context, and **watch** it interact with other objects. The Transcript shows you the system's heartbeat. Every window is a lens into the same living image.

PromptObjects maps perfectly:

| Smalltalk | PromptObjects |
|-----------|---------------|
| Class categories | PO list |
| Method list | Capabilities |
| Source pane | Prompt/identity (markdown) |
| Workspace | Conversation thread |
| Transcript | Message bus |
| Inspector | PO detail (state, sessions, config) |

The redesign should feel like an **IDE for a living system**, not a messenger app.

## Aesthetic Direction: "Warm Machine"

Not cold blue-purple AI. Not clinical white IDE. Something in between — **warm, dense, professional, alive.**

Think: the amber phosphor glow of a terminal, but with the spatial clarity of a modern IDE. A system that feels like it has **warmth and weight** — like a piece of well-made equipment, not a SaaS product.

**Tone keywords**: Utilitarian. Warm. Dense. Precise. Alive.

**What it's NOT**: Glassy. Gradient-heavy. Purple. Bubbly. Chat-like.

## Color System

Moving from cold purple-on-blue-black to warm neutrals with amber as the signal color:

```
Background layers (warm charcoal):
  --surface-0: #1a1918    (deepest — page bg)
  --surface-1: #222120    (panels, cards)
  --surface-2: #2c2a28    (elevated — inputs, dropdowns)
  --surface-3: #363432    (highest — hover states, active)

Borders:
  --border:       #3d3a37  (default)
  --border-focus: #5c5752  (focused/active)

Text (warm grays, not blue-tinted):
  --text-0: #e8e2da    (primary — warm off-white)
  --text-1: #a8a29a    (secondary)
  --text-2: #78726a    (tertiary/disabled)
  --text-3: #524e48    (ghost/placeholder)

Accent (amber/gold — the color of "something is happening"):
  --accent:       #d4952a  (primary — warm amber)
  --accent-muted: #9a6d20  (backgrounds, borders)
  --accent-wash:  rgba(212, 149, 42, 0.08)  (tinted backgrounds)

Status:
  --status-idle:    #78726a  (warm gray — quiet)
  --status-active:  #d4952a  (amber — working)
  --status-calling: #3b9a6e  (sage green — tool call in flight)
  --status-error:   #c45c4a  (warm red — not neon)
  --status-delegated: #5a8fc2 (steel blue — handed off)
```

The amber accent is key. It's the color of signal lights, status indicators, caution tape — **the system is telling you something**. When a PO is thinking, the amber pulses. When a message traverses the bus, amber particles flow. It makes the system feel alive without the coldness of purple or blue.

## Typography

**Display/UI**: **"Geist"** (by Vercel) — geometric, technical, extremely legible at small sizes, not overused. If Geist isn't available or feels too trendy, **"Instrument Sans"** is a distinctive alternative with slightly more personality.

**Monospace**: **"Geist Mono"** or **"IBM Plex Mono"** — for capabilities, JSON, tool names, the system prompt editor, code blocks. This is the "voice of the system." It should feel like reading a terminal or source file.

**Scale** (tighter than typical — Smalltalk UIs are dense):
- `--text-2xs`: 10px — timestamps, metadata
- `--text-xs`: 11px — bus messages, capability params
- `--text-sm`: 12px — most body text, lists
- `--text-base`: 13px — primary content
- `--text-lg`: 15px — section headers
- `--text-xl`: 18px — panel titles

The density matters. Smalltalk browsers pack information in. We should too. This isn't a marketing site — it's a tool.

## Layout Architecture: The Browser

Replace sidebar+main with a **multi-pane browser layout**:

```
┌──────────────────────────────────────────────────────────────────────┐
│ SYSTEM BAR (32px)                                                    │
│  ● PromptObjects  │  env: my-project  │  claude-haiku-4-5 ▾  │  ◉ │
├────────────┬─────────────────────────────────────────────────────────┤
│            │                                                         │
│  OBJECT    │  ┌─ INSPECTOR ──────────────────────────────────────┐  │
│  LIST      │  │                                                   │  │
│            │  │  ┌─────────────┬──────────────────────────────┐  │  │
│  ● solver  │  │  │ METHODS     │  SOURCE                      │  │  │
│    reader  │  │  │             │                              │  │  │
│    coord.  │  │  │ read_file   │  # Solver                   │  │  │
│            │  │  │ list_files  │  ## Identity                 │  │  │
│  ┄┄┄┄┄┄┄┄ │  │  │ grid_info   │  You are a careful,         │  │  │
│  Status    │  │  │ render_grid │  methodical problem solver   │  │  │
│  ┄┄┄┄┄┄┄┄ │  │  │ ...         │  who approaches ARC-AGI     │  │  │
│  idle      │  │  │             │  puzzles...                  │  │  │
│  thinking… │  │  ├─────────────┴──────────────────────────────┤  │  │
│  idle      │  │  │ WORKSPACE                                  │  │  │
│            │  │  │                                             │  │  │
│            │  │  │  Thread: solving-abc123  ▾                  │  │  │
│            │  │  │                                             │  │  │
│            │  │  │  > Analyze the training pairs...            │  │  │
│            │  │  │                                             │  │  │
│            │  │  │  I'll examine each pair systematically...   │  │  │
│            │  │  │  ┌ grid_info({grid: [[1,0,0]...]}) ───┐    │  │  │
│            │  │  │  │ rows: 3, cols: 3, colors: {0: 6..} │    │  │  │
│            │  │  │  └────────────────────────────────────┘    │  │  │
│            │  │  │                                             │  │  │
│            │  │  │  [                                    ▸ ]   │  │  │
│            │  │  └─────────────────────────────────────────────┘  │  │
│            │  └───────────────────────────────────────────────────┘  │
├────────────┴─────────────────────────────────────────────────────────┤
│ TRANSCRIPT (collapsible, ~120px)                                     │
│  14:23:07  solver → grid_info  {grid: [[1,0,2...]]}                 │
│  14:23:07  grid_info → solver  {rows: 3, cols: 3, colors: ...}      │
│  14:23:08  solver → render_grid  {grid: [[1,0,2...]], label: "in"} │
│  14:23:09  solver → coordinator  {message: "Found pattern..."}      │
└──────────────────────────────────────────────────────────────────────┘
```

### Key Layout Changes

1. **System Bar** replaces Header — thinner (32px vs 56px), denser, more like a window title bar / IDE status bar. Environment and model are just text, not decorated elements.

2. **Object List** replaces Dashboard sidebar — always visible, compact, shows all POs with live status indicators. Not cards — just a tight list, like the class list in a Smalltalk browser. Status dots pulse live. Active PO highlighted with amber left border.

3. **Inspector** replaces PODetail — the selected PO is "inspected." The inspector has sub-panes:
   - **Methods** (top-left): Capability list, dense, monospace, clickable. Like the method list in a System Browser.
   - **Source** (top-right): The PO's markdown prompt. Live-editable, like editing a method in Smalltalk. Monospace, syntax-highlighted markdown.
   - **Workspace** (bottom): The conversation. This is where you interact with the PO. Thread selector is a dropdown, not a sidebar. Tool calls render inline as collapsible blocks (like debugger frames), not chat bubbles.

4. **Transcript** replaces MessageBus — always visible at the bottom (collapsible). This is the Smalltalk Transcript — the heartbeat of the system. Dense, monospace, timestamped, color-coded by type. Not a sidebar you toggle — it's always there, watching.

## Component Language

### Messages Are Not Chat Bubbles

They're **workspace entries** — like a REPL. User input is prefixed with `>`, like a prompt. Assistant responses are just text (no avatar circles, no colored backgrounds). Tool calls are collapsible frames with monospace content. The workspace reads like a transcript of work, not a conversation.

```
> Analyze the first training pair and describe the transformation.

I'll start by examining the input and output grids.

┌ grid_info({grid: input_grid}) ──────────────────────────
│ rows: 5, cols: 5
│ colors: {0: 15, 1: 4, 2: 6}
│ non_background: 10
└─────────────────────────────────────────────────────────

┌ render_grid({grid: input_grid, label: "Input"}) ───────
│ Input
│ 5x5
│     0  1  2  3  4
│    ----------
│  0|  .  1  .  .  2
│  1|  .  1  1  .  2
│ ...
└─────────────────────────────────────────────────────────

The input shows two distinct colored regions...
```

### PO Status Indicators

Small but prominent:
- **Idle**: dim warm-gray dot
- **Thinking**: amber dot, pulsing glow
- **Calling tool**: green dot, with the tool name shown inline (`→ grid_info`)
- **Delegated**: blue dot, with the delegating PO name (`← solver`)

### Notifications

`ask_human` notifications don't float — they appear as amber-bordered frames in the workspace area, inline with the conversation. Also highlighted in the Transcript. When you click it, you respond right there — no modal.

### Thread Selector

A compact dropdown in the inspector header, not a full sidebar. Shows thread name, type icon, and message count. Thread management (new, rename, delete) lives in a popover from this dropdown.

## What Changes vs. What Stays

### Changes
- Dashboard card grid → Object List (compact, always-visible)
- Chat bubbles with avatars → Workspace with REPL-style entries
- Purple accent everywhere → Amber as signal color on warm neutrals
- Floating notification panel → Inline workspace interrupts
- Thread sidebar → Compact dropdown in workspace header
- Generic system fonts → Geist / Geist Mono
- Sidebar toggle buttons → Persistent multi-pane layout
- 56px header → 32px system bar

### Stays
- Zustand store architecture (same shape, same selectors)
- WebSocket connection and event handling
- All existing data types and state shape
- Three.js canvas view (separate concern, already distinct)
- Model selector (just restyled)
- Capabilities/Prompt data (just presented differently)

## Key Interactions

1. **Click PO in Object List** → Inspector opens/switches to that PO (like clicking a class in Smalltalk browser)
2. **Click capability in Methods pane** → SourcePane shows the capability's definition and parameter schema
3. **Edit Source pane** → Auto-saves with debounce, like Smalltalk's accept (Cmd+S)
4. **Type in Workspace** → Send message to PO in current thread context (Enter to send)
5. **Transcript click** → Clicking a message in the transcript selects the relevant PO
6. **Thread dropdown** → Switch between threads, create new ones
