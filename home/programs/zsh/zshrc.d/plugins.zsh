mkdir -p ~/.local/share/zinit
test -d ~/.local/share/zinit/bin || git clone https://github.com/zdharma-continuum/zinit.git ~/.local/share/zinit/bin

# Configure zinit
declare -A ZINIT
ZINIT[BIN_DIR]=~/.local/share/zinit/bin
ZINIT[HOME_DIR]=~/.local/share/zinit

source ~/.local/share/zinit/bin/zinit.zsh

export _ZL_MATCH_MODE=1

# zinit ice depth=1; zinit light romkatv/powerlevel10k

# Load sensitive envvars
if [[ -e ~/git/secret-envvars ]]; then
  eval $(~/git/secret-envvars/target/release/get-secrets)
fi

# zinit ice from"gh-r" as"program" atclone"./starship init zsh > init.zsh" atpull"%atclone" src"init.zsh"
# zinit light starship/starship

# Plugins
zinit load Aloxaf/fzf-tab
zinit load alanjjenkins/kube-aliases
zinit load fabiokiatkowski/exercism.plugin.zsh
zinit load joepvd/zsh-hints
zinit load l-umaca/omz-fluxcd-plugin
zinit load macunha1/zsh-terraform
zinit load zsh-users/zsh-autosuggestions
zinit load molovo/tipz

# Install rtx version manager (replacement for asdf)
# zinit ice from"gh-r" as"command" mv"rtx* -> rtx" \
#   atclone'./rtx complete -s zsh > _rtx' atpull'%atclone'
# zinit light jdxcode/rtx
# eval "$(rtx activate zsh)"

# Setup Vi mode
zinit ice depth=1
zinit light jeffreytse/zsh-vi-mode

# install zoxide
# rtx global zoxide@0.9.0 &>/dev/null
# zinit light ajeetdsouza/zoxide

# Setup direnv
# eval "$(rtx exec direnv -- direnv hook zsh)"

# A shortcut for asdf managed direnv.
# direnv() { rtx exec direnv -- direnv "$@"; }

zinit snippet 'https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/aws/aws.plugin.zsh'
zinit snippet 'https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/command-not-found/command-not-found.plugin.zsh'

# For postponing loading `fzf`
zinit ice lucid wait
zinit snippet OMZP::fzf

# # Fix Mcfly downloading the wrong binary
# case $(uname) in
#   Darwin)
#     case $(uname -m) in
#       x86_64)
#         mcfly_os="*x86_64-apple-darwin*"
#       ;;
#       arm64)
#         mcfly_os="*aarch64*darwin*"
#       ;;
#     esac
#   ;;
#   Linux)
#     case $(uname -m) in
#       x86_64)
#         mcfly_os="*x86_64*linux*musl*"
#       ;;
#       arm64)
#         mcfly_os="*aarch64*linux*"
#       ;;
#     esac
#   ;;
# esac
#
# if [[ "$mcfly_os" == "*aarch64*darwin*" ]]; then
#   zinit ice lucid wait"0a" as"program" atclone"cargo build --release" pick"./target/release/mcfly" atload'eval "$(mcfly init zsh)"'
# else
#   zinit ice lucid wait"0a" from"gh-r" as"program" atload'eval "$(mcfly init zsh)"' bpick"${mcfly_os}"
# fi
# zinit light cantino/mcfly

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
