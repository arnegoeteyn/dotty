if status is-interactive
    set -gx EDITOR hx
    # Commands to run in interactive sessions can go here
end

starship init fish | source
