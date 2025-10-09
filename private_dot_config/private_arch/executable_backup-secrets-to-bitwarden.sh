#!/bin/bash
set -e

# Check if Bitwarden session is active
if [ -z "$BW_SESSION" ]; then
    echo "ERROR: BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed"
    exit 1
fi

SECRETS_DIR="$HOME/backup-secrets"

if [ ! -d "$SECRETS_DIR" ]; then
    echo "ERROR: Directory $SECRETS_DIR does not exist"
    exit 1
fi

echo "==> Backing up secrets from $SECRETS_DIR to Bitwarden..."
echo ""

# Counter for stats
total=0
uploaded=0
skipped=0

# Loop through all files in the directory
for file in "$SECRETS_DIR"/*; do
    # Skip if not a file
    if [ ! -f "$file" ]; then
        continue
    fi

    total=$((total + 1))

    # Get filename without path
    filename=$(basename "$file")

    # Item name in Bitwarden
    item_name="Secret - $filename"

    echo "[$total] Processing: $filename"

    # Check if item already exists
    if bw get item "$item_name" --session "$BW_SESSION" &>/dev/null; then
        echo "    ⏭ Already exists in Bitwarden, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    # Read file contents
    file_contents=$(cat "$file")

    # Create secure note in Bitwarden
    jq -n \
      --arg name "$item_name" \
      --arg notes "$file_contents" \
      '{
        organizationId: null,
        folderId: null,
        type: 2,
        name: $name,
        notes: $notes,
        secureNote: {
          type: 0
        }
      }' | bw encode | bw create item --session "$BW_SESSION" > /dev/null

    echo "    ✓ Uploaded to Bitwarden"
    uploaded=$((uploaded + 1))
done

echo ""
echo "==> Backup complete!"
echo "    Total files: $total"
echo "    Uploaded: $uploaded"
echo "    Skipped (already exist): $skipped"
