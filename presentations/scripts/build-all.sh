#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build all decks under slidev/*
for deck in slidev/*; do
  [ -d "$deck" ] || continue
  if [ -f "$deck/slides.md" ]; then
    echo "Building $deck ..."
    npx -y @slidev/cli build "$deck/slides.md"
  fi
done

echo "Done."
