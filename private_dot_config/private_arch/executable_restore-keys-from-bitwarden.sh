#!/bin/bash
set -e

# Check if Bitwarden session is active
if [ -z "$BW_SESSION" ]; then
    echo "ERROR: BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

echo "==> Restoring SSH and GPG keys from Bitwarden..."

# Create .ssh directory if it doesn't exist
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

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

    # Check if files already exist
    if [ -f "$HOME/.ssh/$key_file" ]; then
        read -p "    $key_file already exists. Overwrite? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "    Skipping $key_file"
            return
        fi
    fi

    # Write private key
    echo "$private_key" > "$HOME/.ssh/$key_file"
    chmod 600 "$HOME/.ssh/$key_file"
    echo "    ✓ Restored private key: ~/.ssh/$key_file"

    # Write public key
    echo "$public_key" > "$HOME/.ssh/$key_file.pub"
    chmod 644 "$HOME/.ssh/$key_file.pub"
    echo "    ✓ Restored public key: ~/.ssh/$key_file.pub"
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

    # Import private key
    echo "$private_key" | gpg --import 2>&1 | grep -v "key.*unchanged" || true
    echo "    ✓ Imported GPG key: $item_name"
}

# Restore GPG keys
restore_gpg_key "GPG Key - vitor@vitorpy.com"
restore_gpg_key "GPG Key - vitor@darklakelabs.com"

echo ""
echo "==> Restore complete!"
echo ""
echo "SSH keys restored to ~/.ssh/"
echo "GPG keys imported to GPG keyring"
echo ""
echo "To add SSH keys to ssh-agent, run:"
echo "  ssh-add ~/.ssh/github"
echo "  ssh-add ~/.ssh/id_ed25519"
