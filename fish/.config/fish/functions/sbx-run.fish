function sbx-run --description "Run (or create then run) a docker sandbox for a repo"
    set -l repo $argv[1]
    if test -z "$repo"
        echo "Usage: sbx-run <repo-name>"
        return 1
    end

    set -l name "nova-$repo"

    sbx run --name $name
    if test $status -eq 0
        return 0
    end

    echo "The docker sandbox does not exist yet, run the following to create it"
    echo "sbx env create --auto-approve --env-arg repo=$repo /Users/arne/Documents/itsme-tools/docker-sandbox/sbxenv.yaml"

    read -P "Create the sandbox now? [y/N] " ans
    if test "$ans" = "y"
        sbx env create --auto-approve --env-arg repo=$repo /Users/arne/Documents/itsme-tools/docker-sandbox/sbxenv.yaml
        and sbx run --name $name
    end
end
