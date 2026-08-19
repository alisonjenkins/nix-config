# shellcheck shell=bash
# Sourced by checks/*.sh. Consistent finding output + fix-confirmation gate.

FINDINGS_COUNT=0

report_pass() {
    printf '  \033[32mPASS\033[0m  %s\n' "$1"
}

# report_fail <description> [<diff-or-detail-text>]
report_fail() {
    FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
    printf '  \033[31mFAIL\033[0m  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '%s\n' "$2" | sed 's/^/        /'
    fi
}

report_skip() {
    printf '  \033[33mSKIP\033[0m  %s\n' "$1"
}

# confirm_fix <description> <apply-fn> [args...]
# No-op unless DO_FIX=true. Prompts y/n per finding; never batch-applies.
confirm_fix() {
    local desc="$1"; shift
    local apply_fn="$1"; shift
    if [[ "${DO_FIX:-false}" != "true" ]]; then
        return 0
    fi
    local reply
    read -r -p "  Apply fix: $desc? [y/N] " reply
    case "$reply" in
        y|Y)
            if "$apply_fn" "$@"; then
                echo "  applied."
            else
                echo "  fix failed — see error above." >&2
            fi
            ;;
        *)
            echo "  skipped."
            ;;
    esac
}
