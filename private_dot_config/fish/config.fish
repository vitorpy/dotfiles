fish_add_path $HOME/.local/bin

# ANTHROPIC_API_KEY should be set via environment or secure method
if status is-interactive
    set fish_greeting
    set EDITOR nvim

    # System update alias
    alias update="$HOME/.config/arch/update-system.sh"

    # GNOME Control Center (works outside GNOME)
    alias gnome-settings="env XDG_CURRENT_DESKTOP=GNOME gnome-control-center"

    # Commands to run in interactive sessions can go here
    starship init fish | source
    direnv hook fish | source

    # zoxide - smarter cd command
    zoxide init fish | source
    alias cd="z"
end

# NVM Setup
set -x NVM_DIR $HOME/.nvm

# Load nvm from Arch package
if test -e /usr/share/nvm/init-nvm.sh
    bass source /usr/share/nvm/init-nvm.sh
end

# pnpm
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

# zvm (Zig Version Manager)
fish_add_path $HOME/.zvm/bin

