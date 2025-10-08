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

echo "==> Backing up SSH and GPG keys to Bitwarden..."

# Backup SSH keys
echo "==> Backing up SSH keys..."

# SSH key: github
if [ -f "$HOME/.ssh/github" ]; then
    GITHUB_KEY=$(cat "$HOME/.ssh/github")
    GITHUB_PUB=$(cat "$HOME/.ssh/github.pub")

    bw get item "SSH Key - github" --session "$BW_SESSION" &>/dev/null && \
        echo "  - SSH Key 'github' already exists in Bitwarden, skipping" || \
        (jq -n \
          --arg name "SSH Key - github" \
          --arg notes "Private Key:
$GITHUB_KEY

Public Key:
$GITHUB_PUB" \
          '{
            organizationId: null,
            folderId: null,
            type: 2,
            name: $name,
            notes: $notes,
            secureNote: {
              type: 0
            }
          }' | bw encode | bw create item --session "$BW_SESSION" > /dev/null && echo "  ✓ Backed up SSH key: github")
fi

# SSH key: id_ed25519
if [ -f "$HOME/.ssh/id_ed25519" ]; then
    ID_KEY=$(cat "$HOME/.ssh/id_ed25519")
    ID_PUB=$(cat "$HOME/.ssh/id_ed25519.pub")

    bw get item "SSH Key - id_ed25519" --session "$BW_SESSION" &>/dev/null && \
        echo "  - SSH Key 'id_ed25519' already exists in Bitwarden, skipping" || \
        (jq -n \
          --arg name "SSH Key - id_ed25519" \
          --arg notes "Private Key:
$ID_KEY

Public Key:
$ID_PUB" \
          '{
            organizationId: null,
            folderId: null,
            type: 2,
            name: $name,
            notes: $notes,
            secureNote: {
              type: 0
            }
          }' | bw encode | bw create item --session "$BW_SESSION" > /dev/null && echo "  ✓ Backed up SSH key: id_ed25519")
fi

# Backup GPG keys
echo "==> Backing up GPG keys..."

# GPG key: vitor@vitorpy.com (04983CBC2428686A)
GPG1_KEY_ID="04983CBC2428686A"
GPG1_NAME="GPG Key - vitor@vitorpy.com"
GPG1_PRIVATE=$(gpg --export-secret-keys --armor "$GPG1_KEY_ID")
GPG1_PUBLIC=$(gpg --export --armor "$GPG1_KEY_ID")

bw get item "$GPG1_NAME" --session "$BW_SESSION" &>/dev/null && \
    echo "  - GPG Key '$GPG1_NAME' already exists in Bitwarden, skipping" || \
    (jq -n \
      --arg name "$GPG1_NAME" \
      --arg keyid "$GPG1_KEY_ID" \
      --arg private "$GPG1_PRIVATE" \
      --arg public "$GPG1_PUBLIC" \
      --arg notes "Key ID: \($keyid)

Private Key:
\($private)

Public Key:
\($public)" \
      '{
        organizationId: null,
        folderId: null,
        type: 2,
        name: $name,
        notes: $notes,
        secureNote: {
          type: 0
        }
      }' | bw encode | bw create item --session "$BW_SESSION" > /dev/null && echo "  ✓ Backed up GPG key: $GPG1_NAME")

# GPG key: vitor@darklakelabs.com (C32867843FDB3933)
GPG2_KEY_ID="C32867843FDB3933"
GPG2_NAME="GPG Key - vitor@darklakelabs.com"
GPG2_PRIVATE=$(gpg --export-secret-keys --armor "$GPG2_KEY_ID")
GPG2_PUBLIC=$(gpg --export --armor "$GPG2_KEY_ID")

bw get item "$GPG2_NAME" --session "$BW_SESSION" &>/dev/null && \
    echo "  - GPG Key '$GPG2_NAME' already exists in Bitwarden, skipping" || \
    (jq -n \
      --arg name "$GPG2_NAME" \
      --arg keyid "$GPG2_KEY_ID" \
      --arg private "$GPG2_PRIVATE" \
      --arg public "$GPG2_PUBLIC" \
      --arg notes "Key ID: \($keyid)

Private Key:
\($private)

Public Key:
\($public)" \
      '{
        organizationId: null,
        folderId: null,
        type: 2,
        name: $name,
        notes: $notes,
        secureNote: {
          type: 0
        }
      }' | bw encode | bw create item --session "$BW_SESSION" > /dev/null && echo "  ✓ Backed up GPG key: $GPG2_NAME")

echo ""
echo "==> Backup complete! Your keys are now stored in Bitwarden."
echo ""
echo "IMPORTANT: Verify the backups in Bitwarden before deleting local keys!"
