# This is a function for switching directory using nnn
# it is similar to rcd but using nnn instead of ranger.
n ()
{
    # Block nesting of nnn in subshells
    if [ -n $NNNLVL ] && [ "${NNNLVL:-0}" -ge 1 ]; then
        echo "nnn is already running"
        return
    fi

    # The default behaviour is to cd on quit (nnn checks if NNN_TMPFILE is set)
    # To cd on quit only on ^G, remove the "export" as in:
    #     NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"
    # NOTE: NNN_TMPFILE is fixed, should not be modified
    export NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"

    # Unmask ^Q (, ^V etc.) (if required, see `stty -a`) to Quit nnn
    # stty start undef
    # stty stop undef
    # stty lwrap undef
    # stty lnext undef

    nnn "$@"

    if [ -f "$NNN_TMPFILE" ]; then
            . "$NNN_TMPFILE"
            rm -f "$NNN_TMPFILE" > /dev/null
    fi
}

# This is a function for switching directory using yazi
# it is similar to the n function above but using yazi instead of nnn.
y ()
{
    # # Block nesting of nnn in subshells
    # if [ -n $NNNLVL ] && [ "${NNNLVL:-0}" -ge 1 ]; then
    #     echo "nnn is already running"
    #     return
    # fi

    export YAZI_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/yazi/.lastd"
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/yazi"

    yazi "--cwd-file $YAZI_TMPFILE $@"

    if [ -f "$YAZI_TMPFILE" ]; then
            . "$YAZI_TMPFILE"
            rm -f "$YAZI_TMPFILE" > /dev/null
    fi
}
