function sync-clanker --description "Sync main and clanker worktrees (push: clanker<-main, pull: main<-clanker)"
    set -l main_worktree ../main
    set -l clanker_worktree ../clanker

    switch $argv[1]
    case push
        # Get the branch checked out in main worktree
        set -l target_branch (git -C $main_worktree rev-parse --abbrev-ref HEAD)

        if test $status -ne 0
            echo "Failed to get branch from main worktree"
            return 1
        end
        echo "Resetting clanker branch to $target_branch..."

        # Hard reset clanker branch to the target branch
        git -C $clanker_worktree reset --hard $target_branch

    case pull
        # Get the branch checked out in clanker worktree
        set -l source_branch (git -C $clanker_worktree rev-parse --abbrev-ref HEAD)

        if test $status -ne 0
            echo "Failed to get branch from clanker worktree"
            return 1
        end
        echo "Soft-resetting main branch to $source_branch (bringing clanker's commits)..."

        # Soft reset main branch to clanker's branch, preserving main's current
        # staged/unstaged changes (reset --soft never touches the index or working tree).
        git -C $main_worktree reset --soft $source_branch
        or begin
            echo "Failed to reset main branch to $source_branch"
            return 1
        end

        # Carry over clanker's staged changes onto main's index/working tree.
        if not git -C $clanker_worktree diff --cached --quiet
            echo "Applying clanker's staged changes to main..."
            git -C $clanker_worktree diff --cached | git -C $main_worktree apply --cached
            or echo "Warning: failed to apply clanker's staged changes to main"
        end

        # Carry over clanker's unstaged changes onto main's working tree only.
        if not git -C $clanker_worktree diff --quiet
            echo "Applying clanker's unstaged changes to main..."
            git -C $clanker_worktree diff | git -C $main_worktree apply
            or echo "Warning: failed to apply clanker's unstaged changes to main"
        end

    case '*'
        echo "Usage: sync-clanker push|pull"
        return 1
    end
end
