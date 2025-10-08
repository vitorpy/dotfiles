#!/bin/bash
set -e

PACKAGES_FILE="$HOME/.config/arch/packages.txt"

echo "==> Installing Arch packages from $PACKAGES_FILE"

# Install yay (AUR helper) if not present
if ! command -v yay &> /dev/null; then
    echo "==> Installing yay AUR helper..."
    sudo pacman -S --needed base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd -
fi

# Parse package list and install
pacman_packages=()
aur_packages=()
flatpak_packages=()

while IFS='|' read -r package source; do
    # Skip comments and empty lines
    [[ "$package" =~ ^#.*$ ]] && continue
    [[ -z "$package" ]] && continue

    # Trim whitespace
    package=$(echo "$package" | xargs)
    source=$(echo "$source" | xargs)

    case "$source" in
        pacman)
            pacman_packages+=("$package")
            ;;
        aur)
            aur_packages+=("$package")
            ;;
        flatpak)
            flatpak_packages+=("$package")
            ;;
    esac
done < "$PACKAGES_FILE"

# Install pacman packages
if [ ${#pacman_packages[@]} -gt 0 ]; then
    echo "==> Installing pacman packages: ${pacman_packages[*]}"
    sudo pacman -S --needed --noconfirm "${pacman_packages[@]}"
fi

# Install AUR packages
if [ ${#aur_packages[@]} -gt 0 ]; then
    echo "==> Installing AUR packages: ${aur_packages[*]}"
    yay -S --needed --noconfirm "${aur_packages[@]}"
fi

# Install flatpak packages
if [ ${#flatpak_packages[@]} -gt 0 ]; then
    if ! command -v flatpak &> /dev/null; then
        echo "==> Installing flatpak..."
        sudo pacman -S --needed --noconfirm flatpak
    fi

    echo "==> Installing flatpak packages: ${flatpak_packages[*]}"
    for pkg in "${flatpak_packages[@]}"; do
        flatpak install -y flathub "$pkg"
    done
fi

echo "==> All packages installed successfully!"
