function tide_bench --description "Benchmark Tide prompt items to identify slow components"
    if not git -C . rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "Warning: not in a git repo — git item timing will be near-zero"
        echo "Re-run from a git repo for realistic git timing."
        echo ""
    end

    echo "=== Tide item timing ==="
    echo "(Run from a git repo. Run twice — first may be slower due to cold disk cache.)"
    echo ""

    # Fish `time` builtin: measures wall-clock time in-process, no subprocess needed.
    # Item stdout suppressed; time stats print to stderr (visible in terminal).
    set -l items git status cmd_duration context jobs direnv gcloud kubectl terraform aws nix_shell
    for item in $items
        if functions -q __tide_item_$item
            echo "--- $item ---"
            time __tide_item_$item >/dev/null
        else
            echo "--- $item --- (function not loaded)"
        end
    end
end
