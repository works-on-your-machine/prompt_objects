import * as THREE from 'three'
import { COLORS, ANIMATION } from '../constants'

export class MessageArc {
  readonly id: string
  readonly from: string
  readonly to: string
  readonly group: THREE.Group

  private curve: THREE.QuadraticBezierCurve3
  private line: THREE.Line
  private lineMaterial: THREE.LineBasicMaterial
  private particles: THREE.Points
  private particleMaterial: THREE.PointsMaterial
  private particlePositions: Float32Array
  private particleTs: number[] // parameter t for each particle on the curve

  private startPoint = new THREE.Vector3()
  private endPoint = new THREE.Vector3()
  private controlPoint = new THREE.Vector3()
  private age = 0
  private expired = false

  constructor(id: string, from: string, to: string, startPos: THREE.Vector3, endPos: THREE.Vector3) {
    this.id = id
    this.from = from
    this.to = to
    this.group = new THREE.Group()

    this.startPoint.copy(startPos)
    this.endPoint.copy(endPos)
    this.computeControlPoint()

    this.curve = new THREE.QuadraticBezierCurve3(
      this.startPoint,
      this.controlPoint,
      this.endPoint
    )

    // Arc line
    const linePoints = this.curve.getPoints(50)
    const lineGeometry = new THREE.BufferGeometry().setFromPoints(linePoints)
    this.lineMaterial = new THREE.LineBasicMaterial({
      color: COLORS.arcColor,
      transparent: true,
      opacity: 0.4,
    })
    this.line = new THREE.Line(lineGeometry, this.lineMaterial)
    this.group.add(this.line)

    // Particles traveling along the curve
    const count = ANIMATION.particleCount
    this.particlePositions = new Float32Array(count * 3)
    this.particleTs = []

    for (let i = 0; i < count; i++) {
      this.particleTs.push(i / count)
    }

    const particleGeometry = new THREE.BufferGeometry()
    particleGeometry.setAttribute(
      'position',
      new THREE.BufferAttribute(this.particlePositions, 3)
    )

    this.particleMaterial = new THREE.PointsMaterial({
      color: COLORS.particleColor,
      size: 4,
      transparent: true,
      opacity: 0.8,
      sizeAttenuation: false,
    })

    this.particles = new THREE.Points(particleGeometry, this.particleMaterial)
    this.group.add(this.particles)

    this.updateParticlePositions()
  }

  private computeControlPoint(): void {
    // Perpendicular offset at midpoint
    const mid = new THREE.Vector3().addVectors(this.startPoint, this.endPoint).multiplyScalar(0.5)
    const dir = new THREE.Vector3().subVectors(this.endPoint, this.startPoint)
    const dist = dir.length()
    // Perpendicular in 2D: rotate 90 degrees
    const perp = new THREE.Vector3(-dir.y, dir.x, 0).normalize()
    this.controlPoint.copy(mid).addScaledVector(perp, dist * 0.3)
  }

  updateEndpoints(startPos: THREE.Vector3, endPos: THREE.Vector3): void {
    this.startPoint.copy(startPos)
    this.endPoint.copy(endPos)
    this.computeControlPoint()

    this.curve.v0.copy(this.startPoint)
    this.curve.v1.copy(this.controlPoint)
    this.curve.v2.copy(this.endPoint)

    // Rebuild line geometry
    const linePoints = this.curve.getPoints(50)
    this.line.geometry.dispose()
    this.line.geometry = new THREE.BufferGeometry().setFromPoints(linePoints)
  }

  private updateParticlePositions(): void {
    for (let i = 0; i < this.particleTs.length; i++) {
      const point = this.curve.getPoint(this.particleTs[i])
      this.particlePositions[i * 3] = point.x
      this.particlePositions[i * 3 + 1] = point.y
      this.particlePositions[i * 3 + 2] = point.z
    }
    this.particles.geometry.attributes.position.needsUpdate = true
  }

  update(delta: number): void {
    this.age += delta

    // Advance particles
    for (let i = 0; i < this.particleTs.length; i++) {
      this.particleTs[i] = (this.particleTs[i] + delta * ANIMATION.particleSpeed) % 1
    }
    this.updateParticlePositions()

    // Fade out in last 2 seconds of lifetime
    const fadeStart = ANIMATION.arcLifetime - ANIMATION.arcFadeDuration
    if (this.age > fadeStart) {
      const fadeProgress = (this.age - fadeStart) / ANIMATION.arcFadeDuration
      const alpha = Math.max(1 - fadeProgress, 0)
      this.lineMaterial.opacity = 0.4 * alpha
      this.particleMaterial.opacity = 0.8 * alpha
    }

    if (this.age >= ANIMATION.arcLifetime) {
      this.expired = true
    }
  }

  isExpired(): boolean {
    return this.expired
  }

  dispose(): void {
    this.line.geometry.dispose()
    this.lineMaterial.dispose()
    this.particles.geometry.dispose()
    this.particleMaterial.dispose()
    this.group.parent?.remove(this.group)
  }
}
