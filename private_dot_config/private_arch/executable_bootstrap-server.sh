#!/bin/bash
# Bootstrap script for server installations
# Installs packages from packages.txt but skips desktop/GUI applications

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Server Bootstrap Script ===${NC}"
echo "Reading packages from: $PACKAGES_FILE"
echo ""

# Packages to install
PACMAN_PACKAGES=()
AUR_PACKAGES=()

# Sections to skip (desktop/GUI related)
SKIP_SECTIONS=(
    "# Hyprland ecosystem"
    "# GNOME Apps"
    "# Sway ecosystem"
    "# Communication & Productivity"
    "# Theming & Fonts"
    "# Multimedia & Hardware Acceleration"
)

# Individual packages to skip (GUI apps in other sections)
SKIP_PACKAGES=(
    "firefox"
    "chromium"
    "bitwarden"  # GUI version, keep bitwarden-cli
    "nautilus"
    "ghostty"
    "vlc"
    "vscodium-bin"
    "jan-appimage"
    "veracrypt"
    "framework-tool-tui"
)

skip_this_section=false

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && {
        # Check if this is a section header we should skip
        for section in "${SKIP_SECTIONS[@]}"; do
            if [[ "$line" == "$section"* ]]; then
                skip_this_section=true
                echo -e "${YELLOW}Skipping section: $line${NC}"
                break
            fi
        done

        # Reset skip flag on any new section that's not in skip list
        if [[ "$line" =~ ^[[:space:]]*# ]] && [[ ! " ${SKIP_SECTIONS[@]} " =~ " ${line} " ]]; then
            skip_this_section=false
        fi

        continue
    }

    # Skip if we're in a skipped section
    [[ "$skip_this_section" == true ]] && continue

    # Parse package line: "package-name | source"
    if [[ "$line" =~ ^([^|]+)\|[[:space:]]*(pacman|aur|flatpak) ]]; then
        package="${BASH_REMATCH[1]}"
        source="${BASH_REMATCH[2]}"

        # Trim whitespace
        package=$(echo "$package" | xargs)

        # Skip individual packages
        skip=false
        for skip_pkg in "${SKIP_PACKAGES[@]}"; do
            if [[ "$package" == "$skip_pkg" ]]; then
                skip=true
                echo -e "${YELLOW}Skipping GUI package: $package${NC}"
                break
            fi
        done
        [[ "$skip" == true ]] && continue

        # Skip flatpak packages on servers
        if [[ "$source" == "flatpak" ]]; then
            echo -e "${YELLOW}Skipping flatpak: $package${NC}"
            continue
        fi

        # Add to appropriate array
        if [[ "$source" == "pacman" ]]; then
            PACMAN_PACKAGES+=("$package")
        elif [[ "$source" == "aur" ]]; then
            AUR_PACKAGES+=("$package")
        fi
    fi
done < "$PACKAGES_FILE"

echo ""
echo -e "${GREEN}Packages to install:${NC}"
echo "  Pacman packages: ${#PACMAN_PACKAGES[@]}"
echo "  AUR packages: ${#AUR_PACKAGES[@]}"
echo ""

# Ask for confirmation
read -p "Continue with installation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Update system first
echo -e "${GREEN}Updating system...${NC}"
sudo pacman -Syu --noconfirm

# Install pacman packages
if [ ${#PACMAN_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo -e "${GREEN}Installing pacman packages...${NC}"
    sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}" || {
        echo -e "${RED}Some pacman packages failed to install${NC}"
    }
fi

# Install AUR packages (requires yay)
if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
    if command -v yay &> /dev/null; then
        echo ""
        echo -e "${GREEN}Installing AUR packages...${NC}"
        yay -S --needed --noconfirm "${AUR_PACKAGES[@]}" || {
            echo -e "${RED}Some AUR packages failed to install${NC}"
        }
    else
        echo -e "${YELLOW}yay not found, skipping AUR packages${NC}"
        echo "Install yay first or manually install: ${AUR_PACKAGES[*]}"
    fi
fi

echo ""
echo -e "${GREEN}=== Bootstrap complete! ===${NC}"
