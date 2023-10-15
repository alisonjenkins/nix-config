autoload -Uz compinit
autoload -Uz bashcompinit
zstyle ':completion:*' menu select

# Auto complete with case insenstivity
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

zmodload zsh/complist
compinit
bashcompinit
_comp_options+=(globdots)		# Include hidden files.
