# Navigation aliases
# Note: 'alias -- -' doesn't work in Fish, use 'prevd' or 'cd -' directly instead
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias cdd='cd ~/Downloads/'
alias cdg='cd ~/git/'
alias cdot='cd ~/.local/share/chezmoi'
alias cdgo='cd $GOPATH'

# Generate SHA-512 Password hash
alias pwhash='python -c "import crypt,getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512)))"'

# Archlinux aliases
alias makepkg='chrt --idle 0 ionice -c idle makepkg'

# Docker/Podman overrides
if command -v podman &>/dev/null
    alias fpm='podman run --rm -v "$WORKSPACE:/source" -v /etc/passwd:/etc/passwd:ro --user=(id -u):(id -g) claranet/fpm'
    alias saws='podman run -it --rm -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN -e AWS_SECURITY_TOKEN=$AWS_SECURITY_TOKEN -e ASSUMED_ROLE=$ASSUMED_ROLE -v $HOME/.aws:/root/.aws joshdvir/saws'
else
    alias fpm='docker run --rm -v "$WORKSPACE:/source" -v /etc/passwd:/etc/passwd:ro --user=(id -u):(id -g) claranet/fpm'
    alias saws='docker run -it --rm -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN -e AWS_SECURITY_TOKEN=$AWS_SECURITY_TOKEN -e ASSUMED_ROLE=$ASSUMED_ROLE -v $HOME/.aws:/root/.aws joshdvir/saws'
end

# fd alias for Ubuntu
if command -v fdfind &>/dev/null
    alias fd='fdfind'
end

# SSH key aliases
alias key='ssh-add ~/.ssh/ssh_keys/id_bashton_alan'
alias keyaur='ssh-add ~/.ssh/ssh_keys/id_aur'
alias keyb='ssh-add ~/.ssh/ssh_keys/id_bashton'
alias keycl='ssh-add -D'
alias keyp='ssh-add ~/.ssh/ssh_keys/id_personal'
alias keypa='ssh-add ~/.ssh/ssh_keys/id_alan-aws'
alias keypo='ssh-add ~/.ssh/ssh_keys/id_personal_old'
alias keyk='ssh-add ~/.ssh/ssh_keys/id_krystal'
alias kmse='set -gx EYAML_CONFIG $PWD/.kms-eyaml.yaml'

# Neovim
if command -v nvim &>/dev/null
    alias vim='nvim'
    alias vi='nvim'
else if command -v vim &>/dev/null
    alias vi='vim'
end

# Misc aliases
alias j='just'

# Platform-specific ls aliases
if test (uname -s) = "Darwin"
    alias ll='ls -G'
    alias ls='ls -G'
    if command -v tree &>/dev/null
        alias lt='tree -C'
    end
else
    if command -v eza &>/dev/null
        alias ll='eza -l --grid --git'
        alias ls='eza'
        alias lt='eza --tree --git --long'
    else
        alias ll='ls --color=auto -l'
        alias ls='ls --color=auto'
        if command -v tree &>/dev/null
            alias lt='tree -C'
        end
    end
end

# Kubernetes aliases
alias watchhr='watch "kubectl get hr -A"'

# Nix aliases
alias nfr='nix run .'
alias nfti='nix-flake-template-init'
alias nfu='nix flake update'
alias nfuc='nix flake update --commit-lock-file'
alias nsg='nix store gc'
alias nsgo='nix store gc && nix store optimise'
alias nso='nix store optimise'

# Terragrunt aliases
alias tg='terragrunt --terragrunt-forward-tf-stdout --terragrunt-non-interactive'
alias tgr='terragrunt run-all --terragrunt-forward-tf-stdout --terragrunt-non-interactive'

# Go aliases
alias gb='go build'
alias gbw='watchexec --clear --exts go -- go build'
alias gtw='watchexec --clear --exts go -- go test'

# VPN
alias vpn='sudo openconnect --config ~/.config/openconnect/config'
