#!/bin/bash
# Comprehensive system update script for Arch Linux
# Updates official repos, AUR, and firmware

set -e

refresh_berg_updates() {
    local update_status=$?

    if /usr/bin/systemctl --user is-active --quiet quickshell-berg.service; then
        /usr/bin/qs -c berg ipc call shell refreshUpdates >/dev/null 2>&1 || true
    fi

    return "$update_status"
}

trap refresh_berg_updates EXIT

echo "════════════════════════════════════════════════════════════"
echo "  Arch Linux System Update"
echo "════════════════════════════════════════════════════════════"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

readonly MIN_UPDATE_FREE_BYTES=$((10 * 1024 * 1024 * 1024))

prepare_package_storage() {
    local available_bytes
    local available_gib

    echo -e "${BLUE}==> Preparing package storage...${NC}"
    echo "Cleaning package cache (keeping last 3 versions)..."
    if ! sudo paccache -rk3; then
        echo "Could not prune the package cache; continuing to the free-space check." >&2
    fi

    if ! read -r available_bytes < <(
        df --output=avail --block-size=1 / 2>/dev/null | tail -n 1
    ); then
        echo "Unable to determine free space on /; refusing to update packages." >&2
        return 1
    fi

    available_bytes="${available_bytes//[[:space:]]/}"
    if [[ ! "$available_bytes" =~ ^[0-9]+$ ]]; then
        echo "Unable to determine free space on /; refusing to update packages." >&2
        return 1
    fi

    available_gib=$((available_bytes / 1024 / 1024 / 1024))
    if ((available_bytes < MIN_UPDATE_FREE_BYTES)); then
        printf \
            'At least 10 GiB must be free on / before updating packages; only %s GiB is available.\n' \
            "${available_gib}" >&2
        return 1
    fi

    echo "  ${available_gib} GiB free on /"
    echo ""
}

# Prune first so cached packages can recover space before enforcing the update
# floor. This intentionally runs before discovery so it also covers no-op runs.
prepare_package_storage

# Check for updates
echo -e "${BLUE}==> Checking for updates...${NC}"
echo ""

# Official repos
echo -e "${YELLOW}Official repositories:${NC}"
if command -v checkupdates &>/dev/null; then
    official=$(checkupdates 2>/dev/null || true)
    official_count=$(echo "$official" | grep -v '^$' | wc -l)
else
    official=$(pacman -Qu 2>/dev/null || true)
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
    aur=$(yay -Qua 2>/dev/null || true)
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
total=$((official_count + aur_count + firmware_count))
echo "────────────────────────────────────────────────────────────"
echo -e "${GREEN}Total updates available: $total${NC}"
echo "  Official: $official_count | AUR: $aur_count | Firmware: $firmware_count"
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

# Update Firmware
if [ "$firmware_count" -gt 0 ]; then
    echo -e "${BLUE}==> Updating firmware...${NC}"
    sudo fwupdmgr update
    echo ""
fi

# Clean up
echo -e "${BLUE}==> Cleaning up...${NC}"
echo "Removing orphaned packages..."
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [ ! -z "$orphans" ]; then
    echo "$orphans"
    sudo pacman -Rns $(pacman -Qtdq) --noconfirm
else
    echo "  No orphaned packages found"
fi

echo ""
if command -v yay &>/dev/null; then
    echo "Cleaning yay cache..."
    yay -Sc --aur --noconfirm
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ System update complete!${NC}"
echo "════════════════════════════════════════════════════════════"
