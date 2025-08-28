import { defineConfig } from 'slidev/config'
import { resolve } from 'path'

export default defineConfig({
  vite: {
    resolve: {
      alias: {
        'lz-string': resolve(__dirname, '../shims/lz-string.mjs'),
      },
    },
  },
  mermaid: {
    options: {
      theme: 'dark',
      securityLevel: 'loose',
      flowchart: { useMaxWidth: true, htmlLabels: true },
    },
    themeVariables: {
      primaryColor: '#22c55e',
      primaryTextColor: '#e5e7eb',
      lineColor: '#94a3b8',
      tertiaryColor: '#141821',
      fontFamily: 'Inter, system-ui, sans-serif',
    },
  },
})
