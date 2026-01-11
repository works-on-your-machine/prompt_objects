import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],

  // Output to Ruby server's public directory for production
  build: {
    outDir: '../lib/prompt_objects/server/public',
    emptyOutDir: true,
  },

  // Development proxy to Ruby server
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      },
      // WebSocket proxy
      '/ws': {
        target: 'ws://localhost:3000',
        ws: true,
      },
    },
  },
})
