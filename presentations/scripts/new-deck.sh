#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <deck-slug>" >&2
  exit 1
fi

slug="$1"
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
slidev_dir="$root_dir/slidev"

mkdir -p "$slidev_dir"

# Find next index (NN)
max=0
for d in "$slidev_dir"/*; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"
  if [[ "$base" =~ ^([0-9]{2})- ]]; then
    n="${BASH_REMATCH[1]}"
    if (( 10#$n > max )); then max=$((10#$n)); fi
  fi
done
next=$(printf "%02d" $((max+1)))

new_dir="$slidev_dir/${next}-${slug}"
mkdir -p "$new_dir"

# Create slidev.config.ts with shared lz-string alias and mermaid config
cat > "$new_dir/slidev.config.ts" <<'EOF'
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
EOF

# Create slides.md starter
cat > "$new_dir/slides.md" <<'EOF'
---
title: "New Deck"
subtitle: ""
eyebrow: ""
author: Jido Team
info: ""
theme: slidev-theme-agent-jido
layout: cover
transition: slide-left
mdc: true
drawings:
  persist: false
---

# New Deck

Welcome to your new deck. Start editing `slides.md`.

---

## Agenda

- Topic 1
- Topic 2

---

```mermaid {scale: 0.9}
flowchart LR
  A --> B
```
EOF

# Create Shiki setup for syntax highlighting with Elixir and light/dark themes
mkdir -p "$new_dir/setup"
cat > "$new_dir/setup/shiki.ts" <<'EOF'
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
EOF

# Output path
echo "$new_dir"
