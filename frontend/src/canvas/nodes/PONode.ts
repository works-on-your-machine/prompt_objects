import * as THREE from 'three'
import { CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js'
import { COLORS, CSS_COLORS, NODE, ANIMATION } from '../constants'

const vertexShader = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`

const fragmentShader = /* glsl */ `
  uniform vec3 uColor;
  uniform vec3 uGlowColor;
  uniform float uGlowIntensity;
  uniform float uTime;
  uniform float uHovered;
  uniform float uSelected;

  varying vec2 vUv;

  void main() {
    // Distance from center (0 at center, 1 at edge)
    float dist = length(vUv - 0.5) * 2.0;

    // Base dark fill
    vec3 base = uColor * 0.3;

    // Edge glow
    float edgeGlow = smoothstep(0.5, 1.0, dist) * uGlowIntensity;
    // Animated pulse
    float pulse = sin(uTime * ${ANIMATION.pulseSpeed.toFixed(1)}) * 0.15 + 0.85;
    edgeGlow *= pulse;

    vec3 color = mix(base, uGlowColor, edgeGlow);

    // Hover brightening
    color = mix(color, uGlowColor * 1.2, uHovered * 0.3);

    // Selection brightening
    color = mix(color, uGlowColor * 1.5, uSelected * 0.4);

    // Alpha: solid center, slight transparency at edges
    float alpha = smoothstep(1.0, 0.8, dist);

    gl_FragColor = vec4(color, alpha);
  }
`

type POStatus = 'idle' | 'thinking' | 'calling_tool'

const STATUS_COLORS: Record<POStatus, number> = {
  idle: COLORS.statusIdle,
  thinking: COLORS.statusThinking,
  calling_tool: COLORS.statusCallingTool,
}

const STATUS_CSS_COLORS: Record<POStatus, string> = {
  idle: CSS_COLORS.statusIdle,
  thinking: CSS_COLORS.statusThinking,
  calling_tool: CSS_COLORS.statusCallingTool,
}

export class PONode {
  readonly id: string
  readonly group: THREE.Group
  readonly mesh: THREE.Mesh

  private material: THREE.ShaderMaterial
  private statusRing: THREE.LineLoop
  private statusRingMaterial: THREE.LineBasicMaterial
  private label: CSS2DObject
  private labelEl: HTMLDivElement
  private nameEl: HTMLSpanElement
  private statusEl: HTMLSpanElement
  private badge: CSS2DObject
  private badgeEl: HTMLDivElement
  private badgeCountEl: HTMLSpanElement

  private targetPosition = new THREE.Vector3()

  constructor(id: string, name: string) {
    this.id = id
    this.group = new THREE.Group()
    this.group.userData = { type: 'po', id }

    // Hexagonal geometry
    const geometry = new THREE.CircleGeometry(NODE.poRadius, NODE.poSides)

    // Shader material
    this.material = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        uColor: { value: new THREE.Color(COLORS.nodeFill) },
        uGlowColor: { value: new THREE.Color(COLORS.nodeGlow) },
        uGlowIntensity: { value: 0.5 },
        uTime: { value: 0 },
        uHovered: { value: 0 },
        uSelected: { value: 0 },
      },
      transparent: true,
    })

    this.mesh = new THREE.Mesh(geometry, this.material)
    this.mesh.userData = { type: 'po', id }
    this.group.add(this.mesh)

    // Status ring (hex outline)
    const ringGeometry = new THREE.BufferGeometry()
    const ringPoints: THREE.Vector3[] = []
    for (let i = 0; i <= NODE.poSides; i++) {
      const angle = (i / NODE.poSides) * Math.PI * 2 - Math.PI / 2
      ringPoints.push(
        new THREE.Vector3(
          Math.cos(angle) * (NODE.poRadius + 3),
          Math.sin(angle) * (NODE.poRadius + 3),
          0
        )
      )
    }
    ringGeometry.setFromPoints(ringPoints)

    this.statusRingMaterial = new THREE.LineBasicMaterial({
      color: STATUS_COLORS.idle,
      transparent: true,
      opacity: 0.6,
    })
    this.statusRing = new THREE.LineLoop(ringGeometry, this.statusRingMaterial)
    this.group.add(this.statusRing)

    // CSS2D Label (name + status)
    this.labelEl = document.createElement('div')
    this.labelEl.className = 'canvas-node-label'

    this.nameEl = document.createElement('span')
    this.nameEl.className = 'canvas-node-name'
    this.nameEl.textContent = name

    this.statusEl = document.createElement('span')
    this.statusEl.className = 'canvas-node-status'
    this.statusEl.textContent = 'idle'

    this.labelEl.appendChild(this.nameEl)
    this.labelEl.appendChild(this.statusEl)

    this.label = new CSS2DObject(this.labelEl)
    this.label.position.set(0, -NODE.labelOffsetY, 0)
    this.group.add(this.label)

    // Notification badge
    this.badgeEl = document.createElement('div')
    this.badgeEl.className = 'canvas-node-badge'
    this.badgeEl.style.display = 'none'

    this.badgeCountEl = document.createElement('span')
    this.badgeCountEl.textContent = '0'
    this.badgeEl.appendChild(this.badgeCountEl)

    this.badge = new CSS2DObject(this.badgeEl)
    this.badge.position.set(NODE.badgeOffsetX, -NODE.badgeOffsetY, 0)
    this.group.add(this.badge)
  }

  setStatus(status: POStatus): void {
    this.statusRingMaterial.color.setHex(STATUS_COLORS[status])

    // Update glow intensity based on status
    const intensity = status === 'idle' ? 0.3 : status === 'thinking' ? 0.8 : 0.6
    this.material.uniforms.uGlowIntensity.value = intensity

    // Update glow color for calling_tool
    if (status === 'calling_tool') {
      this.material.uniforms.uGlowColor.value.setHex(COLORS.statusCallingTool)
    } else {
      this.material.uniforms.uGlowColor.value.setHex(COLORS.nodeGlow)
    }

    this.statusEl.textContent = status.replace('_', ' ')
    this.statusEl.style.color = STATUS_CSS_COLORS[status]
  }

  setNotificationCount(count: number): void {
    if (count > 0) {
      this.badgeEl.style.display = 'flex'
      this.badgeCountEl.textContent = String(count)
    } else {
      this.badgeEl.style.display = 'none'
    }
  }

  setHovered(hovered: boolean): void {
    this.material.uniforms.uHovered.value = hovered ? 1 : 0
  }

  setSelected(selected: boolean): void {
    this.material.uniforms.uSelected.value = selected ? 1 : 0
    this.statusRingMaterial.opacity = selected ? 1.0 : 0.6
  }

  setPosition(x: number, y: number): void {
    this.targetPosition.set(x, y, 0)
  }

  getPosition(): THREE.Vector3 {
    return this.group.position.clone()
  }

  update(_delta: number, elapsed: number): void {
    // Lerp toward target position
    this.group.position.lerp(this.targetPosition, ANIMATION.positionLerpFactor)

    // Update time uniform for pulse animation
    this.material.uniforms.uTime.value = elapsed
  }

  dispose(): void {
    this.mesh.geometry.dispose()
    this.material.dispose()
    this.statusRing.geometry.dispose()
    this.statusRingMaterial.dispose()
    this.labelEl.remove()
    this.badgeEl.remove()
    this.group.parent?.remove(this.group)
  }
}
