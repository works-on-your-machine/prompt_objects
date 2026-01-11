/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Custom colors for PromptObjects
        po: {
          bg: '#0f0f1a',
          surface: '#1a1a2e',
          border: '#2d2d44',
          accent: '#7c3aed',
          'accent-hover': '#9061f9',
          success: '#22c55e',
          warning: '#f59e0b',
          error: '#ef4444',
        },
      },
    },
  },
  plugins: [],
}
