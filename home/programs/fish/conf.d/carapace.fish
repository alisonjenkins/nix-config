# Carapace completion initialization
# Carapace provides completions for 1000+ commands

if type -q carapace
    # Initialize carapace completions
    set -gx CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense'
    
    # Load carapace completions
    mkdir -p ~/.config/fish/completions
    carapace --list | awk '{print $1}' | xargs -I{} touch ~/.config/fish/completions/{}.fish 2>/dev/null
    
    # Carapace completion for common tools
    carapace _carapace | source
end

# Additional completion enhancements
set -g fish_complete_style_dim yes
set -g fish_complete_style_secondary_background yes
