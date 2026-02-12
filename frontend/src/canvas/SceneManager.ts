import * as THREE from 'three'
import { CSS2DRenderer } from 'three/addons/renderers/CSS2DRenderer.js'
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js'
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js'
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js'
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js'

import { ForceLayout } from './ForceLayout'
import { CameraControls } from './controls/CameraControls'
import { PONode } from './nodes/PONode'
import { ToolCallNode } from './nodes/ToolCallNode'
import { MessageArc } from './edges/MessageArc'
import { useCanvasStore } from './canvasStore'
import { COLORS, BLOOM, NODE } from './constants'
import type { PromptObject, BusMessage, Notification, ToolCall } from '../types'

export class SceneManager {
  private container: HTMLDivElement
  private scene: THREE.Scene
  private camera: THREE.OrthographicCamera
  private renderer: THREE.WebGLRenderer
  private cssRenderer: CSS2DRenderer
  private composer: EffectComposer
  private cameraControls: CameraControls
  private forceLayout: ForceLayout
  private raycaster: THREE.Raycaster
  private pointer: THREE.Vector2

  private poNodes = new Map<string, PONode>()
  private toolCallNodes = new Map<string, ToolCallNode>()
  private messageArcs = new Map<string, MessageArc>()

  private animationFrameId: number | null = null
  private clock = new THREE.Clock()
  private running = false

  // Track processed bus messages to avoid duplicates
  private processedArcIds = new Set<string>()

  // Track PO status transitions and tool calls
  private prevPOStatuses = new Map<string, string>()
  private seenToolCallIds = new Set<string>()
  // Map from PO name → set of tool call node IDs currently active for that PO
  private poToolCallNodes = new Map<string, Set<string>>()
  // Track active PO-to-PO delegations: tool_call_id → { callerPO, targetPO }
  private activeDelegations = new Map<string, { callerPO: string; targetPO: string }>()

  constructor(container: HTMLDivElement) {
    this.container = container
    const { width, height } = container.getBoundingClientRect()

    // Scene
    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(COLORS.background)

    // Orthographic camera (true 2D)
    const aspect = width / height
    const frustumSize = 500
    this.camera = new THREE.OrthographicCamera(
      (-frustumSize * aspect) / 2,
      (frustumSize * aspect) / 2,
      frustumSize / 2,
      -frustumSize / 2,
      0.1,
      1000
    )
    this.camera.position.z = 100

    // WebGL renderer
    this.renderer = new THREE.WebGLRenderer({ antialias: true })
    this.renderer.setSize(width, height)
    this.renderer.setPixelRatio(window.devicePixelRatio)
    container.appendChild(this.renderer.domElement)

    // CSS2D renderer (overlaid for labels)
    this.cssRenderer = new CSS2DRenderer()
    this.cssRenderer.setSize(width, height)
    this.cssRenderer.domElement.style.position = 'absolute'
    this.cssRenderer.domElement.style.top = '0'
    this.cssRenderer.domElement.style.left = '0'
    this.cssRenderer.domElement.style.pointerEvents = 'none'
    container.appendChild(this.cssRenderer.domElement)

    // Post-processing (bloom)
    this.composer = new EffectComposer(this.renderer)
    this.composer.addPass(new RenderPass(this.scene, this.camera))
    const bloomPass = new UnrealBloomPass(
      new THREE.Vector2(width, height),
      BLOOM.strength,
      BLOOM.radius,
      BLOOM.threshold
    )
    this.composer.addPass(bloomPass)
    this.composer.addPass(new OutputPass())

    // Camera controls
    this.cameraControls = new CameraControls(this.camera, this.renderer.domElement)

    // Force layout
    this.forceLayout = new ForceLayout()

    // Raycaster for picking
    this.raycaster = new THREE.Raycaster()
    this.pointer = new THREE.Vector2()

    // Event listeners
    this.renderer.domElement.addEventListener('click', this.onClick)
    this.renderer.domElement.addEventListener('pointermove', this.onPointerMove)
    window.addEventListener('resize', this.onResize)
  }

  // --- Public sync API ---

