/home/linuxbrew/.linuxbrew/bin/brew shellenv | source

if status is-interactive
    set fish_greeting
    # Commands to run in interactive sessions can go here
    starship init fish | source
    direnv hook fish | source
end

fish_add_path /home/vpb/.local/bin

fish_add_path /home/vpb/.rvm/bin
rvm default

fish_add_path /home/vpb/.local/share/solana/install/active_release/bin
fish_add_path /home/vpb/.foundry/bin

fish_add_path /home/vpb/.cargo/bin

nvm use latest
pyenv init - | source

fish_add_path -a /home/vpb/.config/.foundry/bin
