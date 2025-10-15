#!/bin/bash
# Configure system-wide keyboard layout
# Sets Polish and US International (with dead keys) as system defaults

set -e

echo "==> Configuring keyboard layout..."
echo "    - Polish layout"
echo "    - US International with dead keys"
echo "    - Alt+Shift to toggle"

sudo localectl set-x11-keymap pl,us pc105 ,intl grp:alt_shift_toggle

echo "==> Keyboard configuration complete!"
echo ""
localectl status