  syncPromptObjects(pos: Record<string, PromptObject>): void {
    const currentIds = new Set(this.poNodes.keys())
    const newIds = new Set(Object.keys(pos))

    // Remove nodes that no longer exist
    for (const id of currentIds) {
      if (!newIds.has(id)) {
        const node = this.poNodes.get(id)!
        this.scene.remove(node.group)
        node.dispose()
        this.poNodes.delete(id)
        this.forceLayout.removeNode(id)
        this.fadeOutToolCallsForPO(id)
        this.prevPOStatuses.delete(id)
      }
    }

    // Add or update nodes
    for (const [name, po] of Object.entries(pos)) {
      let node = this.poNodes.get(name)
      if (!node) {
        node = new PONode(name, name)
        this.poNodes.set(name, node)
        this.scene.add(node.group)
        this.forceLayout.addNode(name, 'po')
      }
      node.setStatus(po.status)

      // Detect status transitions for tool call visualization
      const prevStatus = this.prevPOStatuses.get(name)
      this.prevPOStatuses.set(name, po.status)

      if (po.status === 'calling_tool') {
        // PO is calling tools — extract any new tool_calls from its messages
        this.extractAndCreateToolCalls(name, po)
      } else if (prevStatus === 'calling_tool') {
        // PO just finished calling tools — fade out its tool call nodes
        this.fadeOutToolCallsForPO(name)
      }

      // Even when 'thinking', scan for tool calls we haven't seen yet.
      // The server often sends status back to 'thinking' between individual
      // tool calls in a multi-tool sequence, so we'd miss them if we only
      // check on the 'calling_tool' transition.
      if (po.status === 'thinking') {
        this.extractAndCreateToolCalls(name, po)
      }
    }
  }

  syncBusMessages(messages: BusMessage[]): void {
    for (const msg of messages) {
      const arcId = `${msg.from}-${msg.to}-${msg.timestamp}`
      if (this.processedArcIds.has(arcId)) continue
      this.processedArcIds.add(arcId)

      const fromNode = this.poNodes.get(msg.from)
      const toNode = this.poNodes.get(msg.to)
      if (!fromNode || !toNode) continue

      // Create arc for all PO-to-PO bus messages
      const arc = new MessageArc(
        arcId,
        msg.from,
        msg.to,
        fromNode.getPosition(),
        toNode.getPosition()
      )
      this.messageArcs.set(arcId, arc)
      this.scene.add(arc.group)
    }

    // Keep processed sets from growing unbounded
    if (this.processedArcIds.size > 500) {
      const ids = Array.from(this.processedArcIds)
      for (let i = 0; i < 200; i++) {
        this.processedArcIds.delete(ids[i])
      }
    }
    if (this.seenToolCallIds.size > 200) {
      const ids = Array.from(this.seenToolCallIds)
      for (let i = 0; i < 100; i++) {
        this.seenToolCallIds.delete(ids[i])
      }
    }
  }

  syncNotifications(notifications: Notification[]): void {
    // Count notifications per PO
    const counts = new Map<string, number>()
    for (const n of notifications) {
      counts.set(n.po_name, (counts.get(n.po_name) || 0) + 1)
    }

    // Update badges on all PO nodes
    for (const [name, node] of this.poNodes) {
      node.setNotificationCount(counts.get(name) || 0)
    }
  }

  fitAll(): void {
    if (this.poNodes.size === 0) return

    const bounds = new THREE.Box3()
    for (const node of this.poNodes.values()) {
      bounds.expandByPoint(node.getPosition())
    }

    // Expand bounds by node radius
    const padding = new THREE.Vector3(100, 100, 0)
    bounds.min.sub(padding)
    bounds.max.add(padding)

    this.cameraControls.fitAll(bounds)
  }

  // --- Tool call extraction ---

