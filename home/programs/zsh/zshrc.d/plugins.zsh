# mkdir -p ~/.local/share/zinit
# test -d ~/.local/share/zinit/bin || git clone https://github.com/zdharma-continuum/zinit.git ~/.local/share/zinit/bin

# Configure zinit
# declare -A ZINIT
# ZINIT[BIN_DIR]=~/.local/share/zinit/bin
# ZINIT[HOME_DIR]=~/.local/share/zinit

# source ~/.local/share/zinit/bin/zinit.zsh

# export _ZL_MATCH_MODE=1

# zinit ice depth=1; zinit light romkatv/powerlevel10k

# Load sensitive envvars
if [[ -e ~/git/secret-envvars ]]; then
  eval $(~/git/secret-envvars/target/release/get-secrets)
fi

# zinit ice from"gh-r" as"program" atclone"./starship init zsh > init.zsh" atpull"%atclone" src"init.zsh"
# zinit light starship/starship

# _evalcache starship init zsh
_evalcache zoxide init zsh
_evalcache direnv hook zsh
_evalcache mcfly init zsh

# smartcache comp rustup completions zsh

# zinit ice lucid wait
# zinit snippet OMZP::fzf


# autoload -Uz _zinit
# (( ${+_comps} )) && _comps[zinit]=_zinit
