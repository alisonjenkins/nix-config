source ~/.config/zshrc.d/zsh_settings.zsh

# source ~/.config/zshrc.d/p10k.zsh

source ~/.config/zshrc.d/aliases.zsh
source ~/.config/zshrc.d/environment_vars.zsh
source ~/.config/zshrc.d/plugins.zsh
source ~/.config/zshrc.d/zsh_functions.zsh

if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then . $HOME/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Setup mappings
# Accept autosuggestions with ctrl-space
bindkey '^ ' autosuggest-accept
