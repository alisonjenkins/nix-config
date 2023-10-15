# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source ~/.config/zshrc.d/completion.zsh
source ~/.config/zshrc.d/environment_vars.zsh
source ~/.config/zshrc.d/powerlevel10k.zsh
source ~/.config/zshrc.d/aliases.zsh
source ~/.config/zshrc.d/plugins.zsh
source ~/.config/zshrc.d/bash_helpers.zsh
source ~/.config/zshrc.d/zsh_functions.zsh
source ~/.config/zshrc.d/zsh_settings.zsh
if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then . $HOME/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Setup mappings
# Accept autosuggestions with ctrl-space
bindkey '^ ' autosuggest-accept
