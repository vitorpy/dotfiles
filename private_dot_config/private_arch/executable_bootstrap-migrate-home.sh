#!/bin/bash
set -euo pipefail

SOURCE_HOME="${1:-}"
TARGET_HOME="${2:-}"
TARGET_USERNAME="${3:-}"

require_arg() {
  local value="$1"
  local name="$2"
  if [[ -z "$value" ]]; then
    echo "ERROR: Missing required argument: $name" >&2
    exit 1
  fi
}

require_arg "$SOURCE_HOME" "SOURCE_HOME"
require_arg "$TARGET_HOME" "TARGET_HOME"
require_arg "$TARGET_USERNAME" "TARGET_USERNAME"

if [[ ! -d "$SOURCE_HOME" ]]; then
  echo "ERROR: Source home directory not found: $SOURCE_HOME" >&2
  exit 1
fi

mkdir -p "$TARGET_HOME"

echo "==> Migrating home directory..."
echo "    Source: $SOURCE_HOME"
echo "    Target: $TARGET_HOME"

rsync -aHAX --info=progress2 \
  --exclude='.cache/' \
  --exclude='.local/share/Trash/' \
  --exclude='.gnupg/S.gpg-agent' \
  --exclude='.gnupg/S.gpg-agent.*' \
  --exclude='.ssh/agent.*' \
  "$SOURCE_HOME"/ "$TARGET_HOME"/

mkdir -p "$TARGET_HOME/.local/state"
printf 'source=%s\n' "$SOURCE_HOME" > "$TARGET_HOME/.local/state/arch-home-migration"

chown -R "$TARGET_USERNAME:$TARGET_USERNAME" "$TARGET_HOME"

echo "==> Home migration complete."
