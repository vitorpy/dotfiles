# Secret Management with Keeper Commander

This setup integrates Keeper Password Manager with your dotfiles for secure secret management.

## Quick Setup

Run the setup script to install and configure Keeper Commander:

```bash
~/.local/share/chezmoi/scripts/setup-keeper-secrets.sh
```

## How It Works

1. **Fish Shell Integration**: The `~/.config/fish/secrets.fish` file automatically loads secrets from Keeper when you start a new shell session.

2. **Secrets Managed**:
   - `ANTHROPIC_API_KEY` - For AI assistant tools
   - `NPM_TOKEN` - For npm package management

3. **No Templates Required**: Unlike typical chezmoi templates, this uses plain Fish shell checks to load secrets dynamically.

## Configuration

After running the setup script, you need to:

1. **Find your Keeper record UIDs**:
   ```bash
   keeper list
   # Or for JSON output:
   keeper list --format=json | jq -r '.[] | {title, record_uid}'
   ```

2. **Update the UIDs in `secrets.fish`**:
   Edit `~/.config/fish/secrets.fish` and replace:
   - `ANTHROPIC_RECORD_UID` with your Anthropic API key record UID
   - `NPM_RECORD_UID` with your NPM token record UID

## Manual Fallback

If you prefer not to use Keeper, create a local secrets file:

```bash
cat > ~/.config/fish/secrets.local.fish << 'EOF'
set -gx ANTHROPIC_API_KEY "your-api-key-here"
set -gx NPM_TOKEN "your-npm-token-here"
EOF

chmod 600 ~/.config/fish/secrets.local.fish
```

## Security Notes

- Secrets are never committed to the repository
- Keeper Commander stores credentials encrypted locally
- The `secrets.fish` file only contains the logic, not actual secrets
- Local fallback files (`.local.fish`) should be in `.gitignore`

## Testing

To verify secrets are loaded correctly:

```bash
# Start a new fish shell
fish

# Check if secrets are loaded
echo $ANTHROPIC_API_KEY
echo $NPM_TOKEN
```

## Troubleshooting

- **Keeper not found**: Run the setup script
- **Not logged in**: Run `keeper login`
- **Record not found**: Check the UID with `keeper list`
- **Python errors**: Ensure Python 3 is installed