/home/linuxbrew/.linuxbrew/bin/brew shellenv | source

fish_add_path /home/vitorpy/.local/bin

set NODE_OPTIONS --max-old-space-size=8192

# Created by `pipx` on 2024-04-12 12:49:16
set PATH $PATH /home/vitorpy/.local/bin
set OMAKUB_PATH /home/vitorpy/.local/share/omakub

# bun
set BUN_INSTALL "$HOME/.bun"
set PATH $BUN_INSTALL/bin $PATH

# Android SDK
set PATH $PATH /home/vitorpy/Android/Sdk/platform-tools
set PATH $PATH /home/vitorpy/android-studio/bin

# ANTHROPIC_API_KEY should be set via environment or secure method

if status is-interactive
    set fish_greeting
    set EDITOR nvim
    set GTK_THEME "Yaru:dark"
    set HOMEBREW_NO_ENV_HINTS
    set QT_QPA_PLATFORMTHEME gnome
    set QT_STYLE_OVERRIDE Adwaita-Dark
    set MOZ_ENABLE_WAYLAND 0

    # Commands to run in interactive sessions can go here
    starship init fish | source
    direnv hook fish | source
end

export NARGO_HOME="/home/vitorpy/.nargo"

# NVM Setup
set -x NVM_DIR ~/.nvm

# Load nvm automatically if it exists
if test -e ~/.nvm/nvm.sh
    load_nvm
end

# pnpm
set -gx PNPM_HOME "/home/vitorpy/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

