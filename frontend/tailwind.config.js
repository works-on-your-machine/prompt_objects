/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        po: {
          bg: '#1a1918',
          surface: '#222120',
          'surface-2': '#2c2a28',
          'surface-3': '#363432',
          border: '#3d3a37',
          'border-focus': '#5c5752',
          accent: '#d4952a',
          'accent-muted': '#9a6d20',
          'accent-wash': 'rgba(212,149,42,0.08)',
          'text-primary': '#e8e2da',
          'text-secondary': '#a8a29a',
          'text-tertiary': '#78726a',
          'text-ghost': '#524e48',
          'status-idle': '#78726a',
          'status-active': '#d4952a',
          'status-calling': '#3b9a6e',
          'status-error': '#c45c4a',
          'status-delegated': '#5a8fc2',
          success: '#3b9a6e',
          warning: '#d4952a',
          error: '#c45c4a',
        },
      },
      fontFamily: {
        ui: ['Geist', 'system-ui', 'sans-serif'],
        mono: ['"Geist Mono"', '"IBM Plex Mono"', 'monospace'],
      },
      fontSize: {
        '2xs': ['11px', { lineHeight: '15px' }],
      },
    },
  },
  plugins: [],
}
