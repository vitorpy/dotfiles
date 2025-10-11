#!/bin/bash
# Setup Docker on Arch Linux
# This script installs Docker, adds user to docker group, and enables the service

set -e

echo "==> Setting up Docker..."

# Get the current user
CURRENT_USER=$(whoami)

# Add user to docker group
echo "  - Adding $CURRENT_USER to docker group..."
sudo usermod -aG docker "$CURRENT_USER"
echo "    ✓ User added to docker group"

# Enable and start Docker service
echo "  - Enabling Docker service..."
sudo systemctl enable docker.service
echo "    ✓ Docker service enabled"

echo "  - Starting Docker service..."
sudo systemctl start docker.service
echo "    ✓ Docker service started"

# Check Docker status
if systemctl is-active --quiet docker.service; then
    echo "    ✓ Docker is running"
else
    echo "    ⚠ Warning: Docker service failed to start"
fi

echo ""
echo "==> Docker setup complete!"
echo ""
echo "Important:"
echo "  - You need to log out and log back in for group changes to take effect"
echo "  - After re-login, test with: docker run hello-world"
echo "  - Docker Compose is also installed and available as 'docker-compose'"
