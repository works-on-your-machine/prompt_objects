# Spatial Canvas — Real-Time Environment Visualization

**Status**: Ready
**Priority**: High
**Depends on**: Web Server Infrastructure (Complete), Web UI (In Progress — no blockers)
**Route**: `/canvas`

---

## Overview

A Three.js 2D spatial visualization that renders a live, zoomable view of an environment's prompt objects, their communication topology, tool calls, and activity state. This is a peer view to the existing dashboard/chat UI — a separate route optimized for monitoring, understanding system behavior, and demoing.

The existing web UI answers **"what do I want to say to this PO?"** — it's conversational, one-PO-at-a-time. The canvas answers **"what is the system doing right now?"** — it's spatial, showing everything simultaneously.

### What the canvas makes visible that the chat view cannot

- **Parallelism and fan-out**: When a coordinator decomposes a task and spins up three workers, you *see* three nodes bloom outward simultaneously. The shape of work becomes legible.
- **Communication topology**: Which POs talk to each other, how often, who's central, who's isolated. Edges *are* the communication.
- **Activity at a glance**: All POs visible simultaneously — pulsing when active, dimmed when idle, alert markers when waiting for human input.
- **Lifecycle**: POs created at runtime animate into existence. You see the system grow.
- **Tool call chains as visible paths**: A message hops across nodes with a visual trail. Causal chains become spatial journeys.

---

## Aesthetic Direction: Neural Observatory

**Tone**: Bioluminescent deep-sea meets mission control. The visualization should feel like watching a living nervous system — organic, breathing, alive. Not a mechanical dashboard with boxes and arrows, but a luminous ecosystem.

**The unforgettable moment**: A coordinator PO pulses in the center, receives a complex task, and three new nodes bloom outward from it simultaneously — like cell division — each trailing luminous connections back. Message particles flow along the edges like synaptic impulses. One node hits a problem, its glow shifts to amber, an exclamation mark floats above it. You click it, respond to its question, and it resumes — the whole system breathing again.

### Color Palette

Built on the existing `po-*` palette, extended for the canvas:

```
Background:         #0a0a12  (deeper than po-bg, space-like)
Background grain:   subtle noise texture at 2-3% opacity

PO Node (idle):     #4a6fa5 → #3d5c8a  (cool steel blue, low glow)
PO Node (thinking): #b87f3a → #d4962e  (warm amber, pulsing)
PO Node (calling):  #7c3aed → #9061f9  (accent purple, bright pulse)
PO Node (waiting):  #f59e0b             (warning amber, breathing)

Tool Call:          #0ea5a0 → #14b8a6  (teal, ephemeral bloom)
Tool Success:       #22c55e             (flash, then fade)
Tool Error:         #ef4444             (flash, then fade)

Message Arc:        #e8e0d4 at 60%     (warm white particles)
Arc Trail:          #7c3aed at 30%     (accent glow trail)

Alert Badge:        #f59e0b             (amber exclamation)
Alert Pulse:        #f59e0b at 20%     (expanding ring)

Panel Chrome:       #1a1a2e / po-surface with backdrop-blur
Panel Border:       #2d2d44 / po-border
Panel Text:         #e8e0d4 (warm off-white, not pure white)
```

### Typography

Scene labels and panel UI use distinctive fonts loaded via Google Fonts:

- **Display / headings**: `"Darker Grotesque"` — condensed, characterful, slightly unsettling in a good way. Used for PO names in the scene and panel headers.
- **Body / data**: `"Overpass Mono"` — clean monospace with a technical, slightly rounded feel. Used for tool names, parameters, timestamps.
- **Panel prose**: `"Overpass"` — the sans-serif sibling, readable at body sizes. Used for descriptions and prompt text.

Three.js text rendering uses `CSS2DRenderer` to overlay HTML elements on the scene, so web fonts work naturally.

### Motion Language

- **Easing**: Organic curves everywhere. `cubic-bezier(0.34, 1.56, 0.64, 1)` for spring-like arrivals. `ease-out` for fades. No linear motion.
- **Breathing**: Idle nodes have a subtle scale oscillation (0.98–1.02) on a slow sine wave, offset per node so they don't synchronize.
- **Pulses**: Activity changes trigger a ring that expands outward and fades — like a ripple in water.
- **Particles**: Message particles travel along cubic bezier arcs with slight random wobble. 3-5 particles per message, staggered by ~80ms.
- **Bloom/fade**: Tool call nodes scale from 0 → 1 with overshoot easing on creation, then scale 1 → 0 with fade on completion. Duration ~400ms in, ~600ms out.
- **Node entry**: New POs scale from 0 and drift outward from their creator with a spring curve. Duration ~800ms.

