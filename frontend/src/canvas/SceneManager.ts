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
import { COLORS, BLOOM } from './constants'
import type { PromptObject, BusMessage, Notification } from '../types'

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

      const arc = new MessageArc(
        arcId,
        msg.from,
        msg.to,
        fromNode.getPosition(),
        toNode.getPosition()
      )
      this.messageArcs.set(arcId, arc)
      this.scene.add(arc.group)

      // Check if this is a tool call message — create a ToolCallNode
      if (typeof msg.content === 'object' && msg.content !== null) {
        const content = msg.content as Record<string, unknown>
        if (content.tool_name || content.capability) {
          const toolId = `tc-${arcId}`
          const toolName = (content.tool_name || content.capability || 'tool') as string
          const tcNode = new ToolCallNode(toolId, toolName, msg.from)

          // Position near the caller node
          const callerPos = fromNode.getPosition()
          const targetPos = toNode.getPosition()
          const midX = (callerPos.x + targetPos.x) / 2
          const midY = (callerPos.y + targetPos.y) / 2
          tcNode.setPosition(midX, midY + 30)

          this.toolCallNodes.set(toolId, tcNode)
          this.scene.add(tcNode.group)
        }
      }
    }

    // Keep processed set from growing unbounded
    if (this.processedArcIds.size > 500) {
      const ids = Array.from(this.processedArcIds)
      for (let i = 0; i < 200; i++) {
        this.processedArcIds.delete(ids[i])
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

    // 3. Update arcs (recalculate endpoints, advance particles)
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

    // 4. Update tool call nodes (lifecycle)
    for (const [id, node] of this.toolCallNodes) {
      node.update(delta)
      if (node.isExpired()) {
        this.scene.remove(node.group)
        node.dispose()
        this.toolCallNodes.delete(id)
      }
    }

    // 5. Render
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

        // Update visual selection
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
