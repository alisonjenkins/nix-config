function _tide_item_kubectl
    # Performance override: read kubeconfig directly instead of spawning kubectl.
    # Original: kubectl config view --minify --output jsonpath=... (~140ms on macOS under AV)
    # This version: pure fish file read, no subprocess (~<1ms)
    # Tradeoff: namespace is not shown (context only). Add it back if needed.
    set -l kconfig (string split : -- $KUBECONFIG)[1]
    if test -z "$kconfig"
        set kconfig $HOME/.kube/config
    end
    test -f "$kconfig" || return

    set -l context
    while read -l line
        if string match -qr '^current-context:' -- $line
            set context (string replace -r '^current-context:\s*' '' -- $line | string trim)
            break
        end
    end < $kconfig

    test -n "$context" || return
    _tide_print_item kubectl $tide_kubectl_icon' '$context
end
