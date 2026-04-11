function _tide_item_git
    # Performance override: read git metadata directly from .git/ — no git subprocess.
    # Original: multiple git calls including git status --porcelain (~50-125ms on macOS under AV)
    # This version: pure file reads, no subprocess (~<1ms)
    #
    # What we keep:   branch name, detached HEAD hash, in-progress operation (merge/rebase/etc), stash indicator
    # What we drop:   dirty/staged/untracked counts, upstream ahead/behind
    #                 (these require git status / rev-list — unavoidable subprocess cost)

    # Walk up to find the .git directory
    set -l git_dir
    set -l dir (pwd)
    while true
        if test -f "$dir/.git"
            # Submodule: .git is a file like "gitdir: ../.git/modules/foo"
            set -l ref (string replace 'gitdir: ' '' (string trim (cat "$dir/.git")))
            if string match -q '/*' $ref
                set git_dir $ref
            else
                set git_dir "$dir/$ref"
            end
            break
        else if test -d "$dir/.git"
            set git_dir "$dir/.git"
            break
        end
        set -l parent (string replace -r '/[^/]+$' '' $dir)
        test "$parent" = "$dir" && return  # reached filesystem root
        set dir $parent
    end

    test -f "$git_dir/HEAD" || return

    # Read branch / commit reference
    set -l head (string trim (cat "$git_dir/HEAD"))
    set -l location
    if string match -qr '^ref: refs/heads/' $head
        set location (string replace 'ref: refs/heads/' '' $head \
            | string shorten -m$tide_git_truncation_length)
    else if string match -qr '^ref: refs/tags/' $head
        set location '#'(string replace 'ref: refs/tags/' '' $head \
            | string shorten -m$tide_git_truncation_length)
    else
        # Detached HEAD — show short hash
        set location '@'(string sub -l 7 $head)
    end

    # In-progress operation (merge, rebase, cherry-pick, etc.) — file existence checks only
    set -l operation
    set -l step
    set -l total_steps
    if test -d "$git_dir/rebase-merge"
        if test -f "$git_dir/rebase-merge/msgnum"
            set step (string trim (cat "$git_dir/rebase-merge/msgnum"))
            set total_steps (string trim (cat "$git_dir/rebase-merge/end"))
        end
        test -f "$git_dir/rebase-merge/interactive" && set operation rebase-i || set operation rebase-m
    else if test -d "$git_dir/rebase-apply"
        if test -f "$git_dir/rebase-apply/next"
            set step (string trim (cat "$git_dir/rebase-apply/next"))
            set total_steps (string trim (cat "$git_dir/rebase-apply/last"))
        end
        if test -f "$git_dir/rebase-apply/rebasing"
            set operation rebase
        else if test -f "$git_dir/rebase-apply/applying"
            set operation am
        else
            set operation am/rebase
        end
    else if test -f "$git_dir/MERGE_HEAD"
        set operation merge
    else if test -f "$git_dir/CHERRY_PICK_HEAD"
        set operation cherry-pick
    else if test -f "$git_dir/REVERT_HEAD"
        set operation revert
    else if test -f "$git_dir/BISECT_LOG"
        set operation bisect
    end

    # Stash — just whether one exists, not how many
    set -l stash_indicator
    test -f "$git_dir/refs/stash" && set stash_indicator ' *'

    # Set background colour based on operation (mirrors tide's urgent/normal logic)
    if test -n "$operation"
        set -g tide_git_bg_color $tide_git_bg_color_urgent
    end

    _tide_print_item git $_tide_location_color$tide_git_icon' ' (
        set_color white; echo -ns $location
        set_color $tide_git_color_operation; echo -ns ' '$operation ' '$step/$total_steps
        set_color $tide_git_color_stash; echo -ns $stash_indicator
    )
end
