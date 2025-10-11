#!/bin/bash
# Comprehensive system update script for Arch Linux
# Updates official repos, AUR, and Flatpak packages

set -e

echo "════════════════════════════════════════════════════════════"
echo "  Arch Linux System Update"
echo "════════════════════════════════════════════════════════════"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for updates first
echo -e "${BLUE}==> Checking for updates...${NC}"
echo ""

# Official repos
echo -e "${YELLOW}Official repositories:${NC}"
if command -v checkupdates &>/dev/null; then
    official=$(checkupdates 2>/dev/null)
    official_count=$(echo "$official" | grep -v '^$' | wc -l)
else
    official=$(pacman -Qu 2>/dev/null)
    official_count=$(echo "$official" | grep -v '^$' | wc -l)
fi

if [ "$official_count" -gt 0 ]; then
    echo "$official"
    echo ""
else
    echo "  No updates available"
    echo ""
fi

# AUR
echo -e "${YELLOW}AUR packages:${NC}"
if command -v yay &>/dev/null; then
    aur=$(yay -Qua 2>/dev/null)
    aur_count=$(echo "$aur" | grep -v '^$' | wc -l)
    if [ "$aur_count" -gt 0 ]; then
        echo "$aur"
        echo ""
    else
        echo "  No updates available"
        echo ""
    fi
else
    echo "  yay not installed, skipping AUR updates"
    echo ""
    aur_count=0
fi

# Flatpak
echo -e "${YELLOW}Flatpak packages:${NC}"
if command -v flatpak &>/dev/null; then
    flatpak=$(flatpak remote-ls --updates 2>/dev/null)
    flatpak_count=$(echo "$flatpak" | grep -v '^$' | wc -l)
    if [ "$flatpak_count" -gt 0 ]; then
        echo "$flatpak"
        echo ""
    else
        echo "  No updates available"
        echo ""
    fi
else
    echo "  Flatpak not installed, skipping"
    echo ""
    flatpak_count=0
fi

# Firmware
echo -e "${YELLOW}Firmware updates:${NC}"
if command -v fwupdmgr &>/dev/null; then
    # Refresh metadata first
    fwupdmgr refresh &>/dev/null || true
    firmware=$(fwupdmgr get-updates 2>/dev/null | grep -E "^\s+├─" || true)
    firmware_count=$(echo "$firmware" | grep -v '^$' | wc -l)
    if [ "$firmware_count" -gt 0 ]; then
        echo "$firmware"
        echo ""
    else
        echo "  No updates available"
        echo ""
    fi
else
    echo "  fwupd not installed, skipping"
    echo ""
    firmware_count=0
fi

# Summary
total=$((official_count + aur_count + flatpak_count + firmware_count))
echo "────────────────────────────────────────────────────────────"
echo -e "${GREEN}Total updates available: $total${NC}"
echo "  Official: $official_count | AUR: $aur_count | Flatpak: $flatpak_count | Firmware: $firmware_count"
echo "────────────────────────────────────────────────────────────"
echo ""

if [ "$total" -eq 0 ]; then
    echo -e "${GREEN}✓ System is up to date!${NC}"
    exit 0
fi

# Ask for confirmation
read -p "Proceed with updates? [Y/n] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    echo "Update cancelled."
    exit 0
fi

echo ""

# Update official repos
if [ "$official_count" -gt 0 ]; then
    echo -e "${BLUE}==> Updating official repositories...${NC}"
    sudo pacman -Syu
    echo ""
fi

# Update AUR
if [ "$aur_count" -gt 0 ]; then
    echo -e "${BLUE}==> Updating AUR packages...${NC}"
    yay -Sua
    echo ""
fi

# Update Flatpak
if [ "$flatpak_count" -gt 0 ]; then
    echo -e "${BLUE}==> Updating Flatpak packages...${NC}"
    flatpak update -y
    echo ""
fi

# Update Firmware
if [ "$firmware_count" -gt 0 ]; then
    echo -e "${BLUE}==> Updating firmware...${NC}"
    sudo fwupdmgr update
    echo ""
fi

# Clean up
echo -e "${BLUE}==> Cleaning up...${NC}"
echo "Removing orphaned packages..."
orphans=$(pacman -Qtdq 2>/dev/null)
if [ ! -z "$orphans" ]; then
    echo "$orphans"
    sudo pacman -Rns $(pacman -Qtdq) --noconfirm
else
    echo "  No orphaned packages found"
fi

echo ""
echo "Cleaning package cache (keeping last 3 versions)..."
sudo paccache -rk3

if command -v yay &>/dev/null; then
    echo "Cleaning yay cache..."
    yay -Sc --noconfirm
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ System update complete!${NC}"
echo "════════════════════════════════════════════════════════════"