---

## Technical Architecture

### Rendering Stack

```
┌──────────────────────────────────────────────────┐
│  React Component (<CanvasView />)                 │
│  ├── Three.js WebGLRenderer  (effects, particles)│
│  ├── CSS2DRenderer overlay   (labels, badges)     │
│  └── React side panel        (inspector, editor)  │
└──────────────────────────────────────────────────┘
         │                           │
         ▼                           ▼
┌──────────────────┐    ┌──────────────────────────┐
│  d3-force         │    │  Zustand Store            │
│  (layout sim)     │    │  (same store as chat UI)  │
└──────────────────┘    └──────────────────────────┘
```

**Why vanilla Three.js (not R3F)**: This is a 2D visualization with custom shaders, particle systems, and tight animation control. R3F's declarative model adds overhead without benefit here. A single React component manages the Three.js lifecycle via refs.

**Why d3-force for layout**: Proven force simulation with configurable forces. The simulation runs in a `requestAnimationFrame` loop alongside Three.js rendering, feeding updated positions to the scene graph.

**Why CSS2DRenderer for labels**: HTML elements positioned in scene-space give us web fonts, proper text rendering, and easy click handling without raycasting for text. The Three.js scene handles visual effects (glows, particles, arcs) while CSS2D handles text and badges.

### Camera

Orthographic camera for true 2D (no perspective distortion):

```typescript
const frustumSize = 1000
const aspect = width / height
camera = new THREE.OrthographicCamera(
  -frustumSize * aspect / 2, frustumSize * aspect / 2,
  frustumSize / 2, -frustumSize / 2,
  0.1, 2000
)
camera.position.z = 500
```

Zoom: adjust `camera.zoom` (scroll wheel). Pan: translate camera position (mouse drag on empty space).

### Post-Processing

Subtle bloom pass (UnrealBloomPass) on the WebGL layer for glow effects:

```typescript
const bloomPass = new UnrealBloomPass(
  new THREE.Vector2(width, height),
  0.4,   // strength (subtle)
  0.6,   // radius
  0.85   // threshold (only bright things bloom)
)
```

This makes node glows and message particles feel luminous without overwhelming the scene.

---

## Scene Elements

### PO Nodes

**Geometry**: Hexagonal shape (6-sided `CircleGeometry` or custom `Shape`). Hex feels more intentional than a circle — suggests structure, like a cell or tile.

**Material**: Custom shader with:
- Base color determined by status
- Inner glow (radial gradient from center)
- Edge highlight (subtle lighter ring at border)
- Pulse amplitude driven by activity level

**Size**: Base radius ~30 scene units. Scales slightly with importance (number of connections or recent message volume). Never smaller than 0.7x or larger than 1.4x base.

**Visual states**:

| Status | Color | Glow | Animation |
|--------|-------|------|-----------|
| idle | Steel blue | Low, steady | Slow breathing (scale oscillation) |
| thinking | Warm amber | Medium, pulsing | Ring ripple every ~2s |
| calling_tool | Accent purple | Bright, active | Quick pulse on each tool call |
| waiting (ask_human) | Warning amber | Bright, urgent | Continuous expanding ring + exclamation badge |

**Label**: CSS2D element below the node. PO name in Darker Grotesque, status text below in Overpass Mono at smaller size. Opacity fades at extreme zoom-out levels to reduce clutter.

### Tool Call Nodes

**Geometry**: Diamond (rotated square) or pill (rounded rect). Smaller than PO nodes (~15 unit radius). Diamond for tool calls, pill for tool results.

**Lifecycle**:
1. **Bloom**: Appears near its parent PO node. Scales from 0 → 1 with spring easing. Connected to parent PO by a short edge.
2. **Active**: Subtle spinner/rotation animation while the call is pending. Teal color with gentle glow.
3. **Complete**: Flash green (success) or red (error). Hold for ~400ms. Then scale down and fade out over ~600ms.

**Persistence**: Tool call nodes remain visible for ~3 seconds after completion so you can click them. After that they fade completely. A "trail" of recent tool calls could persist as small dots near the PO for a configurable time.

