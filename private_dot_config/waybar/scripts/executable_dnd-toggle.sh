#!/bin/bash

# Toggle DND mode - use -s to SET mode (not add)
if makoctl mode | grep -q "do-not-disturb"; then
    # DND is on, turn it off
    makoctl mode -s default
else
    # DND is off, turn it on
    makoctl mode -s do-not-disturb
fi

# Give a small delay for the mode to be updated
sleep 0.1

# Check if DND is now active and return appropriate JSON
if makoctl mode | grep -q "do-not-disturb"; then
    echo "{\"text\": \"\", \"tooltip\": \"Do Not Disturb: ON\"}"
else
    echo "{\"text\": \"\", \"tooltip\": \"Do Not Disturb: OFF\"}"
fi
