#!/usr/bin/env bash
set -e

# ==============================================================================
# AcexGateway 1-Click Update Script
# Automatically updates AcexGateway to the latest version.
# ==============================================================================

echo "🚀 [AcexGateway] Checking environment and updating..."

# 1. Check if running inside or with Docker Compose
if command -v docker &> /dev/null && [ -f "docker-compose.yml" ]; then
    echo "🐳 [AcexGateway] Docker Compose environment detected."
    echo "📦 Pulling latest images..."
    if docker compose version &> /dev/null; then
        docker compose pull
        echo "🔄 Restarting containers with zero-downtime recreation..."
        docker compose up -d --remove-orphans
    elif command -v docker-compose &> /dev/null; then
        docker-compose pull
        echo "🔄 Restarting containers with zero-downtime recreation..."
        docker-compose up -d --remove-orphans
    else
        echo "❌ Docker Compose command not found."
        exit 1
    fi
    echo "✅ [AcexGateway] Docker containers updated and restarted successfully!"
    exit 0
fi

# 2. Check if running directly from Git source
if [ -d ".git" ]; then
    echo "📂 [AcexGateway] Git source repository detected."
    echo "📥 Pulling latest commits from origin..."
    git pull origin main
    if command -v mix &> /dev/null; then
        echo "🔨 Compiling Elixir application..."
        mix deps.get
        mix compile
        echo "✅ [AcexGateway] Code updated and compiled successfully!"
        echo "💡 Restart the running service/process to apply changes."
    fi
    exit 0
fi

echo "⚠️ [AcexGateway] Unrecognized deployment environment. Please pull images manually:"
echo "   docker pull ghcr.io/quaywin/acex:latest"
exit 1