  private extractAndCreateToolCalls(poName: string, po: PromptObject): void {
    const messages = po.current_session?.messages
    if (!messages || messages.length === 0) return

    // Scan recent messages for tool_calls we haven't visualized yet,
    // and also for tool results to enrich existing tool call entries.
    const newToolCalls: ToolCall[] = []
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i]
      if (msg.role === 'assistant' && msg.tool_calls) {
        for (const tc of msg.tool_calls) {
          if (!this.seenToolCallIds.has(tc.id)) {
            newToolCalls.push(tc)
          }
        }
      }
      // Enrich with results from tool messages
      if (msg.role === 'tool' && msg.results) {
        for (const result of msg.results) {
          const tcNodeId = `tc-${result.tool_call_id}`
          if (this.toolCallNodes.has(tcNodeId)) {
            useCanvasStore.getState().updateToolCall(tcNodeId, {
              result: result.content,
              status: 'completed',
              completedAt: Date.now(),
            })
          }
        }
      }
      // Don't scan the entire history — last 10 messages is enough
      // (a multi-tool call can generate several messages)
      if (messages.length - 1 - i >= 10) break
    }

    if (newToolCalls.length === 0) return

    const callerNode = this.poNodes.get(poName)
    if (!callerNode) return
    const callerPos = callerNode.getPosition()

    // Get how many tool call nodes this PO already has (for offset positioning)
    let poTcSet = this.poToolCallNodes.get(poName)
    if (!poTcSet) {
      poTcSet = new Set()
      this.poToolCallNodes.set(poName, poTcSet)
    }

    for (const tc of newToolCalls) {
      this.seenToolCallIds.add(tc.id)

      // Check if this tool call targets another PO (delegation) vs a primitive
      const targetPONode = this.poNodes.get(tc.name)
      if (targetPONode) {
        // PO-to-PO call: activate the target PO visually and create a connecting arc
        targetPONode.setDelegatedBy(poName)
        this.activeDelegations.set(tc.id, { callerPO: poName, targetPO: tc.name })

        // Create a message arc from caller to target PO
        const arcId = `delegation-${tc.id}`
        if (!this.messageArcs.has(arcId)) {
          const arc = new MessageArc(
            arcId,
            poName,
            tc.name,
            callerNode.getPosition(),
            targetPONode.getPosition()
          )
          this.messageArcs.set(arcId, arc)
          this.scene.add(arc.group)
        }

        // Register in canvas store for inspector
        useCanvasStore.getState().addToolCall({
          id: `tc-${tc.id}`,
          toolName: `delegate → ${tc.name}`,
          callerPO: poName,
          params: tc.arguments,
          status: 'active',
          startedAt: Date.now(),
        })
      } else {
        // Primitive tool call: create a diamond ToolCallNode
        const existingCount = poTcSet.size
        const angle = (existingCount * (2 * Math.PI / 6)) - Math.PI / 2
        const offsetDist = NODE.poRadius + 40
        const offsetX = Math.cos(angle) * offsetDist
        const offsetY = Math.sin(angle) * offsetDist

        const tcNodeId = `tc-${tc.id}`
        const tcNode = new ToolCallNode(tcNodeId, tc.name, poName)
        tcNode.setPosition(callerPos.x + offsetX, callerPos.y + offsetY)

        this.toolCallNodes.set(tcNodeId, tcNode)
        this.scene.add(tcNode.group)
        poTcSet.add(tcNodeId)

        // Register in canvas store for inspector
        useCanvasStore.getState().addToolCall({
          id: tcNodeId,
          toolName: tc.name,
          callerPO: poName,
          params: tc.arguments,
          status: 'active',
          startedAt: Date.now(),
        })
      }
    }
  }

  private fadeOutToolCallsForPO(poName: string): void {
    const tcSet = this.poToolCallNodes.get(poName)
    if (tcSet) {
      for (const tcNodeId of tcSet) {
        const tcNode = this.toolCallNodes.get(tcNodeId)
        if (tcNode) {
          tcNode.triggerFadeOut()
        }
        // Mark as completed in canvas store
        useCanvasStore.getState().updateToolCall(tcNodeId, {
          status: 'completed',
          completedAt: Date.now(),
        })
      }
      // Clear the set — expired nodes will be removed by the animation loop
      tcSet.clear()
    }

    // Clear any PO-to-PO delegations where this PO was the caller
    for (const [tcId, delegation] of this.activeDelegations) {
      if (delegation.callerPO === poName) {
        const targetNode = this.poNodes.get(delegation.targetPO)
        if (targetNode) {
          // Restore target PO's visual to its server status
          targetNode.clearDelegated()
          // Re-apply whatever status the server says it has
          // (setStatus will be called again in the next syncPromptObjects cycle)
        }
        this.activeDelegations.delete(tcId)

        // Mark delegation as completed in canvas store
        useCanvasStore.getState().updateToolCall(`tc-${tcId}`, {
          status: 'completed',
          completedAt: Date.now(),
        })
      }
    }
  }

  // --- Lifecycle ---

  start(): void {
    if (this.running) return
    this.running = true
    this.clock.start()
    this.animate()
  }

  stop(): void {
    this.running = false
    if (this.animationFrameId !== null) {
      cancelAnimationFrame(this.animationFrameId)
      this.animationFrameId = null
    }
  }

  dispose(): void {
    this.stop()

    // Dispose all nodes
    for (const node of this.poNodes.values()) {
      node.dispose()
    }
    this.poNodes.clear()

    for (const node of this.toolCallNodes.values()) {
      node.dispose()
    }
    this.toolCallNodes.clear()

    for (const arc of this.messageArcs.values()) {
      arc.dispose()
    }
    this.messageArcs.clear()

    // Dispose Three.js resources
    this.forceLayout.dispose()
    this.cameraControls.dispose()
    this.composer.dispose()
    this.renderer.dispose()

    // Remove event listeners
    this.renderer.domElement.removeEventListener('click', this.onClick)
    this.renderer.domElement.removeEventListener('pointermove', this.onPointerMove)
    window.removeEventListener('resize', this.onResize)

    // Remove DOM elements
    this.container.removeChild(this.renderer.domElement)
    this.container.removeChild(this.cssRenderer.domElement)
  }

  // --- Animation loop ---

  private animate = (): void => {
    if (!this.running) return
    this.animationFrameId = requestAnimationFrame(this.animate)

    const delta = this.clock.getDelta()
    const elapsed = this.clock.elapsedTime

    // 1. Tick force layout → get positions
    this.forceLayout.tick()
    const positions = this.forceLayout.getPositions()

    // 2. Update PO node positions (lerp) and animations
    for (const [id, node] of this.poNodes) {
      const pos = positions.get(id)
      if (pos) {
        node.setPosition(pos.x, pos.y)
      }
      node.update(delta, elapsed)
    }

    // 3. Update tool call node positions to follow their caller PO
    for (const [poName, tcSet] of this.poToolCallNodes) {
      const callerNode = this.poNodes.get(poName)
      if (!callerNode) continue
      const callerPos = callerNode.getPosition()

      let i = 0
      for (const tcNodeId of tcSet) {
        const tcNode = this.toolCallNodes.get(tcNodeId)
        if (!tcNode) continue
        // Keep tool call nodes orbiting around caller
        const angle = (i * (2 * Math.PI / Math.max(tcSet.size, 1))) - Math.PI / 2
        const offsetDist = NODE.poRadius + 40
        tcNode.setPosition(
          callerPos.x + Math.cos(angle) * offsetDist,
          callerPos.y + Math.sin(angle) * offsetDist
        )
        i++
      }
    }

    // 4. Update arcs (recalculate endpoints, advance particles)
    for (const [id, arc] of this.messageArcs) {
      const fromNode = this.poNodes.get(arc.from)
      const toNode = this.poNodes.get(arc.to)
      if (fromNode && toNode) {
        arc.updateEndpoints(fromNode.getPosition(), toNode.getPosition())
      }
      arc.update(delta)

      if (arc.isExpired()) {
        this.scene.remove(arc.group)
        arc.dispose()
        this.messageArcs.delete(id)
      }
    }

    // 5. Update tool call nodes (lifecycle)
    for (const [id, node] of this.toolCallNodes) {
      node.update(delta)
      if (node.isExpired()) {
        this.scene.remove(node.group)
        node.dispose()
        this.toolCallNodes.delete(id)
        // Clean up from canvas store
        useCanvasStore.getState().removeToolCall(id)
      }
    }

    // 6. Render
    this.composer.render()
    this.cssRenderer.render(this.scene, this.camera)
  }

  // --- Event handlers ---

  private onClick = (event: MouseEvent): void => {
    this.updatePointer(event)
    this.raycaster.setFromCamera(this.pointer, this.camera)

    const meshes = this.getMeshes()
    const intersects = this.raycaster.intersectObjects(meshes)

    if (intersects.length > 0) {
      const obj = intersects[0].object
      const { type, id } = obj.userData
      if (type && id) {
        useCanvasStore.getState().selectNode({ type, id })

        // Update visual selection on PO nodes
        for (const node of this.poNodes.values()) {
          node.setSelected(node.id === id)
        }
        return
      }
    }

    // Click on empty space — deselect
    useCanvasStore.getState().selectNode(null)
    for (const node of this.poNodes.values()) {
      node.setSelected(false)
    }
  }

  private onPointerMove = (event: MouseEvent): void => {
    this.updatePointer(event)
    this.raycaster.setFromCamera(this.pointer, this.camera)

    const meshes = this.getMeshes()
    const intersects = this.raycaster.intersectObjects(meshes)

    // Reset all hover states
    for (const node of this.poNodes.values()) {
      node.setHovered(false)
    }

    if (intersects.length > 0) {
      const obj = intersects[0].object
      const { type, id } = obj.userData
      if (type === 'po' && id) {
        const node = this.poNodes.get(id)
        if (node) {
          node.setHovered(true)
        }
      }
      this.renderer.domElement.style.cursor = 'pointer'
      useCanvasStore.getState().setHoveredNode(id || null)
    } else {
      this.renderer.domElement.style.cursor = 'default'
      useCanvasStore.getState().setHoveredNode(null)
    }
  }

  private onResize = (): void => {
    const { width, height } = this.container.getBoundingClientRect()
    const aspect = width / height
    const frustumSize = 500

    this.camera.left = (-frustumSize * aspect) / 2
    this.camera.right = (frustumSize * aspect) / 2
    this.camera.top = frustumSize / 2
    this.camera.bottom = -frustumSize / 2
    this.camera.updateProjectionMatrix()

    this.renderer.setSize(width, height)
    this.cssRenderer.setSize(width, height)
    this.composer.setSize(width, height)
  }

  // --- Helpers ---

  private updatePointer(event: MouseEvent): void {
    const rect = this.renderer.domElement.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1
  }

  private getMeshes(): THREE.Mesh[] {
    const meshes: THREE.Mesh[] = []
    for (const node of this.poNodes.values()) {
      meshes.push(node.mesh)
    }
    for (const node of this.toolCallNodes.values()) {
      meshes.push(node.mesh)
    }
    return meshes
  }
}