**Label**: Tool name in Overpass Mono. Shows briefly, fades with the node.

### Message Arcs

When a bus_message event fires (PO → PO or PO → tool), an animated arc connects the source and target:

**Path**: Quadratic bezier curve. Control point perpendicular to the midpoint, offset by ~30% of the distance. Direction alternates (up/down) to avoid overlapping when two POs are chatting back and forth.

**Particles**: 3-5 small circles (radius ~2) travel along the bezier path, staggered by ~80ms. Each particle has a small glow trail (rendered as a short line segment in the direction of travel). Warm white color with accent glow.

**Lifetime**: Particles travel the full arc in ~600-1000ms (depending on distance). The arc path itself renders as a faint line that fades after all particles have traversed it.

**Bidirectional traffic**: If two POs are actively exchanging messages, you'd see particles flowing in both directions along slightly offset arcs. The visual effect is a conversation — pulses going back and forth.

### Notification Badges

For POs in `waiting` state (ask_human pending):

**Badge**: A floating CSS2D element above the PO node — amber circle with white `!` exclamation mark. Positioned ~40 units above the node center.

**Pulse**: An expanding ring animation behind the badge (CSS `@keyframes` — a circle that scales from 1x to 2x and fades from 40% to 0% opacity, repeating every 1.5s).

**Click**: Clicking the badge opens the inspector panel in ask_human response mode. The badge disappears when the human responds.

**Multiple notifications**: If a PO has multiple pending requests, show a count badge (e.g., "3") instead of just "!".

### Background

