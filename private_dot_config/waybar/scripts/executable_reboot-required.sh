#!/bin/bash

# Check if system reboot is required
# Detects kernel version mismatch (running vs installed)

running_kernel=$(uname -r)

# Check if the running kernel's modules directory exists
if [ ! -d "/lib/modules/$running_kernel" ]; then
    # Running kernel modules missing - reboot required
    installed_kernels=$(ls -1 /lib/modules/ | sort -V | tail -1)
    echo "{\"text\":\"\", \"tooltip\":\"Reboot required: kernel $running_kernel → $installed_kernels\", \"class\":\"reboot-required\"}"
else
    # System OK, no reboot needed - show nothing
    echo ""
fi
