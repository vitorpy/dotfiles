#!/bin/bash

# Check if DND is active and display appropriate icon
if makoctl mode | grep -q "do-not-disturb"; then
    echo "{\"text\": \"\", \"tooltip\": \"Do Not Disturb: ON\"}"
else
    echo "{\"text\": \"\", \"tooltip\": \"Do Not Disturb: OFF\"}"
fi