- Solid deep color (#0a0a12)
- Subtle dot grid at very low opacity (3-4%) — gives spatial reference when panning without being distracting
- Optional: very faint radial gradient from center (slightly lighter) to suggest the "gravity well" that active nodes drift toward

---

## Layout System

### Force Simulation (d3-force)

```typescript
const simulation = d3.forceSimulation(nodes)
  .force('charge', d3.forceManyBody()
    .strength(-300)              // Nodes repel each other
  )
  .force('center', d3.forceCenter(0, 0)
    .strength(0.03)              // Weak general centering
  )
  .force('link', d3.forceLink(links)
    .distance(200)               // Edge rest length
    .strength(0.3)               // Edge pull strength
  )
  .force('collision', d3.forceCollide()
    .radius(60)                  // Prevent overlap
  )
  .force('activity', activityForce())  // Custom: active → center
  .alphaDecay(0.01)              // Slow cooldown for smooth settling
  .velocityDecay(0.4)            // Damping
```

### Activity Gravity (Custom Force)

A custom d3 force that pulls active nodes toward the center and lets idle nodes drift outward:

```typescript
function activityForce() {
  let nodes: SimNode[]

  function force(alpha: number) {
    for (const node of nodes) {
      const activityLevel = getActivityLevel(node) // 0 = idle, 1 = very active
      const centerPull = 0.02 + activityLevel * 0.08
      // Pull toward center proportional to activity
      node.vx! -= node.x! * centerPull * alpha
      node.vy! -= node.y! * centerPull * alpha
    }
  }

  force.initialize = (n: SimNode[]) => { nodes = n }
  return force
}
```

**Activity level** is derived from:
- Status: `idle` = 0, `thinking` = 0.6, `calling_tool` = 0.8
- Recent message volume: messages in last 10 seconds add 0.1 per message (capped at 0.4)
- Activity decays over ~15 seconds of inactivity

### Link Generation

Links (edges in the force simulation) are derived from bus_message history:

```typescript
// Build links from recent bus messages
function deriveLinks(busMessages: BusMessage[], promptObjects: string[]): Link[] {
  const linkMap = new Map<string, { source: string, target: string, weight: number }>()

  for (const msg of recentMessages(busMessages, 60)) { // last 60 seconds
    // Only PO-to-PO links (not PO-to-tool)
    if (promptObjects.includes(msg.from) && promptObjects.includes(msg.to)) {
      const key = [msg.from, msg.to].sort().join('↔')
      const existing = linkMap.get(key)
      if (existing) {
        existing.weight++
      } else {
        linkMap.set(key, { source: msg.from, target: msg.to, weight: 1 })
      }
    }
  }

  return Array.from(linkMap.values())
}
```

Links that haven't had traffic in >60 seconds fade out and are removed from the simulation. Links with higher weight (more messages) render as thicker, brighter lines.

### Node Pinning

When a user drags a node, it becomes "pinned" — its position is fixed in the simulation (`fx`, `fy` set). A small pin icon appears. Double-click to unpin.

---

## Interaction

### Zoom & Pan

- **Scroll wheel**: Zoom in/out. Adjusts `camera.zoom`. Smooth tweened transition (~200ms).
- **Mouse drag on empty space**: Pan the camera. Updates `camera.position.x/y`.
- **Pinch gesture**: Zoom (for trackpad users).
- **Minimap** (optional, lower-right corner): Small overview showing all nodes and the current viewport rectangle. Click to jump.

### Zoom Levels

| Zoom Level | What's Visible |
|-----------|---------------|
| Far out (< 0.3x) | PO nodes as colored dots, no labels, thick aggregate edges |
| Normal (0.5–1.5x) | PO nodes with names, tool calls visible, message arcs animate |
| Close up (> 2x) | Full labels, PO descriptions visible, tool call names, parameter previews |

Labels and detail elements fade in/out based on zoom level to prevent clutter.

### Click Interactions

**Click PO node** → Opens the inspector side panel for that PO. The panel slides in from the right (~380px wide). Contents:
- PO name and status
- Capabilities list (same data as CapabilitiesPanel)
- Current prompt (viewable and editable, with save — reuses PromptPanel logic)
- Active session / recent messages (compact view)
- If PO has notifications: ask_human response form at the top

**Click tool call node** → Opens the inspector panel with tool call details:
- Tool name
- Parameters (JSON, syntax highlighted)
- Status (pending / success / error)
- Result (if completed — full content, syntax highlighted)
- Duration

**Click notification badge** → Opens inspector panel directly in ask_human mode:
- Shows the PO's request message
- Option buttons for predefined responses
- Text input for custom response
- Submit sends `respondToNotification` via WebSocket

**Click empty space** → Closes the inspector panel.

### Hover

- **PO node**: Glow intensity increases. Cursor becomes pointer. Connected edges brighten.
- **Tool call node**: Slight scale-up. Tooltip with tool name + status.
- **Message arc**: The arc brightens. Tooltip shows from → to and timestamp.

---

## Inspector Side Panel

The panel slides in from the right edge, overlaying the canvas (canvas stays visible and animating behind it). Width: 380px. Uses the existing `po-surface` background with `backdrop-blur-xl`.

### Panel Modes

**PO Inspector**:
```
┌─────────────────────────────────┐
│  ✕                               │
│  ⬡ reader                       │  ← Hex icon + PO name
│  Helps people understand files   │  ← Description
│  ● thinking                      │  ← Status with dot
│                                  │
│  ▸ Notifications (2)             │  ← If has ask_human pending
│    ┌─ Request ──────────────┐   │
│    │ Create src/utils.rb?    │   │
│    │ [Yes] [No] [________]  │   │
│    └────────────────────────┘   │
│                                  │
│  ▸ Capabilities                  │  ← Expandable
│    read_file                     │
│    list_files                    │
│    write_file                    │
│                                  │
│  ▸ Prompt                        │  ← Expandable, editable
│    # Reader                      │
│    You are a careful, thoughtful │
│    file reader...                │
│    [Edit] [Save]                 │
│                                  │
│  ▸ Recent Activity               │  ← Last few messages
│    12:01 → list_files(src/)     │
│    12:01 ← [src/main.rb, ...]   │
│    12:02 User: What files?       │
│    12:02 Reader: I found...      │
│                                  │
└─────────────────────────────────┘
```

**Tool Call Inspector**:
```
┌─────────────────────────────────┐
│  ✕                               │
│  ◇ read_file                     │  ← Diamond icon + tool name
│  Called by: reader               │
│  Status: ✓ completed (340ms)     │
│                                  │
│  Parameters                      │
│  ┌────────────────────────────┐ │
│  │ {                           │ │
│  │   "path": "src/main.rb"    │ │
│  │ }                           │ │
│  └────────────────────────────┘ │
│                                  │
│  Result                          │
│  ┌────────────────────────────┐ │
│  │ # Main entry point          │ │
│  │ require 'prompt_objects'    │ │
│  │ ...                         │ │
│  └────────────────────────────┘ │
│                                  │
└─────────────────────────────────┘
```

---

## Data Flow

The canvas consumes the **same WebSocket feed** as the existing chat UI. No backend changes needed.

### WebSocket Event → Visual Effect Mapping

| WS Event | Visual Effect |
|----------|--------------|
| `po_state` | Update node color/glow/animation. If new PO, create node with bloom animation. |
| `po_added` | Create new PO node. Animate in from center or from parent if known. |
| `po_removed` | Fade and shrink node out. Remove from simulation. |
| `bus_message` | Create message arc + particles between `from` and `to` nodes. Update link weights. |
| `stream` | Intensify target PO's glow. Show streaming indicator on node. |
| `stream_end` | Reduce glow back to status-based level. |
| `notification` | Show alert badge above PO node. Start pulse animation. |
| `notification_resolved` | Remove alert badge. Brief green flash. |
| `po_state.status = 'calling_tool'` | Create tool call node near PO. Show call name. |
| `po_state.status = 'idle'` (after calling) | Complete tool call node — flash success/error, fade out. |

### Canvas-Specific Store Extensions

The canvas needs a small amount of additional state beyond the shared store:

```typescript
// New slice in Zustand store (or separate canvas store)
interface CanvasState {
  // Node positions (managed by d3-force, mirrored for React)
  nodePositions: Record<string, { x: number, y: number }>

  // Pinned nodes (user-dragged to fixed position)
  pinnedNodes: Set<string>
  pinNode: (name: string, x: number, y: number) => void
  unpinNode: (name: string) => void

  // Active tool calls (ephemeral, for rendering tool call nodes)
  activeToolCalls: ToolCallNode[]
  addToolCall: (call: ToolCallNode) => void
  completeToolCall: (id: string, success: boolean) => void
  removeToolCall: (id: string) => void

  // Message arcs (ephemeral, for rendering animated arcs)
  messageArcs: MessageArc[]
  addMessageArc: (arc: MessageArc) => void
  removeMessageArc: (id: string) => void

  // Canvas-specific selection (separate from main selectedPO to avoid interference)
  canvasSelectedNode: { type: 'po' | 'tool', id: string } | null
  setCanvasSelectedNode: (node: CanvasState['canvasSelectedNode']) => void

  // Zoom/pan state
  zoom: number
  panOffset: { x: number, y: number }
}

interface ToolCallNode {
  id: string
  toolName: string
  callerPO: string
  params: Record<string, unknown>
  status: 'pending' | 'success' | 'error'
  result?: string
  startedAt: number
  completedAt?: number
}

interface MessageArc {
  id: string
  from: string
  to: string
  timestamp: number
  content?: string
}
```

---

## Component Structure

```
frontend/src/
├── components/
│   ├── canvas/
│   │   ├── CanvasView.tsx          # Main container: Three.js + panel + controls
│   │   ├── SceneManager.ts         # Three.js scene lifecycle (init, animate, dispose)
│   │   ├── ForceLayout.ts          # d3-force simulation setup and update
│   │   ├── nodes/
│   │   │   ├── PONodeMesh.ts       # Hex geometry, shader material, glow
│   │   │   ├── ToolCallMesh.ts     # Diamond geometry, lifecycle animations
│   │   │   └── NodeLabel.ts        # CSS2D label creation and management
│   │   ├── edges/
│   │   │   ├── MessageArc.ts       # Bezier arc geometry and particle system
│   │   │   └── LinkLine.ts         # Persistent PO-to-PO connection lines
│   │   ├── effects/
│   │   │   ├── GlowShader.ts       # Custom glow shader material
│   │   │   ├── PulseRing.ts        # Expanding ring animation for activity
│   │   │   └── ParticleTrail.ts    # Message particle trail effect
│   │   ├── interaction/
│   │   │   ├── CameraControls.ts   # Zoom, pan, gesture handling
│   │   │   └── NodeDrag.ts         # Drag-to-pin interaction
│   │   ├── InspectorPanel.tsx      # Side panel container (React)
│   │   ├── POInspector.tsx         # PO detail panel content
│   │   ├── ToolCallInspector.tsx   # Tool call detail panel content
│   │   └── CanvasControls.tsx      # Zoom buttons, minimap toggle, legend
│   └── ... (existing components)
├── hooks/
│   ├── useWebSocket.ts             # Existing (shared)
│   └── useCanvasEvents.ts          # Maps WS events to canvas-specific actions
├── store/
│   ├── index.ts                    # Existing (shared)
│   └── canvas.ts                   # Canvas-specific state slice
└── ...
```

### Key File Responsibilities

**CanvasView.tsx** — React component that owns the canvas element. On mount, initializes SceneManager. Subscribes to store changes and forwards them to the scene. Renders the inspector panel overlay when a node is selected. Handles keyboard shortcuts (Escape to deselect, +/- to zoom).

**SceneManager.ts** — Pure TypeScript class (no React). Manages the Three.js scene, camera, renderers, and animation loop. Exposes methods like `addPONode()`, `removePONode()`, `updateNodeStatus()`, `triggerMessageArc()`, `addToolCall()`. The React component calls these methods in response to store changes.

**ForceLayout.ts** — Wraps d3-force simulation. Accepts node and link data, runs the simulation, and calls back with updated positions each tick. The animation loop in SceneManager reads positions from here and updates mesh positions.

**useCanvasEvents.ts** — A hook that subscribes to the Zustand store (bus_messages, po_state changes, notifications) and translates them into canvas-specific actions (triggerMessageArc, addToolCall, showNotificationBadge). This is the bridge between the shared data layer and the canvas-specific visual effects.

---

## Implementation Phases

### Phase 1: Scene Foundation

**Goal**: Three.js scene renders in a React component. PO nodes appear as glowing hexagons. Camera zoom and pan work. Force layout positions nodes.

**Tasks**:
- [ ] Set up Three.js scene with OrthographicCamera and WebGLRenderer
- [ ] Add CSS2DRenderer for labels
- [ ] Implement CameraControls (zoom wheel, pan drag)
- [ ] Create PONodeMesh with basic hex geometry and glow shader
- [ ] Set up d3-force simulation with charge + center + collision forces
- [ ] Wire up Zustand store — render a PONodeMesh for each PO in the store
- [ ] Add node labels (PO name + status) via CSS2DRenderer
- [ ] Background with subtle dot grid
- [ ] Add UnrealBloomPass for glow

**Exit criteria**: Navigate to `/canvas`, see hexagonal PO nodes with names, zoom in/out, pan around. Nodes settle into a force-directed layout.

### Phase 2: Activity & State Visualization

**Goal**: Nodes visually respond to PO state changes. The scene feels alive.

**Tasks**:
- [ ] Implement status-based color transitions (idle → thinking → calling_tool)
- [ ] Add breathing animation for idle nodes
- [ ] Add pulse ring effect for active nodes
- [ ] Implement activity-based gravity (active → center, idle → outward)
- [ ] Streaming indicator (subtle particle emission from node during stream)
- [ ] Glow intensity responds to activity level
- [ ] Zoom-level-dependent label detail (fade out at extreme zoom-out)

**Exit criteria**: Send a message to a PO via the chat UI. Switch to canvas. See the PO glow shift to amber/purple as it thinks/calls tools, then return to blue when idle. Active nodes drift toward center.

### Phase 3: Message Arcs & Tool Calls

**Goal**: Communication between POs and tool usage becomes visible as animated arcs and ephemeral nodes.

**Tasks**:
- [ ] Implement MessageArc with bezier path and particle system
- [ ] Trigger arcs from bus_message events
- [ ] Implement persistent link lines between POs that communicate (weight-based thickness)
- [ ] Create ToolCallMesh (diamond geometry, bloom/fade lifecycle)
- [ ] Wire tool call lifecycle to po_state changes
- [ ] Tool call success/error flash
- [ ] Tool call persistence (visible for ~3s after completion)
- [ ] Link generation from bus_message history

**Exit criteria**: Watch two POs exchange messages and see particles arc between them. See tool calls bloom near their parent PO, spin while pending, flash green/red on completion, and fade.

### Phase 4: Inspector Panel

**Goal**: Click any node to inspect it. Respond to notifications. Edit prompts.

**Tasks**:
- [ ] Implement click detection (raycaster for meshes, click handler for CSS2D elements)
- [ ] Build InspectorPanel container with slide-in animation
- [ ] Build POInspector (capabilities, prompt view/edit, recent activity)
- [ ] Build ToolCallInspector (params, result, duration)
- [ ] Wire prompt editing to existing `updatePrompt` WebSocket method
- [ ] Add ask_human notification badge (CSS2D element above PO node)
- [ ] Notification pulse animation
- [ ] Notification response form in inspector panel
- [ ] Click badge → opens inspector in notification mode
- [ ] Hover effects (glow increase, cursor change, edge highlighting)
- [ ] Click empty space → close panel

**Exit criteria**: Click a PO, see its capabilities and prompt, edit the prompt and save. Trigger an ask_human, see the exclamation badge appear, click it, respond, see it resolve.

### Phase 5: PO Lifecycle & Polish

**Goal**: New POs animate into existence. Node dragging works. Visual polish pass.

**Tasks**:
- [ ] Animate new PO creation (bloom from center or parent)
- [ ] Animate PO removal (shrink and fade)
- [ ] Node drag to pin position
- [ ] Pin indicator + double-click to unpin
- [ ] Zoom controls overlay (+ / - buttons, fit-all button)
- [ ] Keyboard shortcuts (Escape to deselect, F to fit all nodes in view)
- [ ] Performance optimization (instanced rendering if node count > 20)
- [ ] Canvas-specific header or breadcrumb (environment name, node count, link to dashboard)
- [ ] Legend/key overlay (what colors and shapes mean)
- [ ] Responsive canvas sizing (window resize handling)

**Exit criteria**: Full workflow — start environment, watch POs appear on canvas, send messages, see arcs, inspect nodes, respond to notifications, edit prompts. Smooth at 60fps with 10 POs and active message traffic.

### Phase 6: Parallel Processing Visualization (Future)

**Goal**: When parallel PO execution lands in the backend, visualize fan-out/fan-in patterns.

**Tasks**:
- [ ] Detect parallel spawning events (coordinator creates multiple POs simultaneously)
- [ ] Starburst animation: new nodes bloom outward from parent in a radial pattern
- [ ] Fan-in visualization: result messages converging back to coordinator
- [ ] Work-tree view: trace the decomposition structure of a complex task
- [ ] Timeline scrubber (replay the evolution of the scene over time)

This phase depends on backend parallel execution support landing first.

---

## Dependencies

### New npm packages:

```json
{
  "three": "^0.170.0",
  "d3-force": "^3.0.0",
  "@types/three": "^0.170.0",
  "@types/d3-force": "^3.0.0"
}
```

Three.js addons (imported from `three/addons/`):
- `CSS2DRenderer` — HTML labels in 3D space
- `UnrealBloomPass` — glow post-processing
- `EffectComposer` — post-processing pipeline
- `RenderPass` — base render pass

### No backend changes needed

The canvas is purely a frontend view consuming existing WebSocket events. The same `useWebSocket` hook (or a shared connection instance) feeds both the dashboard and the canvas.

---

## Routing

Add `/canvas` as a sibling route to the existing dashboard. The simplest approach given the current architecture (no router — Zustand-based navigation):

```typescript
// In App.tsx or a lightweight router
type View = 'dashboard' | 'canvas'

// Navigation between views
// Header gets a toggle or tab to switch between Dashboard and Canvas
```

Alternatively, add `react-router-dom` if routing complexity grows. For now, a simple view toggle in the store is sufficient.

---

## Open Questions

1. **Shared WebSocket connection**: The current `useWebSocket` hook creates a connection per component mount. If dashboard and canvas are sibling routes, we need a shared connection that persists across view switches. Consider lifting the WS connection to a top-level provider or using a Zustand middleware.

2. **Performance with many tool calls**: A PO that makes 20 rapid tool calls could spawn 20 diamond nodes in quick succession. May need to aggregate or throttle tool call node creation. One option: only show the most recent N tool calls per PO.

3. **Mobile/tablet**: Three.js works on mobile but the interaction model (hover, right-click) doesn't translate. Not a priority but worth noting that canvas is primarily a desktop experience.

4. **Accessibility**: Three.js canvas is opaque to screen readers. The CSS2D overlay helps somewhat (real HTML elements). The inspector panel is fully accessible. Consider an ARIA live region that announces significant events.

5. **Canvas ↔ Chat navigation**: Should clicking "View in Chat" from the canvas inspector navigate to the chat UI for that PO? And vice versa — a "View in Canvas" link from the chat view? This creates a nice bidirectional workflow.

---

## Non-Goals (For Now)

- 3D depth / perspective (keep it flat 2D)
- Saving/loading canvas layouts to disk
- Recording or replaying visualizations as video
- Multiple canvases / split canvas views
- Collaborative viewing (multi-user same canvas)
- Environment-to-environment visualization
