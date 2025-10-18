fish_add_path /home/vitorpy/.local/bin

set OMAKUB_PATH /home/vitorpy/.local/share/omakub

# bun
set BUN_INSTALL "$HOME/.bun"
set PATH $BUN_INSTALL/bin $PATH

# ANTHROPIC_API_KEY should be set via environment or secure method

if status is-interactive
    set fish_greeting
    set EDITOR nvim

    # System update alias
    alias update="~/.config/arch/update-system.sh"

    # GNOME Control Center (works outside GNOME)
    alias gnome-settings="env XDG_CURRENT_DESKTOP=GNOME gnome-control-center"

    # Commands to run in interactive sessions can go here
    starship init fish | source
    direnv hook fish | source

    # zoxide - smarter cd command
    zoxide init fish | source
    alias cd="z"
end

export NARGO_HOME="/home/vitorpy/.nargo"

# NVM Setup
set -x NVM_DIR ~/.nvm

# Load nvm from Arch package
if test -e /usr/share/nvm/init-nvm.sh
    bass source /usr/share/nvm/init-nvm.sh
end

# pnpm
set -gx PNPM_HOME "/home/vitorpy/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end


# opencode
fish_add_path /home/vitorpy/.opencode/bin
