#!/bin/bash

# Keeper Commander + Chezmoi Integration Setup Script
# This script sets up Keeper Commander CLI for secret management in dotfiles

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Keeper Commander + Chezmoi Secret Management Setup${NC}"
echo "=================================================="
echo ""

# Check Python availability
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Python 3 is required but not installed.${NC}"
    exit 1
fi

# Function to install Keeper Commander
install_keeper() {
    echo -e "${YELLOW}Installing Keeper Commander...${NC}"

    # Install in user space to avoid system conflicts
    pip3 install --user keepercommander

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Keeper Commander installed successfully${NC}"

        # Add pip user bin to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo -e "${YELLOW}Adding ~/.local/bin to PATH...${NC}"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
            echo 'set -x PATH $HOME/.local/bin $PATH' >> ~/.config/fish/config.fish 2>/dev/null || true
            export PATH="$HOME/.local/bin:$PATH"
        fi
    else
        echo -e "${RED}Failed to install Keeper Commander${NC}"
        exit 1
    fi
}

# Function to configure Keeper
configure_keeper() {
    echo ""
    echo -e "${YELLOW}Configuring Keeper Commander...${NC}"
    echo "You'll need your Keeper credentials to continue."
    echo ""

    # Initialize Keeper configuration
    keeper login

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Keeper configured successfully${NC}"
    else
        echo -e "${RED}Keeper configuration failed${NC}"
        exit 1
    fi
}

# Function to create chezmoi integration scripts
create_chezmoi_integration() {
    echo ""
    echo -e "${YELLOW}Creating Chezmoi integration...${NC}"

    # Create keeper helper script for chezmoi
    cat > ~/.local/bin/chezmoi-keeper-get << 'EOF'
#!/bin/bash
# Helper script to get secrets from Keeper for chezmoi templates
# Usage: chezmoi-keeper-get <record_uid> <field>

RECORD_UID="$1"
FIELD="$2"

if [ -z "$RECORD_UID" ] || [ -z "$FIELD" ]; then
    echo "Usage: chezmoi-keeper-get <record_uid> <field>"
    exit 1
fi

# Get the secret from Keeper
keeper get "$RECORD_UID" --format=json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if '$FIELD' == 'password':
        print(data.get('password', ''), end='')
    elif '$FIELD' == 'login':
        print(data.get('login', ''), end='')
    else:
        # Look in custom fields
        for field in data.get('custom', []):
            if field.get('name') == '$FIELD':
                print(field.get('value', ''), end='')
                break
except:
    sys.exit(1)
"
EOF

    chmod +x ~/.local/bin/chezmoi-keeper-get

    echo -e "${GREEN}✓ Chezmoi-Keeper helper script created${NC}"
}

# Function to create example template
create_example_template() {
    echo ""
    echo -e "${YELLOW}Creating example template...${NC}"

    # Create example directory if it doesn't exist
    mkdir -p ~/.local/share/chezmoi/.examples

    # Create example template for SSH config
    cat > ~/.local/share/chezmoi/.examples/ssh_config.tmpl << 'EOF'
# Example SSH Config Template with Keeper Secrets
# To use this, copy to private_dot_ssh/config.tmpl

Host myserver
    HostName server.example.com
    User myuser
    # Get password from Keeper (replace RECORD_UID with actual UID)
    # You can find the UID by running: keeper list --format=json
    # Password: {{ output "chezmoi-keeper-get" "RECORD_UID" "password" | trim }}

Host github.com
    User git
    # Example of getting SSH key passphrase from Keeper
    # IdentityFile ~/.ssh/id_ed25519
    # {{ $passphrase := output "chezmoi-keeper-get" "GITHUB_KEY_UID" "passphrase" | trim }}
EOF

    # Create example for environment variables
    cat > ~/.local/share/chezmoi/.examples/env_secrets.tmpl << 'EOF'
# Example Environment Variables Template with Keeper Secrets
# To use this, copy to desired location with .tmpl extension

# API Keys from Keeper
export ANTHROPIC_API_KEY="{{ output "chezmoi-keeper-get" "ANTHROPIC_RECORD_UID" "password" | trim }}"
export OPENAI_API_KEY="{{ output "chezmoi-keeper-get" "OPENAI_RECORD_UID" "password" | trim }}"
export NPM_TOKEN="{{ output "chezmoi-keeper-get" "NPM_RECORD_UID" "password" | trim }}"

# Database credentials
export DB_USER="{{ output "chezmoi-keeper-get" "DB_RECORD_UID" "login" | trim }}"
export DB_PASS="{{ output "chezmoi-keeper-get" "DB_RECORD_UID" "password" | trim }}"
EOF

    echo -e "${GREEN}✓ Example templates created in ~/.local/share/chezmoi/.examples/${NC}"
}

# Function to show how to use
show_usage() {
    echo ""
    echo -e "${GREEN}Setup Complete!${NC}"
    echo ""
    echo "How to use Keeper with Chezmoi:"
    echo "================================"
    echo ""
    echo "1. Find a record's UID in Keeper:"
    echo "   ${YELLOW}keeper list --format=json | jq -r '.[] | select(.title==\"My Record\") | .record_uid'${NC}"
    echo ""
    echo "2. Create a template file (add .tmpl extension):"
    echo "   ${YELLOW}chezmoi add --template ~/.config/myapp/config${NC}"
    echo ""
    echo "3. In the template, use Keeper to get secrets:"
    echo '   ${YELLOW}password = "{{ output "chezmoi-keeper-get" "RECORD_UID" "password" | trim }}"${NC}'
    echo ""
    echo "4. Apply templates:"
    echo "   ${YELLOW}chezmoi apply${NC}"
    echo ""
    echo "Example templates have been created in:"
    echo "  ${YELLOW}~/.local/share/chezmoi/.examples/${NC}"
}

# Main execution
main() {
    # Check if Keeper Commander is already installed
    if command -v keeper &> /dev/null; then
        echo -e "${GREEN}✓ Keeper Commander is already installed${NC}"
    else
        install_keeper
    fi

    # Check if Keeper is configured
    if keeper whoami &> /dev/null 2>&1; then
        echo -e "${GREEN}✓ Keeper is already configured${NC}"
    else
        configure_keeper
    fi

    # Create chezmoi integration
    create_chezmoi_integration

    # Create examples
    create_example_template

    # Show usage
    show_usage
}

# Run main function
main