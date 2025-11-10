# Fish completion for just
# Dynamically completes recipe names from justfile

function __fish_just_recipes
    set -l path (pwd)
    set -l nearest_justfile ""
    
    # Search for justfile in current and parent directories
    while test "$path" != "/"
        if test -f "$path/justfile"
            set nearest_justfile "$path/justfile"
            break
        else if test -f "$path/.justfile"
            set nearest_justfile "$path/.justfile"
            break
        end
        set path (dirname "$path")
    end
    
    # If justfile found, list recipes
    if test -n "$nearest_justfile"
        just --list --list-heading "" --justfile "$nearest_justfile" | awk '{print $1}'
    end
end

# Complete recipe names for just command
complete -c just -f -a '(__fish_just_recipes)'

# Complete recipe names for 'j' alias if you use it
complete -c j -f -a '(__fish_just_recipes)'
