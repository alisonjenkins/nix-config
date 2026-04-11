# Carapace completion initialization
# Carapace provides completions for 1000+ commands

if type -q carapace
    set -gx CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'
end

# Additional completion enhancements
set -g fish_complete_style_dim yes
set -g fish_complete_style_secondary_background yes
