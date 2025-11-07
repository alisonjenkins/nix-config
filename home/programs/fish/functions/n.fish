function n --description 'Navigate using nnn and cd on quit'
    # Block nesting of nnn in subshells
    if test -n "$NNNLVL" && test "$NNNLVL" -ge 1
        echo "nnn is already running"
        return
    end

    # Set the temp file for cd on quit
    set -gx NNN_TMPFILE "$XDG_CONFIG_HOME/nnn/.lastd"

    # Run nnn with all arguments
    command nnn $argv

    # Change directory if the temp file exists
    if test -f "$NNN_TMPFILE"
        source "$NNN_TMPFILE"
        rm -f "$NNN_TMPFILE"
    end
end
