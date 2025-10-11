#!/bin/bash
# Install ly display manager configuration from user config to system
# This script copies the managed ly configs from ~/.config/ly to /etc/ly

set -e

echo "==> Installing ly configuration..."

# Copy config.ini
if [ -f "$HOME/.config/ly/config.ini" ]; then
    sudo cp "$HOME/.config/ly/config.ini" /etc/ly/config.ini
    echo "  - Installed config.ini"
fi

# Copy setup.sh
if [ -f "$HOME/.config/ly/setup.sh" ]; then
    sudo cp "$HOME/.config/ly/setup.sh" /etc/ly/setup.sh
    sudo chmod +x /etc/ly/setup.sh
    echo "  - Installed setup.sh"
fi

echo "==> ly configuration installed successfully"
