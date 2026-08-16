#!/usr/bin/env bash

set -u

current=$(brightnessctl get 2>/dev/null) || exit 1
maximum=$(brightnessctl max 2>/dev/null) || exit 1

[[ $current =~ ^[0-9]+$ && $maximum =~ ^[1-9][0-9]*$ ]] || exit 1

percentage=$((current * 100 / maximum))
jq -cn --argjson percent "$percentage" '{percent: $percent}'
