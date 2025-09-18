#!/bin/bash

# Toggle DND mode
makoctl mode -t do-not-disturb

# Give a small delay for the mode to be updated
sleep 0.1

# Check if DND is now active and return appropriate JSON
if makoctl mode | grep -q "do-not-disturb"; then
    echo "{\"text\": \"\", \"tooltip\": \"Do Not Disturb: ON\"}"
else
    echo "{\"text\": \"\", \"tooltip\": \"Do Not Disturb: OFF\"}"
fi