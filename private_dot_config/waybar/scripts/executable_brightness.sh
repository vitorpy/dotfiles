#!/bin/bash
# Get current and max brightness
CURRENT=$(brightnessctl get)
MAX=$(brightnessctl max)
# Calculate percentage
BRIGHTNESS=$((CURRENT * 100 / MAX))
echo "󰃞 $BRIGHTNESS%"
