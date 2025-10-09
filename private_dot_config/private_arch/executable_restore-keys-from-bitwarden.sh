#!/bin/bash
set -e

# Check if Bitwarden session is active
if [ -z "$BW_SESSION" ]; then
    echo "ERROR: BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

# Parse arguments
DRY_RUN=false
if [ "$1" == "--dry-run" ]; then
    DRY_RUN=true
    TEMP_DIR=$(mktemp -d /tmp/bw-restore.XXXXXX)
    SSH_DIR="$TEMP_DIR/.ssh"
    GPG_HOME="$TEMP_DIR/.gnupg"
    echo "==> DRY RUN MODE - restoring to $TEMP_DIR"
else
    SSH_DIR="$HOME/.ssh"
    GPG_HOME="$HOME/.gnupg"
    echo "==> Restoring SSH and GPG keys from Bitwarden..."
fi

# Create .ssh directory if it doesn't exist
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Restore SSH keys
echo "==> Restoring SSH keys..."

# Function to extract and restore SSH key
restore_ssh_key() {
    local item_name="$1"
    local key_file="$2"

    echo "  - Restoring $item_name..."

    # Get the item from Bitwarden
    local notes=$(bw get item "$item_name" --session "$BW_SESSION" 2>/dev/null | jq -r '.notes')

    if [ -z "$notes" ] || [ "$notes" == "null" ]; then
        echo "    WARNING: $item_name not found in Bitwarden, skipping"
        return
    fi

    # Extract private key (between "Private Key:" and "Public Key:")
    local private_key=$(echo "$notes" | sed -n '/Private Key:/,/Public Key:/p' | sed '1d;$d')

    # Extract public key (after "Public Key:")
    local public_key=$(echo "$notes" | sed -n '/Public Key:/,$p' | sed '1d')

    # Check if files already exist (skip in dry-run)
    if [ "$DRY_RUN" == "false" ] && [ -f "$SSH_DIR/$key_file" ]; then
        read -p "    $key_file already exists. Overwrite? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "    Skipping $key_file"
            return
        fi
    fi

    # Write private key
    echo "$private_key" > "$SSH_DIR/$key_file"
    chmod 600 "$SSH_DIR/$key_file"
    echo "    ✓ Restored private key: $SSH_DIR/$key_file"

    # Write public key
    echo "$public_key" > "$SSH_DIR/$key_file.pub"
    chmod 644 "$SSH_DIR/$key_file.pub"
    echo "    ✓ Restored public key: $SSH_DIR/$key_file.pub"
}

# Restore SSH keys
restore_ssh_key "SSH Key - github" "github"
restore_ssh_key "SSH Key - id_ed25519" "id_ed25519"

# Restore GPG keys
echo "==> Restoring GPG keys..."

# Function to restore GPG key
restore_gpg_key() {
    local item_name="$1"

    echo "  - Restoring $item_name..."

    # Get the item from Bitwarden
    local notes=$(bw get item "$item_name" --session "$BW_SESSION" 2>/dev/null | jq -r '.notes')

    if [ -z "$notes" ] || [ "$notes" == "null" ]; then
        echo "    WARNING: $item_name not found in Bitwarden, skipping"
        return
    fi

    # Extract private key (between "Private Key:" and "Public Key:")
    local private_key=$(echo "$notes" | sed -n '/Private Key:/,/Public Key:/p' | sed '1d;$d')

    if [ "$DRY_RUN" == "true" ]; then
        # In dry-run, just save to file
        local safe_name=$(echo "$item_name" | sed 's/[^a-zA-Z0-9]/_/g')
        echo "$private_key" > "$TEMP_DIR/${safe_name}.asc"
        echo "    ✓ Would import GPG key: $item_name (saved to $TEMP_DIR/${safe_name}.asc)"
    else
        # Import private key
        echo "$private_key" | gpg --import 2>&1 | grep -v "key.*unchanged" || true
        echo "    ✓ Imported GPG key: $item_name"
    fi
}

# Restore GPG keys
restore_gpg_key "GPG Key - vitor@vitorpy.com"
restore_gpg_key "GPG Key - vitor@darklakelabs.com"

echo ""
if [ "$DRY_RUN" == "true" ]; then
    echo "==> DRY RUN - Files created in $TEMP_DIR"
    echo ""
    echo "Directory contents:"
    ls -lah "$TEMP_DIR"
    ls -lah "$SSH_DIR"
    echo ""
    read -p "Press Enter to clean up and delete $TEMP_DIR..."
    rm -rf "$TEMP_DIR"
    echo "✓ Cleaned up temporary directory"
else
    echo "==> Restore complete!"
    echo ""
    echo "SSH keys restored to ~/.ssh/"
    echo "GPG keys imported to GPG keyring"
    echo ""
    echo "To add SSH keys to ssh-agent, run:"
    echo "  ssh-add ~/.ssh/github"
    echo "  ssh-add ~/.ssh/id_ed25519"
fi
