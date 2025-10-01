# Fish Shell Secrets Configuration
# This file sources secrets from Bitwarden CLI if available

# Check if Bitwarden CLI is available and we have a session
if command -v bw &> /dev/null
    # Check if BW_SESSION is set
    if test -n "$BW_SESSION"
        # Helper function to get secret from Bitwarden
        function get_bitwarden_secret
            set -l item_name $argv[1]

            # Get the secret password field and suppress errors
            bw get password "$item_name" --session "$BW_SESSION" 2>/dev/null
        end

        # Set ANTHROPIC_API_KEY
        set -l anthropic_key (get_bitwarden_secret "Anthropic API Key")
        if test -n "$anthropic_key"
            set -gx ANTHROPIC_API_KEY "$anthropic_key"
        end

        # Set NPM_TOKEN for npmrc
        set -l npm_token (get_bitwarden_secret "NPM Registry Token")
        if test -n "$npm_token"
            set -gx NPM_TOKEN "$npm_token"
        end

    else
        # BW_SESSION not set
        echo "BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)" >&2
    end
else
    # Bitwarden CLI not installed
    echo "Bitwarden CLI not installed. Run: brew install bitwarden-cli" >&2
end