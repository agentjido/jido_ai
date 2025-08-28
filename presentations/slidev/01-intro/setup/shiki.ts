import { defineShikiSetup } from '@slidev/types'

export default defineShikiSetup(() => {
  return {
    themes: {
      dark: 'vitesse-dark',
      light: 'vitesse-light',
    },
    langs: [
      'javascript',
      'typescript',
      'bash',
      'json',
      'markdown',
      'elixir',
    ],
    transformers: [],
  }
})
