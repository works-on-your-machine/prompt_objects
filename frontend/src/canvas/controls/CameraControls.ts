import * as THREE from 'three'
import { CAMERA } from '../constants'

export class CameraControls {
  private camera: THREE.OrthographicCamera
  private domElement: HTMLElement
  private isPanning = false
  private panStart = new THREE.Vector2()

  private onWheel: (e: WheelEvent) => void
  private onPointerDown: (e: PointerEvent) => void
  private onPointerMove: (e: PointerEvent) => void
  private onPointerUp: (e: PointerEvent) => void

  constructor(camera: THREE.OrthographicCamera, domElement: HTMLElement) {
    this.camera = camera
    this.domElement = domElement

    this.onWheel = this.handleWheel.bind(this)
    this.onPointerDown = this.handlePointerDown.bind(this)
    this.onPointerMove = this.handlePointerMove.bind(this)
    this.onPointerUp = this.handlePointerUp.bind(this)

    domElement.addEventListener('wheel', this.onWheel, { passive: false })
    domElement.addEventListener('pointerdown', this.onPointerDown)
    domElement.addEventListener('pointermove', this.onPointerMove)
    domElement.addEventListener('pointerup', this.onPointerUp)
  }

  private handleWheel(e: WheelEvent): void {
    e.preventDefault()
    const delta = e.deltaY > 0 ? 1 - CAMERA.zoomSpeed : 1 + CAMERA.zoomSpeed
    const newZoom = this.camera.zoom * delta
    this.camera.zoom = THREE.MathUtils.clamp(newZoom, CAMERA.zoomMin, CAMERA.zoomMax)
    this.camera.updateProjectionMatrix()
  }

  private handlePointerDown(e: PointerEvent): void {
    // Shift+left click or middle mouse button for panning
    if ((e.button === 0 && e.shiftKey) || e.button === 1) {
      this.isPanning = true
      this.panStart.set(e.clientX, e.clientY)
      this.domElement.setPointerCapture(e.pointerId)
    }
  }

  private handlePointerMove(e: PointerEvent): void {
    if (!this.isPanning) return

    const dx = e.clientX - this.panStart.x
    const dy = e.clientY - this.panStart.y

    // Convert screen pixels to world units based on zoom
    const worldDx = -dx / this.camera.zoom
    const worldDy = dy / this.camera.zoom

    this.camera.position.x += worldDx
    this.camera.position.y += worldDy

    this.panStart.set(e.clientX, e.clientY)
  }

  private handlePointerUp(e: PointerEvent): void {
    if (this.isPanning) {
      this.isPanning = false
      this.domElement.releasePointerCapture(e.pointerId)
    }
  }

  fitAll(bounds: THREE.Box3): void {
    if (bounds.isEmpty()) return

    const center = new THREE.Vector3()
    bounds.getCenter(center)
    const size = new THREE.Vector3()
    bounds.getSize(size)

    this.camera.position.x = center.x
    this.camera.position.y = center.y

    const viewWidth = this.camera.right - this.camera.left
    const viewHeight = this.camera.top - this.camera.bottom

    const scaleX = viewWidth / (size.x * CAMERA.fitPadding)
    const scaleY = viewHeight / (size.y * CAMERA.fitPadding)

    this.camera.zoom = Math.min(scaleX, scaleY, CAMERA.zoomMax)
    this.camera.zoom = Math.max(this.camera.zoom, CAMERA.zoomMin)
    this.camera.updateProjectionMatrix()
  }

  dispose(): void {
    this.domElement.removeEventListener('wheel', this.onWheel)
    this.domElement.removeEventListener('pointerdown', this.onPointerDown)
    this.domElement.removeEventListener('pointermove', this.onPointerMove)
    this.domElement.removeEventListener('pointerup', this.onPointerUp)
  }
}
