source ~/.config/zshrc.d/zsh_settings.zsh

source ~/.config/zshrc.d/aliases.zsh
source ~/.config/zshrc.d/environment_vars.zsh
source ~/.config/zshrc.d/plugins.zsh
source ~/.config/zshrc.d/zsh_functions.zsh

if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then . $HOME/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

# Accept autosuggestions with ctrl-space
bindkey '^ ' autosuggest-accept
