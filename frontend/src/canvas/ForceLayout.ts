import {
  forceSimulation,
  forceManyBody,
  forceCenter,
  forceCollide,
  forceLink,
  type Simulation,
  type SimulationNodeDatum,
  type SimulationLinkDatum,
} from 'd3-force'
import { FORCE } from './constants'

export interface ForceNode extends SimulationNodeDatum {
  id: string
  type: 'po' | 'toolcall'
}

export interface ForceLink extends SimulationLinkDatum<ForceNode> {
  id: string
}

export class ForceLayout {
  private simulation: Simulation<ForceNode, ForceLink>
  private nodes: ForceNode[] = []
  private links: ForceLink[] = []
  private dirty = false

  constructor() {
    this.simulation = forceSimulation<ForceNode, ForceLink>()
      .alphaDecay(FORCE.alphaDecay)
      .velocityDecay(FORCE.velocityDecay)
      .force('charge', forceManyBody<ForceNode>().strength(FORCE.chargeStrength))
      .force('center', forceCenter<ForceNode>(0, 0).strength(FORCE.centerStrength))
      .force(
        'collision',
        forceCollide<ForceNode>().radius(FORCE.collisionRadius)
      )
      .force(
        'link',
        forceLink<ForceNode, ForceLink>()
          .id((d) => d.id)
          .distance(FORCE.linkDistance)
      )
      .stop() // Manual tick mode — we call tick() from animation loop
  }

  addNode(id: string, type: 'po' | 'toolcall'): void {
    if (this.nodes.find((n) => n.id === id)) return
    this.nodes.push({ id, type })
    this.dirty = true
  }

  removeNode(id: string): void {
    const idx = this.nodes.findIndex((n) => n.id === id)
    if (idx === -1) return
    this.nodes.splice(idx, 1)
    // Also remove any links referencing this node
    this.links = this.links.filter((l) => {
      const src = typeof l.source === 'object' ? (l.source as ForceNode).id : l.source
      const tgt = typeof l.target === 'object' ? (l.target as ForceNode).id : l.target
      return src !== id && tgt !== id
    })
    this.dirty = true
  }

  addLink(id: string, sourceId: string, targetId: string): void {
    if (this.links.find((l) => l.id === id)) return
    this.links.push({ id, source: sourceId, target: targetId })
    this.dirty = true
  }

  removeLink(id: string): void {
    const idx = this.links.findIndex((l) => l.id === id)
    if (idx === -1) return
    this.links.splice(idx, 1)
    this.dirty = true
  }

  tick(): void {
    if (this.dirty) {
      this.rebuild()
      this.dirty = false
    }
    this.simulation.tick()
  }

  getPositions(): Map<string, { x: number; y: number }> {
    const positions = new Map<string, { x: number; y: number }>()
    for (const node of this.nodes) {
      positions.set(node.id, { x: node.x ?? 0, y: node.y ?? 0 })
    }
    return positions
  }

  reheat(): void {
    this.simulation.alpha(0.8).restart().stop()
  }

  private rebuild(): void {
    this.simulation.nodes(this.nodes)
    const linkForce = this.simulation.force('link') as ReturnType<
      typeof forceLink<ForceNode, ForceLink>
    >
    if (linkForce) {
      linkForce.links(this.links)
    }
    this.reheat()
  }

  dispose(): void {
    this.simulation.stop()
    this.nodes = []
    this.links = []
  }
}
