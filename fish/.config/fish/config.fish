if status is-interactive
    set -gx EDITOR ms
    # Commands to run in interactive sessions can go here
end

starship init fish | source
