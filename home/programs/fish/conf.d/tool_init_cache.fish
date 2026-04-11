# Cache shell integration init scripts keyed by the resolved binary path (nix store path).
# On a nix upgrade the store path changes, automatically invalidating the cache.
# Sources the cached file directly; only reruns the tool on first use or after upgrades.

if not status is-interactive
    return
end

set -g __init_dir ~/.cache/fish/init

function __fish_init_cached -a name cmd
    set -l cache $__init_dir/$name.fish
    set -l key_f $__init_dir/$name.key
    if test -f $cache -a -f $key_f
        set -l k
        read -l k < $key_f
        if test "$k" = "$cmd"
            source $cache
            return
        end
    end
    mkdir -p $__init_dir
    eval $cmd > $cache 2>/dev/null
    echo $cmd > $key_f
    source $cache
end

if type -q carapace
    set -l _bin (path resolve (command -v carapace) 2>/dev/null)
    test -n "$_bin"; and __fish_init_cached carapace "$_bin _carapace fish"
end

if type -q zoxide
    set -l _bin (path resolve (command -v zoxide) 2>/dev/null)
    test -n "$_bin"; and __fish_init_cached zoxide "$_bin init fish"
end

if type -q direnv
    set -l _bin (path resolve (command -v direnv) 2>/dev/null)
    test -n "$_bin"; and __fish_init_cached direnv "$_bin hook fish"
end

# McFly: cache the init script but replace the slow dd|tr|head session ID pipeline
# with fish's built-in random (saves ~60ms on every startup, not just after first run).
if type -q mcfly
    set -l _mcfly (path resolve (command -v mcfly) 2>/dev/null)
    if test -n "$_mcfly"
        set -l _cache $__init_dir/mcfly.fish
        set -l _key_f $__init_dir/mcfly.key
        set -l _valid 0
        if test -f $_cache -a -f $_key_f
            set -l _k
            read -l _k < $_key_f
            test "$_k" = "$_mcfly"; and set _valid 1
        end
        if test $_valid -eq 0
            mkdir -p $__init_dir
            # Strip the dd|tr|head session ID line — generated below with fish builtins
            $_mcfly init fish 2>/dev/null \
                | string replace -r 'set -gx MCFLY_SESSION_ID .*' '' \
                > $_cache
            echo $_mcfly > $_key_f
        end
        # 24-char alphanumeric session ID via fish builtins only — no subprocess, no seq
        set -l _a 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ
        set -gx MCFLY_SESSION_ID (string join '' \
            (for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24
                random choice 0 1 2 3 4 5 6 7 8 9 \
                    a b c d e f g h i j k l m n o p q r s t u v w x y z \
                    A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
            end))
        source $_cache

        # Ensure Ctrl-R mcfly binding survives fish_vi_key_bindings being called after conf.d
        function fish_user_key_bindings
            mcfly_key_bindings
        end
    end
end

set -e __init_dir
functions --erase __fish_init_cached
