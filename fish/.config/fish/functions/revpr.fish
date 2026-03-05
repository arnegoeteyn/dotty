function revpr --description "Checkout a PR branch in the review worktree"
    # Parse arguments
    set -l debug 0
    set -l mixed_reset 0
    set -l pr_number ""

    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case -d --debug
                set debug 1
            case -m --mixed
                set mixed_reset 1
            case -h --help
                echo "Usage: revpr [-d|--debug] [-m|--mixed] <pr-number>"
                echo ""
                echo "Checks out a PR branch in the 'review' worktree."
                echo ""
                echo "Options:"
                echo "  -m, --mixed    Perform mixed reset to merge base (unstage all PR changes)"
                echo "  -d, --debug    Enable debug output"
                echo "  -h, --help     Show this help"
                return 0
            case '*'
                if test -z "$pr_number"
                    set pr_number $argv[$i]
                end
        end
        set i (math $i + 1)
    end

    # Validate arguments
    if test -z "$pr_number"
        echo (set_color red)"Error: Must specify a PR number"(set_color normal)
        echo "Usage: revpr [-d|--debug] [-m|--mixed] <pr-number>"
        return 1
    end

    # Helper function for debug output
    function __pr_checkout_debug --no-scope-shadowing
        if test $debug -eq 1
            echo (set_color magenta)"[DEBUG] $argv"(set_color normal)
        end
    end

    # Verify we're in a git directory
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo (set_color red)"Error: Not in a git repository"(set_color normal)
        return 1
    end

    __pr_checkout_debug "In git repository"

    # Get the git root directory
    set -l git_root (git rev-parse --show-toplevel 2>&1)
    __pr_checkout_debug "Git root: $git_root"

    # Check if 'review' worktree exists
    set -l worktree_path "$git_root/../review"
    set -l worktree_list (git worktree list 2>&1)
    __pr_checkout_debug "Worktree list: $worktree_list"

    set -l review_worktree ""
    for line in $worktree_list
        if string match -q "*review*" -- $line
            set review_worktree (echo $line | string split ' ' | head -1)
            break
        end
    end

    if test -z "$review_worktree"
        echo (set_color red)"Error: No 'review' worktree found"(set_color normal)
        echo "Create one with: git worktree add ../review <branch>"
        return 1
    end

    __pr_checkout_debug "Review worktree path: $review_worktree"

    # Get PR details
    __pr_checkout_debug "Fetching PR #$pr_number details..."

    set -l pr_head (gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>&1)
    set -l pr_status $status
    __pr_checkout_debug "PR head branch (status=$pr_status): $pr_head"

    if test $pr_status -ne 0 -o -z "$pr_head" -o "$pr_head" = null
        echo (set_color red)"Error: Could not find PR #$pr_number"(set_color normal)
        if test $debug -eq 1
            echo (set_color red)"[DEBUG] Output: $pr_head"(set_color normal)
        end
        return 1
    end

    set -l pr_base (gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>&1)
    __pr_checkout_debug "PR base branch: $pr_base"

    set -l pr_title (gh pr view "$pr_number" --json title --jq '.title' 2>&1)
    __pr_checkout_debug "PR title: $pr_title"

    set -l pr_body (gh pr view "$pr_number" --json body --jq '.body' 2>&1)
    __pr_checkout_debug "PR body: $pr_body"

    # Print PR info
    echo (set_color green)"PR #$pr_number: $pr_title"(set_color normal)
    echo "  Head branch: $pr_head"
    echo "  Base branch: $pr_base"
    
    if test -n "$pr_body" -a "$pr_body" != "null" -a "$pr_body" != ""
        echo ""
        echo (set_color yellow)"Description:"(set_color normal)
        echo "$pr_body"
    end
    echo ""

    # Fetch latest changes
    echo (set_color cyan)"Fetching latest changes..."(set_color normal)
    __pr_checkout_debug "Command: git fetch origin $pr_head:$pr_head"

    set -l fetch_output (git fetch origin "$pr_head":"$pr_head" 2>&1)
    set -l fetch_status $status
    __pr_checkout_debug "Fetch result (status=$fetch_status): $fetch_output"

    # Also fetch base branch
    __pr_checkout_debug "Command: git fetch origin $pr_base:$pr_base"
    set -l fetch_base_output (git fetch origin "$pr_base":"$pr_base" 2>&1)
    __pr_checkout_debug "Fetch base result: $fetch_base_output"

    # Hard reset review worktree to PR branch (stays on review branch)
    echo (set_color cyan)"Hard resetting review worktree to PR branch..."(set_color normal)
    __pr_checkout_debug "Command: git -C '$review_worktree' reset --hard origin/$pr_head"

    set -l reset_hard_output (git -C "$review_worktree" reset --hard "origin/$pr_head" 2>&1)
    set -l reset_hard_status $status
    __pr_checkout_debug "Reset hard result (status=$reset_hard_status): $reset_hard_output"

    if test $reset_hard_status -ne 0
        echo (set_color red)"Error: Failed to hard reset to 'origin/$pr_head'"(set_color normal)
        if test $debug -eq 1
            echo (set_color red)"[DEBUG] Output: $reset_hard_output"(set_color normal)
        end
        return 1
    end

    echo (set_color green)"Hard reset to: origin/$pr_head"(set_color normal)

    # Optionally perform mixed reset to merge base
    if test $mixed_reset -eq 1
        # Find the merge base between PR branch and base branch
        __pr_checkout_debug "Finding merge base between origin/$pr_head and origin/$pr_base..."
        set -l merge_base (git merge-base "origin/$pr_head" "origin/$pr_base" 2>&1)
        set -l merge_base_status $status
        __pr_checkout_debug "Merge base result (status=$merge_base_status): $merge_base"

        if test $merge_base_status -ne 0 -o -z "$merge_base"
            echo (set_color red)"Error: Failed to find merge base"(set_color normal)
            if test $debug -eq 1
                echo (set_color red)"[DEBUG] Output: $merge_base"(set_color normal)
            end
            return 1
        end

        # Perform mixed reset to merge base
        echo (set_color cyan)"Performing mixed reset to merge base..."(set_color normal)
        __pr_checkout_debug "Command: git -C '$review_worktree' reset $merge_base"

        set -l reset_output (git -C "$review_worktree" reset "$merge_base" 2>&1)
        set -l reset_status $status
        __pr_checkout_debug "Reset result (status=$reset_status): $reset_output"

        if test $reset_status -ne 0
            echo (set_color red)"Error: Failed to reset to merge base"(set_color normal)
            if test $debug -eq 1
                echo (set_color red)"[DEBUG] Output: $reset_output"(set_color normal)
            end
            return 1
        end

        echo ""
        echo (set_color green)"Review worktree ready!"(set_color normal)
        echo "  Path: $review_worktree"
        echo "  Merge base: $merge_base"
        echo ""
        echo "All PR changes are now unstaged in the review worktree."
    else
        echo ""
        echo (set_color green)"Review worktree ready!"(set_color normal)
        echo "  Path: $review_worktree"
        echo "  Branch: origin/$pr_head"
    end

    # Store PR number for compr to use later
    set -l pr_review_file "$review_worktree/.pr_review"
    echo "$pr_number" > "$pr_review_file"
    __pr_checkout_debug "Stored PR number in: $pr_review_file"

    # Change to review worktree directory
    __pr_checkout_debug "Changing directory to: $review_worktree"
    cd "$review_worktree"
    echo (set_color cyan)"Changed directory to: "(set_color normal)"$review_worktree"
end
