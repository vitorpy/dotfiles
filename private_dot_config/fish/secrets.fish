# Fish Shell Secrets Configuration
# This file sources secrets from Keeper Commander if available

# Check if Keeper Commander is available and configured
if command -v keeper &> /dev/null
    # Set keeper config path
    set -l keeper_config "$HOME/.keeper/config.json"

    # Check if config exists and we can access Keeper
    if test -f "$keeper_config"

        # Helper function to get secret from Keeper
        function get_keeper_secret
            set -l record_uid $argv[1]
            set -l field $argv[2]
            set -l keeper_config "$HOME/.keeper/config.json"

            # Get the secret and suppress errors
            keeper --config "$keeper_config" get "$record_uid" --format=json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if '$field' == 'password':
        print(data.get('password', ''), end='')
    elif '$field' == 'login':
        print(data.get('login', ''), end='')
    else:
        # Look in custom fields
        for field in data.get('custom', []):
            if field.get('name') == '$field':
                print(field.get('value', ''), end='')
                break
except:
    pass
"
        end

        # Set ANTHROPIC_API_KEY
        set -l anthropic_key (get_keeper_secret "r_HJvm0objPd0IVpJS6sHw" "password")
        if test -n "$anthropic_key"
            set -gx ANTHROPIC_API_KEY "$anthropic_key"
        end

        # Set NPM_TOKEN for npmrc
        set -l npm_token (get_keeper_secret "UXmsbgffjKU-e3BnTZ1MpA" "password")
        if test -n "$npm_token"
            set -gx NPM_TOKEN "$npm_token"
        end

    else
        # Keeper config not found
        echo "Keeper config not found at ~/.keeper/config.json. Run: keeper --config ~/.keeper/config.json login" >&2
    end
else
    # Keeper not installed - use fallback or prompt
    echo "Keeper Commander not installed. Run: ~/.local/share/chezmoi/scripts/setup-keeper-secrets.sh" >&2
end

# Fallback: source local secrets file if it exists (for non-Keeper setup)
if test -f ~/.config/fish/secrets.local.fish
    source ~/.config/fish/secrets.local.fish
end