# Configure zinit
PLUGDIR=~/.config/zsh/plugins
mkdir -p ~/.local/share/zinit
declare -A ZINIT
ZINIT[BIN_DIR]=~/.local/share/zinit/bin
ZINIT[HOME_DIR]=~/.local/share/zinit

source ~/.config/zsh/plugins/zinit/zinit.zsh

export _ZL_MATCH_MODE=1

# Load sensitive envvars
if [[ -e ~/git/secret-envvars ]]; then
  eval $(~/git/secret-envvars/target/release/get-secrets)
fi

# Plugins
zinit light "$PLUGDIR/gitstatus"
zinit light "$PLUGDIR/powerlevel10k"
zinit light "$PLUGDIR/zsh-vi-mode"

PLUGINS=(
  "aws-plugin"
  "direnv"
  "exercism"
  "fzf"
  "fzf-tab"
  "kube-aliases"
  "omz-fluxcd-plugin"
  "tipz"
  "zoxide"
  "zsh-autosuggestions"
  "zsh-hints"
  "zsh-terraform"
)

for PLUGIN in "${PLUGINS[@]}"; do
  zinit ice wait"2" lucid
  zinit load "$PLUGDIR/$PLUGIN"
done

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
