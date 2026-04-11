function _tide_item_direnv
    # Performance override: skip spawning 'direnv status' (~19ms) on every render.
    # Original checks for a "denied" RC state, but if $DIRENV_DIR is set the RC
    # is already loaded/allowed — the denied state cannot occur in that context.
    # We simply show the icon whenever direnv is active.
    set -q DIRENV_DIR || return
    _tide_print_item direnv $tide_direnv_icon
end
