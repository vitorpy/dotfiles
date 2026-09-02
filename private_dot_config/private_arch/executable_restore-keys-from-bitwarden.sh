#!/bin/bash
set -euo pipefail

umask 077

# Check if Bitwarden session is active
if [[ -z "${BW_SESSION:-}" ]]; then
    echo "ERROR: BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

# Parse arguments
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    TEMP_DIR=$(mktemp -d /tmp/bw-restore.XXXXXX)
    trap 'rm -rf -- "$TEMP_DIR"' EXIT
    SSH_DIR="$TEMP_DIR/.ssh"
    echo "==> DRY RUN MODE - restoring to $TEMP_DIR"
else
    SSH_DIR="$HOME/.ssh"
    echo "==> Restoring SSH keys from Bitwarden..."
fi

# Create .ssh directory if it doesn't exist
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Restore SSH keys
echo "==> Restoring SSH keys..."

# Resolve a single item by exact title. Bitwarden's `get item <search>` is
# ambiguous when several item names contain the same word (for example, Git).
get_bw_item_by_exact_name() {
    local item_name="$1"

    bw list items --search "$item_name" |
        jq -cer --arg item_name "$item_name" '
            [.[] | select(.name == $item_name)] as $matches
            | if ($matches | length) == 1 then $matches[0] else empty end
        '
}

# Extract and atomically restore an SSH key from either a native Bitwarden SSH
# key item or the legacy secure-note format used by older backups.
restore_ssh_key() {
    local item_name="$1"
    local key_file="$2"
    local item_json notes private_key public_key
    local private_tmp public_tmp private_fingerprint public_fingerprint

    echo "  - Restoring $item_name..."

    if ! item_json="$(get_bw_item_by_exact_name "$item_name" 2>/dev/null)"; then
        echo "    WARNING: $item_name was not found uniquely in Bitwarden, skipping"
        return 1
    fi

    if [[ "$(jq -r '.type' <<< "$item_json")" == "5" ]]; then
        if ! private_key="$(jq -er '.sshKey.privateKey // empty' <<< "$item_json")" ||
            ! public_key="$(jq -er '.sshKey.publicKey // empty' <<< "$item_json")"; then
            echo "    WARNING: $item_name does not contain a complete native SSH key, skipping"
            return 1
        fi
    else
        notes="$(jq -r '.notes // empty' <<< "$item_json")"
        private_key="$(
            printf '%s\n' "$notes" |
                sed -n '/Private Key:/,/Public Key:/p' |
                sed '1d;$d'
        )"
        public_key="$(
            printf '%s\n' "$notes" |
                sed -n '/Public Key:/,$p' |
                sed '1d'
        )"
    fi
    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo "    WARNING: $item_name does not contain a complete SSH key, skipping"
        return 1
    fi

    # Check if files already exist (skip in dry-run)
    if [[ "$DRY_RUN" == "false" && -f "$SSH_DIR/$key_file" ]]; then
        read -r -p "    $key_file already exists. Overwrite? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "    Skipping $key_file"
            return
        fi
    fi

    private_tmp="$(mktemp "$SSH_DIR/.${key_file}.private.XXXXXX")"
    public_tmp="$(mktemp "$SSH_DIR/.${key_file}.public.XXXXXX")"
    printf '%s\n' "$private_key" > "$private_tmp"
    printf '%s\n' "$public_key" > "$public_tmp"
    chmod 600 "$private_tmp"
    chmod 644 "$public_tmp"

    if ! private_fingerprint="$(ssh-keygen -lf "$private_tmp" 2>/dev/null | awk '{ print $2 }')" ||
        [[ -z "$private_fingerprint" ]]; then
        rm -f -- "$private_tmp" "$public_tmp"
        echo "    WARNING: invalid private SSH key in $item_name"
        return 1
    fi
    if ! public_fingerprint="$(ssh-keygen -lf "$public_tmp" 2>/dev/null | awk '{ print $2 }')" ||
        [[ -z "$public_fingerprint" ]]; then
        rm -f -- "$private_tmp" "$public_tmp"
        echo "    WARNING: invalid public SSH key in $item_name"
        return 1
    fi
    if [[ "$private_fingerprint" != "$public_fingerprint" ]]; then
        rm -f -- "$private_tmp" "$public_tmp"
        echo "    WARNING: private and public fingerprints differ for $item_name"
        return 1
    fi

    mv "$private_tmp" "$SSH_DIR/$key_file"
    mv "$public_tmp" "$SSH_DIR/$key_file.pub"
    echo "    ✓ Restored private key: $SSH_DIR/$key_file"
    echo "    ✓ Restored public key: $SSH_DIR/$key_file.pub"
}

# Restore SSH keys.
# Prefer the current native SSH-key item, then fall back to historical secure
# notes so fresh restores remain compatible without a vault migration.
if ! restore_ssh_key "Git" "vitorpy"; then
    if ! restore_ssh_key "SSH Key - vitorpy" "vitorpy"; then
        restore_ssh_key "SSH Key - github" "vitorpy"
    fi
fi
restore_ssh_key "SSH Key - id_ed25519" "id_ed25519"

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    echo "==> DRY RUN successful - temporary files in $TEMP_DIR"
    echo ""
    echo "Directory contents:"
    ls -lah "$TEMP_DIR"
    ls -lah "$SSH_DIR"
    echo "==> Temporary files will be removed automatically"
else
    echo "==> Restore complete!"
    echo ""
    echo "SSH keys restored to ~/.ssh/"
    echo ""
    echo "To add SSH keys to ssh-agent, run:"
    echo "  ssh-add ~/.ssh/vitorpy"
    echo "  ssh-add ~/.ssh/id_ed25519"
fi
