// Canvas visualization constants

// Colors (hex values matching warm po-* palette)
export const COLORS = {
  // Node colors
  background: 0x1a1918,
  surface: 0x222120,
  border: 0x3d3a37,
  accent: 0xd4952a,
  accentHover: 0xe0a940,
  success: 0x3b9a6e,
  warning: 0xd4952a,
  error: 0xc45c4a,

  // Status colors
  statusIdle: 0x78726a,
  statusThinking: 0xd4952a,
  statusCallingTool: 0x3b9a6e,

  // Canvas-specific
  nodeFill: 0x222120,
  nodeGlow: 0xd4952a,
  toolCallFill: 0x3b9a6e,
  arcColor: 0xd4952a,
  particleColor: 0xe0a940,
  gridColor: 0x222120,
} as const

// CSS color strings (for CSS2DRenderer elements)
export const CSS_COLORS = {
  accent: '#d4952a',
  accentHover: '#e0a940',
  warning: '#d4952a',
  success: '#3b9a6e',
  error: '#c45c4a',
  textPrimary: '#e8e2da',
  textSecondary: '#a8a29a',
  textMuted: '#78726a',
  surface: '#222120',
  border: '#3d3a37',
  statusIdle: '#78726a',
  statusThinking: '#d4952a',
  statusCallingTool: '#3b9a6e',
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
