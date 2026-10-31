function pgh --description "Set git configuration to personal github"
    git config user.name "Arne Goeteyn"
    git config user.email "goeteynarne@gmail.com"

    # Route GitHub remotes through the privategithub ssh alias (personal key).
    for remote in (git remote)
        set -l url (git remote get-url $remote)
        set -l new (string replace -r '^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)' 'git@privategithub:' -- $url)
        if test "$new" != "$url"
            git remote set-url $remote $new
            echo "$remote: $new"
        end
    end
end
