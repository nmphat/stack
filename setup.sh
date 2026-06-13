#!/bin/bash
set -euo pipefail

echo "🔧 Stack Setup"
echo ""

# Init + update submodules
echo "📦 Pulling submodules..."
git submodule update --init --recursive

# Install npm deps for wrapper
echo "📦 Installing wrapper deps..."
pnpm install

# Copy env examples (skip if .env exists)
for dir in hermes-webui; do
  if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
    cp "$dir/.env.example" "$dir/.env"
    echo "📝 Created $dir/.env from .env.example — edit with real values"
  fi
done

echo ""
echo "⚠️  Check .env files for Docker services:"
echo "   hindsight/.env"
echo "   firecrawl/.env"
echo "   (create manually if missing)"
echo ""
echo "✅ Setup complete. Run 'pnpm start' to launch all services."
