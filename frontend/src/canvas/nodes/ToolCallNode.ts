import * as THREE from 'three'
import { CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js'
import { COLORS, NODE, ANIMATION } from '../constants'

type Phase = 'fadein' | 'active' | 'fadeout' | 'expired'

export class ToolCallNode {
  readonly id: string
  readonly callerPO: string
  readonly group: THREE.Group
  readonly mesh: THREE.Mesh

  private material: THREE.MeshBasicMaterial
  private label: CSS2DObject
  private labelEl: HTMLDivElement
  private phase: Phase = 'fadein'
  private phaseTime = 0
  private targetPosition = new THREE.Vector3()

  constructor(id: string, toolName: string, callerPO: string) {
    this.id = id
    this.callerPO = callerPO
    this.group = new THREE.Group()
    this.group.userData = { type: 'toolcall', id }

    // Diamond shape (rotated square)
    const r = NODE.toolCallRadius
    const shape = new THREE.Shape()
    shape.moveTo(0, r)
    shape.lineTo(r, 0)
    shape.lineTo(0, -r)
    shape.lineTo(-r, 0)
    shape.closePath()

    const geometry = new THREE.ShapeGeometry(shape)

    this.material = new THREE.MeshBasicMaterial({
      color: COLORS.toolCallFill,
      transparent: true,
      opacity: 0,
    })

    this.mesh = new THREE.Mesh(geometry, this.material)
    this.mesh.userData = { type: 'toolcall', id }
    this.group.add(this.mesh)

    // Label
    this.labelEl = document.createElement('div')
    this.labelEl.className = 'canvas-toolcall-label'
    this.labelEl.textContent = toolName

    this.label = new CSS2DObject(this.labelEl)
    this.label.position.set(0, -(NODE.toolCallRadius + 12), 0)
    this.group.add(this.label)
  }

  setPosition(x: number, y: number): void {
    this.targetPosition.set(x, y, 0)
  }

  triggerFadeOut(): void {
    if (this.phase !== 'expired') {
      this.phase = 'fadeout'
      this.phaseTime = 0
    }
  }

  isExpired(): boolean {
    return this.phase === 'expired'
  }

  update(delta: number): void {
    this.phaseTime += delta
    this.group.position.lerp(this.targetPosition, ANIMATION.positionLerpFactor)

    switch (this.phase) {
      case 'fadein':
        this.material.opacity = Math.min(this.phaseTime / ANIMATION.toolCallFadeInDuration, 1)
        if (this.phaseTime >= ANIMATION.toolCallFadeInDuration) {
          this.phase = 'active'
          this.phaseTime = 0
        }
        break

      case 'active':
        this.material.opacity = 1
        if (this.phaseTime >= ANIMATION.toolCallActiveDuration) {
          this.phase = 'fadeout'
          this.phaseTime = 0
        }
        break

      case 'fadeout':
        this.material.opacity = Math.max(
          1 - this.phaseTime / ANIMATION.toolCallFadeOutDuration,
          0
        )
        this.labelEl.style.opacity = String(this.material.opacity)
        if (this.phaseTime >= ANIMATION.toolCallFadeOutDuration) {
          this.phase = 'expired'
        }
        break

      case 'expired':
        this.material.opacity = 0
        break
    }
  }

  dispose(): void {
    this.mesh.geometry.dispose()
    this.material.dispose()
    this.labelEl.remove()
    this.group.parent?.remove(this.group)
  }
}
