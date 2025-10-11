#!/bin/bash
# Configure silent boot for Arch Linux
# This script modifies systemd-boot entries for a clean, minimal boot experience

set -e

echo "==> Configuring silent boot..."

# Silent boot kernel parameters
SILENT_PARAMS="quiet loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0 video=2256x1504"

# Find all boot entries
BOOT_ENTRIES=$(find /boot/loader/entries/ -name "*.conf" -type f)

if [ -z "$BOOT_ENTRIES" ]; then
    echo "ERROR: No boot entries found in /boot/loader/entries/"
    exit 1
fi

# Process each boot entry
for entry in $BOOT_ENTRIES; do
    echo "  - Processing: $(basename "$entry")"

    # Check if silent boot params are already present
    if grep -q "quiet loglevel=3" "$entry"; then
        echo "    Already configured for silent boot, skipping"
        continue
    fi

    # Backup original entry
    sudo cp "$entry" "$entry.bak"

    # Add silent boot parameters to options line
    sudo sed -i "s/^options /options $SILENT_PARAMS /" "$entry"

    echo "    ✓ Added silent boot parameters"
done

# Create /etc/kernel/cmdline for persistent kernel parameters
echo "==> Creating /etc/kernel/cmdline for persistent configuration..."

# Get current root parameters from existing boot entry
FIRST_ENTRY=$(echo "$BOOT_ENTRIES" | head -1)
ROOT_PARAMS=$(grep "^options" "$FIRST_ENTRY" | sed 's/^options //' | sed "s/$SILENT_PARAMS //")

# Create /etc/kernel/cmdline with silent boot params + root params
echo "$SILENT_PARAMS $ROOT_PARAMS" | sudo tee /etc/kernel/cmdline > /dev/null

echo "  ✓ Created /etc/kernel/cmdline (will persist across kernel upgrades)"

# Configure systemd to hide boot messages
echo "==> Configuring systemd for minimal output..."

# Create systemd system.conf.d directory if it doesn't exist
sudo mkdir -p /etc/systemd/system.conf.d

# Create silent boot configuration
sudo tee /etc/systemd/system.conf.d/silent-boot.conf > /dev/null <<'EOF'
[Manager]
# Silent boot configuration
ShowStatus=error
DefaultStandardOutput=journal
EOF

echo "  ✓ Created /etc/systemd/system.conf.d/silent-boot.conf"

echo ""
echo "==> Silent boot configured successfully!"
echo ""
echo "Changes made:"
echo "  - Added kernel parameters for quiet boot"
echo "  - Created /etc/kernel/cmdline for persistent configuration"
echo "  - Configured systemd to show only errors"
echo "  - Backup files created with .bak extension"
echo ""
echo "These settings will survive kernel upgrades."
echo "Reboot to see the changes take effect."
