function compr --description "Show PR comments from the last commit with associated PR info"
    # Parse arguments using argparse
    argparse 'd/debug' 'p/pr=' 'b/branch=' 'h/help' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: compr [-d|--debug] (-p|--pr <number> | -b|--branch <name>)"
        echo ""
        echo "Options:"
        echo "  -p, --pr <number>     PR number to review"
        echo "  -b, --branch <name>   Branch name containing the PR"
        echo "  -d, --debug           Enable debug output"
        echo "  -h, --help            Show this help"
        return 0
    end

    set -l debug 0
    set -q _flag_debug; and set debug 1
    set -l pr_number "$_flag_pr"
    set -l branch_name "$_flag_branch"

    # Validate arguments
    if test -z "$pr_number" -a -z "$branch_name"
        echo (set_color red)"Error: Must specify either -p/--pr <number> or -b/--branch <name>"(set_color normal) >&2
        echo "Use -h for help" >&2
        return 1
    end

    if test -n "$pr_number" -a -n "$branch_name"
        echo (set_color red)"Error: Cannot specify both -p/--pr and -b/--branch"(set_color normal) >&2
        return 1
    end

    # Helper function for debug output
    function __pr_debug --no-scope-shadowing
        if test $debug -eq 1
            echo (set_color magenta)"[DEBUG] $argv"(set_color normal)
        end
    end

    # Helper function to get a specific line from a file
    function __get_file_line --no-scope-shadowing
        set -l file $argv[1]
        set -l line_num $argv[2]
        if test -f "$file"
            sed -n "$line_num"p "$file"
        end
    end

    # Helper function to flush pending comment
    function __flush_pending_comment --no-scope-shadowing
        if test -z "$pending_comment"
            return
        end
        set -l comment_body (string replace -r '^.*//\s*PR:\s*' '' -- "$pending_comment")
        set -l target_line_num (math $pending_line_num + 1)
        set -l following_line (__get_file_line "$pending_file" "$target_line_num")
        __pr_debug "Found PR comment: file=$pending_file line=$target_line_num body=$comment_body"

        set -a comment_files "$pending_file"
        set -a comment_lines "$target_line_num"
        set -a comment_bodies "$comment_body"

        echo (set_color yellow)"$pending_file:$pending_line_num"(set_color normal)
        echo (set_color cyan)"$pending_comment"(set_color normal)
        if test -n "$following_line"
            echo "  $target_line_num: $following_line"
        else
            echo "  (no following line)"
        end
        echo ""
        set pending_comment ""
    end

    # Get repo owner/name
    __pr_debug "Fetching repo info..."
    set -l repo_info (gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1)
    set -l repo_status $status
    __pr_debug "Repo info result (status=$repo_status): $repo_info"

    if test $repo_status -ne 0 -o -z "$repo_info"
        echo (set_color red)"Error: Failed to get repo info (is gh authenticated?)"(set_color normal) >&2
        if test $debug -eq 1
            echo (set_color red)"[DEBUG] gh repo view output: $repo_info"(set_color normal) >&2
        end
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 1
    end

    # Get PR info based on provided argument
    set -l pr_title ""
    set -l pr_url ""

    if test -n "$branch_name"
        # Lookup PR by branch name
        __pr_debug "Fetching PR for branch '$branch_name'..."
        set pr_number (gh pr list --head "$branch_name" --json number --jq '.[0].number' 2>&1)
        set -l pr_status $status
        __pr_debug "PR number result (status=$pr_status): $pr_number"

        if test -z "$pr_number" -o "$pr_number" = null
            echo (set_color red)"Error: No open PR found for branch '$branch_name'"(set_color normal) >&2
            functions -e __pr_debug __get_file_line __flush_pending_comment
            return 1
        end
    end

    # Get PR details using jq for reliable JSON parsing
    __pr_debug "Fetching PR details for #$pr_number..."
    set -l pr_title (gh pr view "$pr_number" --json title --jq '.title' 2>&1)
    set -l pr_title_status $status
    set -l pr_url (gh pr view "$pr_number" --json url --jq '.url' 2>&1)
    set -l pr_head (gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>&1)
    __pr_debug "PR title (status=$pr_title_status): $pr_title"
    __pr_debug "PR URL: $pr_url"
    __pr_debug "PR head branch: $pr_head"

    if test $pr_title_status -ne 0 -o -z "$pr_title"
        echo (set_color red)"Error: Could not find PR #$pr_number"(set_color normal) >&2
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 1
    end

    # Print PR information
    echo (set_color green)"PR #$pr_number:"(set_color normal)
    echo "  $pr_title"
    echo "  $pr_url"
    echo "  Branch: $pr_head"
    echo ""

    # Get the diff of the last commit, only added lines
    __pr_debug "Getting diff of last commit..."
    set -l diff_output (git show --no-color -U0 HEAD)
    __pr_debug "Diff output lines: "(count $diff_output)

    set -l current_file ""
    set -l hunk_start 0
    set -l line_offset 0
    set -l pending_comment ""
    set -l pending_line_num 0
    set -l pending_file ""

    # Arrays to store comment data for later submission
    set -l comment_files
    set -l comment_lines
    set -l comment_bodies

    # First pass: collect and show all PR comments
    echo (set_color green)"PR comments in last commit:"(set_color normal)
    echo ""

    for line in $diff_output
        # Track current file
        if string match -qr '^\+\+\+ b/(.*)' -- $line
            __flush_pending_comment

            set current_file (string replace -r '^\+\+\+ b/' '' -- $line | string trim)
            __pr_debug "Found file: '$current_file'"
            continue
        end

        # Track hunk position (new file line numbers)
        if string match -qr '^@@ .* \+([0-9]+)' -- $line
            __flush_pending_comment

            set hunk_start (string match -r '\+([0-9]+)' -- $line | tail -1)
            set line_offset 0
            __pr_debug "Hunk start: $hunk_start"
            continue
        end

        # Only process added lines
        if string match -qr '^\+[^+]' -- $line
            set -l content (string sub -s 2 -- $line)
            set -l current_line_num (math $hunk_start + $line_offset)

            __flush_pending_comment

            # Check if this line is a PR comment
            if string match -qr '//\s*PR:' -- $content
                set pending_comment (string trim -- $content)
                set pending_line_num $current_line_num
                set pending_file (string trim -- $current_file)
                __pr_debug "Stored pending comment: file='$pending_file' line=$pending_line_num"
            end

            set line_offset (math $line_offset + 1)
        end
    end

    # Handle case where PR comment was the last added line
    __flush_pending_comment

    set -l found_comments (count $comment_files)
    __pr_debug "Total comments found: $found_comments"

    if test $found_comments -eq 0
        echo (set_color yellow)"No PR comments found in the last commit"(set_color normal)
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 0
    end

    echo (set_color green)"Found $found_comments PR comment(s)"(set_color normal)
    echo ""

    # Prompt user to continue
    echo (set_color cyan)"Creating PR review for #$pr_number '$pr_title', continue? [y/N]"(set_color normal)
    read -l confirm

    if test "$confirm" != y -a "$confirm" != Y
        echo "Aborted."
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 0
    end

    # Start PR review and capture the review ID
    __pr_debug "Starting PR review..."
    __pr_debug "Command: gh pr-review review --start -R '$repo_info' '$pr_number'"

    set -l review_output (gh pr-review review --start -R "$repo_info" "$pr_number" 2>&1)
    set -l review_status $status
    __pr_debug "Review start result (status=$review_status): $review_output"

    if test $review_status -ne 0
        echo (set_color red)"Error: Failed to start PR review"(set_color normal) >&2
        if test $debug -eq 1
            echo (set_color red)"[DEBUG] Output: $review_output"(set_color normal) >&2
        end
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 1
    end

    # Parse the review ID from JSON output
    __pr_debug "Parsing review ID from output..."
    set -l review_id (echo "$review_output" | string join '' | string match -r '"id":\s*"([^"]+)"' | tail -1)
    __pr_debug "First parse attempt: $review_id"

    # Try parsing with string replace if first method failed
    if test -z "$review_id"
        set review_id (echo "$review_output" | string join '' | string replace -ra '.*"id":\s*"([^"]+)".*' '$1')
        __pr_debug "Second parse attempt: $review_id"
    end

    if test -z "$review_id"
        echo (set_color red)"Error: Failed to parse review ID from output"(set_color normal) >&2
        echo "Output was: $review_output" >&2
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 1
    end

    echo (set_color green)"Started PR review, ID: $review_id"(set_color normal)
    echo ""

    # Submit each comment
    echo (set_color green)"Submitting comments..."(set_color normal)

    for i in (seq (count $comment_files))
        set -l file $comment_files[$i]
        set -l line_num $comment_lines[$i]
        set -l body $comment_bodies[$i]

        echo "  Adding comment to $file:$line_num..."
        __pr_debug "Command: gh pr-review review --add-comment --review-id '$review_id' --path '$file' --line '$line_num' --body '$body' -R '$repo_info' '$pr_number'"

        set -l comment_output (gh pr-review review --add-comment \
            --review-id "$review_id" \
            --path "$file" \
            --line "$line_num" \
            --body "$body" \
            -R "$repo_info" \
            "$pr_number" 2>&1)
        set -l comment_status $status
        __pr_debug "Add comment result (status=$comment_status): $comment_output"

        if test $comment_status -ne 0
            echo (set_color red)"    Failed to add comment"(set_color normal) >&2
            if test $debug -eq 1
                echo (set_color red)"    [DEBUG] Output: $comment_output"(set_color normal) >&2
            end
        else
            echo (set_color green)"    Done"(set_color normal)
        end
    end

    echo ""
    echo (set_color green)"All comments added. Now submit the review."(set_color normal)
    echo ""

    # Ask user for review event type
    echo (set_color cyan)"Select review type:"(set_color normal)
    echo "  1) COMMENT"
    echo "  2) APPROVE"
    echo "  3) REQUEST_CHANGES"
    echo ""
    echo -n "Enter choice [1-3]: "
    read -l event_choice

    set -l review_event
    switch $event_choice
        case 1
            set review_event COMMENT
        case 2
            set review_event APPROVE
        case 3
            set review_event REQUEST_CHANGES
        case '*'
            echo (set_color red)"Invalid choice, defaulting to COMMENT"(set_color normal) >&2
            set review_event COMMENT
    end
    __pr_debug "Selected review event: $review_event"

    # Ask user for review body
    echo ""
    echo (set_color cyan)"Enter review summary (press Enter for empty):"(set_color normal)
    read -l review_body
    __pr_debug "Review body: $review_body"

    # Submit the review
    echo ""
    echo (set_color green)"Submitting review as $review_event..."(set_color normal)

    set -l submit_output
    set -l submit_status

    if test -n "$review_body"
        __pr_debug "Command: gh pr-review review --submit --review-id '$review_id' --event '$review_event' --body '$review_body' -R '$repo_info' '$pr_number'"
        set submit_output (gh pr-review review --submit \
            --review-id "$review_id" \
            --event "$review_event" \
            --body "$review_body" \
            -R "$repo_info" \
            "$pr_number" 2>&1)
        set submit_status $status
        __pr_debug "Submit result (status=$submit_status): $submit_output"
    else
        __pr_debug "Command: gh pr-review review --submit --review-id '$review_id' --event '$review_event' -R '$repo_info' '$pr_number'"
        set submit_output (gh pr-review review --submit \
            --review-id "$review_id" \
            --event "$review_event" \
            -R "$repo_info" \
            "$pr_number" 2>&1)
        set submit_status $status
        __pr_debug "Submit result (status=$submit_status): $submit_output"
    end

    if test $submit_status -ne 0
        echo (set_color red)"Error: Failed to submit review"(set_color normal) >&2
        if test $debug -eq 1
            echo (set_color red)"[DEBUG] Output: $submit_output"(set_color normal) >&2
        end
        functions -e __pr_debug __get_file_line __flush_pending_comment
        return 1
    end

    # Cleanup helper functions
    functions -e __pr_debug __get_file_line __flush_pending_comment

    echo ""
    echo (set_color green)"PR review submitted with $found_comments comment(s)"(set_color normal)
    echo ""
    echo (set_color cyan)"View PR: $pr_url"(set_color normal)
end
