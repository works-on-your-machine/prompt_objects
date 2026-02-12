// Canvas visualization constants

// Colors (hex values matching po-* palette)
export const COLORS = {
  // Node colors
  background: 0x0f0f1a,
  surface: 0x1a1a2e,
  border: 0x2d2d44,
  accent: 0x7c3aed,
  accentHover: 0x9061f9,
  success: 0x22c55e,
  warning: 0xf59e0b,
  error: 0xef4444,

  // Status colors
  statusIdle: 0x6b7280,
  statusThinking: 0x7c3aed,
  statusCallingTool: 0xf59e0b,

  // Canvas-specific
  nodeFill: 0x1a1a2e,
  nodeGlow: 0x7c3aed,
  toolCallFill: 0x3b82f6,
  arcColor: 0x7c3aed,
  particleColor: 0xc084fc,
  gridColor: 0x1a1a2e,
} as const

// CSS color strings (for CSS2DRenderer elements)
export const CSS_COLORS = {
  accent: '#7c3aed',
  accentHover: '#9061f9',
  warning: '#f59e0b',
  success: '#22c55e',
  error: '#ef4444',
  textPrimary: '#ffffff',
  textSecondary: '#9ca3af',
  textMuted: '#6b7280',
  surface: '#1a1a2e',
  border: '#2d2d44',
  statusIdle: '#6b7280',
  statusThinking: '#7c3aed',
  statusCallingTool: '#f59e0b',
} as const

// Node dimensions
export const NODE = {
  poRadius: 40,
  poSides: 6, // hexagon
  toolCallRadius: 18,
  labelOffsetY: 55,
  badgeOffsetX: 30,
  badgeOffsetY: -30,
} as const

// Camera
export const CAMERA = {
  zoomMin: 0.1,
  zoomMax: 5,
  zoomSpeed: 0.1,
  fitPadding: 1.3, // 30% padding
} as const

// Animation
export const ANIMATION = {
  positionLerpFactor: 0.1,
  toolCallFadeInDuration: 0.4,
  toolCallActiveDuration: 8,
  toolCallFadeOutDuration: 1.5,
  arcLifetime: 6,
  arcFadeDuration: 2,
  particleSpeed: 0.4,
  particleCount: 5,
  pulseSpeed: 2,
} as const

// Force simulation
export const FORCE = {
  chargeStrength: -300,
  centerStrength: 0.05,
  collisionRadius: 60, // radius + 20
  linkDistance: 200,
  alphaDecay: 0.02,
  velocityDecay: 0.4,
} as const

// Bloom
export const BLOOM = {
  strength: 0.8,
  radius: 0.4,
  threshold: 0.6,
} as const

// Sync throttling
export const SYNC_THROTTLE_MS = 100
